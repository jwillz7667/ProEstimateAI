import { env } from '../config/env';
import { logger } from '../config/logger';
import type { GeneratedImage, ImageGenContext, ReferencePhoto } from './image-gen';

const PIAPI_BASE_URL = 'https://api.piapi.ai/api/v1';
const POLL_INTERVAL_MS = 3000;
const MAX_POLL_ATTEMPTS = 40; // 40 * 3s = 2 minutes max
const IMAGE_DOWNLOAD_TIMEOUT_MS = 30000;

// ─── PiAPI Task Types ───────────────────────────────────────────────────────

interface PiAPITaskInput {
  prompt: string;
  image_urls?: string[];
  output_format: string;
  aspect_ratio: string;
  resolution: string;
  safety_level?: string;
}

interface PiAPICreateRequest {
  model: string;
  task_type: string;
  input: PiAPITaskInput;
}

interface PiAPITaskResponse {
  code: number;
  message: string;
  data: {
    task_id: string;
    status: 'pending' | 'processing' | 'completed' | 'failed' | 'staged';
    output: {
      image_urls?: string[];
      image_url?: string;
    } | null;
    error?: {
      code: number;
      message: string;
      raw_message?: string;
    };
    meta?: {
      created_at: string;
      started_at: string | null;
      ended_at: string | null;
    };
  };
}

// ─── Aspect Ratio (shared logic) ────────────────────────────────────────────

function aspectRatioForProjectType(projectType: string): string {
  const type = projectType.toUpperCase();
  switch (type) {
    case 'EXTERIOR':
    case 'ROOFING':
    case 'SIDING':
      return '16:9';
    case 'BATHROOM':
      return '3:4';
    case 'KITCHEN':
    case 'ROOM_REMODEL':
    case 'FLOORING':
    case 'PAINTING':
    default:
      return '4:3';
  }
}

// ─── HTTP Helpers ───────────────────────────────────────────────────────────

async function piapiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const apiKey = env.PIAPI_API_KEY;
  if (!apiKey) {
    throw new Error('PIAPI_API_KEY is not configured');
  }

  const url = `${PIAPI_BASE_URL}${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
      ...options?.headers,
    },
  });

  if (!response.ok) {
    const text = await response.text().catch(() => 'no body');
    throw new Error(`PiAPI request failed: ${response.status} ${response.statusText} — ${text}`);
  }

  return response.json() as Promise<T>;
}

async function downloadImageAsBase64(imageUrl: string): Promise<{ base64Data: string; mimeType: string }> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), IMAGE_DOWNLOAD_TIMEOUT_MS);

  try {
    const response = await fetch(imageUrl, { signal: controller.signal });
    if (!response.ok) {
      throw new Error(`Image download failed: ${response.status} ${response.statusText}`);
    }

    const contentType = response.headers.get('content-type') || 'image/png';
    const arrayBuffer = await response.arrayBuffer();
    const base64Data = Buffer.from(arrayBuffer).toString('base64');

    return { base64Data, mimeType: contentType.split(';')[0].trim() };
  } finally {
    clearTimeout(timeout);
  }
}

// ─── Task Lifecycle ─────────────────────────────────────────────────────────

async function createTask(request: PiAPICreateRequest): Promise<string> {
  const result = await piapiFetch<PiAPITaskResponse>('/task', {
    method: 'POST',
    body: JSON.stringify(request),
  });

  if (result.code !== 200 || !result.data?.task_id) {
    throw new Error(`PiAPI create task failed: code=${result.code} message=${result.message}`);
  }

  return result.data.task_id;
}

async function pollTask(taskId: string): Promise<PiAPITaskResponse['data']> {
  for (let attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
    const result = await piapiFetch<PiAPITaskResponse>(`/task/${taskId}`);

    const status = result.data?.status;

    if (status === 'completed') {
      return result.data;
    }

    if (status === 'failed') {
      const errMsg = result.data?.error?.message || result.data?.error?.raw_message || 'Unknown error';
      throw new Error(`PiAPI task failed: ${errMsg}`);
    }

    // Still pending/processing — wait before next poll
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
  }

  throw new Error(`PiAPI task ${taskId} timed out after ${MAX_POLL_ATTEMPTS * POLL_INTERVAL_MS / 1000}s`);
}

// ─── Public API ─────────────────────────────────────────────────────────────

/**
 * Build a reference image URL from a base64 reference photo.
 * If a referenceAssetUrl is provided (publicly accessible), use that directly.
 * Otherwise, we can't send base64 to PiAPI — it requires URLs.
 */
export interface PiAPIGenerateOptions {
  userPrompt: string;
  context: ImageGenContext;
  referencePhoto?: ReferencePhoto;
  referenceAssetUrl?: string;
}

/**
 * Generate a remodel preview image using PiAPI Nano Banana Pro.
 *
 * Flow: create task → poll until complete → download image → return base64.
 * Primary model: nano-banana-pro (best quality, safety controls).
 * Fallback within PiAPI: nano-banana-2 if pro fails.
 */
export async function generatePreviewImagePiAPI(
  options: PiAPIGenerateOptions
): Promise<GeneratedImage | null> {
  const { userPrompt, context, referenceAssetUrl } = options;
  const startMs = Date.now();

  const aspectRatio = aspectRatioForProjectType(context.projectType);

  // Build prompt — same rich prompt as the Google GenAI path
  const prompt = buildPiAPIPrompt(userPrompt, context, !!referenceAssetUrl);

  // Build image_urls from the reference photo (PiAPI needs public URLs)
  const imageUrls: string[] = [];
  if (referenceAssetUrl) {
    imageUrls.push(referenceAssetUrl);
  }

  const taskType = 'nano-banana-pro';

  logger.info(
    { taskType, projectType: context.projectType, qualityTier: context.qualityTier, aspectRatio, hasRefPhoto: imageUrls.length > 0 },
    'Starting PiAPI image generation'
  );

  try {
    // Attempt with nano-banana-pro first
    const result = await attemptGeneration(taskType, prompt, imageUrls, aspectRatio);
    if (result) {
      const durationMs = Date.now() - startMs;
      logger.info({ durationMs, taskType, provider: 'piapi' }, 'PiAPI generation completed');
      return { ...result, durationMs };
    }
  } catch (proErr) {
    logger.warn({ err: proErr, taskType }, 'PiAPI nano-banana-pro failed, trying nano-banana-2 fallback');
  }

  // Fallback: try nano-banana-2 within PiAPI
  try {
    const fallbackResult = await attemptGeneration('nano-banana-2', prompt, imageUrls, aspectRatio);
    if (fallbackResult) {
      const durationMs = Date.now() - startMs;
      logger.info({ durationMs, taskType: 'nano-banana-2', provider: 'piapi-fallback' }, 'PiAPI fallback generation completed');
      return { ...fallbackResult, durationMs };
    }
  } catch (fallbackErr) {
    logger.error({ err: fallbackErr }, 'PiAPI nano-banana-2 fallback also failed');
  }

  return null;
}

async function attemptGeneration(
  taskType: string,
  prompt: string,
  imageUrls: string[],
  aspectRatio: string,
): Promise<Omit<GeneratedImage, 'durationMs'> | null> {
  const request: PiAPICreateRequest = {
    model: 'gemini',
    task_type: taskType,
    input: {
      prompt,
      output_format: 'png',
      aspect_ratio: aspectRatio,
      resolution: '2K',
      ...(imageUrls.length > 0 ? { image_urls: imageUrls } : {}),
      ...(taskType === 'nano-banana-pro' ? { safety_level: 'high' } : {}),
    },
  };

  const taskId = await createTask(request);
  logger.info({ taskId, taskType }, 'PiAPI task created, polling for completion');

  const completedTask = await pollTask(taskId);

  // Extract image URL from output
  const imageUrl =
    completedTask.output?.image_urls?.[0] ||
    completedTask.output?.image_url;

  if (!imageUrl) {
    logger.warn({ taskId, taskType }, 'PiAPI task completed but no image URL in output');
    return null;
  }

  // Download image and convert to base64
  const { base64Data, mimeType } = await downloadImageAsBase64(imageUrl);
  return { base64Data, mimeType };
}

// ─── Prompt Building ────────────────────────────────────────────────────────

function buildPiAPIPrompt(userPrompt: string, context: ImageGenContext, hasReferencePhoto: boolean): string {
  if (hasReferencePhoto) {
    const qualityTier = context.qualityTier.toLowerCase();
    const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();

    return `Edit this photo to show a completed ${projectType} remodel. ${userPrompt}

Keep the exact same room, same layout, same camera angle, same perspective, same windows and doors. Only change the finishes, materials, and fixtures to show a beautiful ${qualityTier}-grade ${projectType} renovation. The result must look like a real photo of this exact same space after a professional remodel. Photorealistic only, no text or labels.`;
  }

  // Build full system prompt for text-to-image
  return buildPiAPISystemPrompt(userPrompt, context);
}

function buildPiAPISystemPrompt(userPrompt: string, context: ImageGenContext): string {
  const qualityTierDescriptions: Record<string, string> = {
    budget: 'Clean and functional with cost-effective builder-grade materials — laminate countertops, basic ceramic tile, painted MDF cabinetry, chrome fixtures.',
    standard: 'Mid-range materials with tasteful design — quartz countertops, engineered hardwood or quality luxury vinyl plank flooring, semi-custom shaker cabinetry, brushed nickel or matte black fixtures.',
    premium: 'High-end finishes — natural marble or quartzite countertops, solid hardwood flooring, custom cabinetry with soft-close hardware, designer lighting fixtures, frameless glass shower enclosures.',
    luxury: 'Ultra-premium — exotic stone slabs with dramatic veining, bespoke millwork, statement chandelier lighting, imported European fixtures, architectural ceiling features.',
  };

  const tierDesc = qualityTierDescriptions[context.qualityTier.toLowerCase()] ?? qualityTierDescriptions['standard'];
  const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();

  let prompt = `Generate a single photorealistic photograph of a beautifully completed ${projectType} remodel. This image will be presented to a homeowner in a professional contractor's proposal.

Shoot the scene with a full-frame camera and a 28mm wide-angle lens at eye level. Frame using the rule of thirds. Keep all vertical lines straight.

Light with warm natural daylight through windows, supplemented by recessed downlights. Bright, inviting, aspirational mood.

Render every material with photorealistic detail — wood grain, stone veining, tile grout lines, metal reflections. The finish level is ${context.qualityTier.toLowerCase()} grade: ${tierDesc}

Project: "${context.projectTitle}" — a ${projectType} project.`;

  if (context.projectDescription) {
    prompt += `\nThe homeowner's vision: ${context.projectDescription}`;
  }
  if (context.squareFootage) {
    prompt += `\nSpace: approximately ${context.squareFootage} square feet.`;
  }
  if (context.dimensions) {
    prompt += `\nDimensions: ${context.dimensions}.`;
  }
  if (context.materials && context.materials.length > 0) {
    prompt += `\n\nMaterials that MUST be visible:\n${context.materials.map((m, i) => `${i + 1}. ${m.name}${m.category ? ` (${m.category})` : ''}`).join('\n')}`;
  }

  prompt += `\n\nThe homeowner wants: "${userPrompt}"

Show only the finished, move-in-ready result. No construction debris, tools, people, pets, text, labels, watermarks, or logos. Single photorealistic image only.`;

  return prompt;
}
