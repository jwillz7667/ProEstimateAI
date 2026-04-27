import { env } from "../config/env";
import { logger } from "../config/logger";
import type {
  GeneratedImage,
  ImageGenContext,
  ReferencePhoto,
} from "./image-gen";
import { toPromptContext } from "./image-gen";
import { getImagePrompt } from "./prompts";

const PIAPI_BASE_URL = "https://api.piapi.ai/api/v1";
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
    status: "pending" | "processing" | "completed" | "failed" | "staged";
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
    case "EXTERIOR":
    case "ROOFING":
    case "SIDING":
    case "LANDSCAPING":
    case "LAWN_CARE":
      return "16:9";
    case "BATHROOM":
      return "3:4";
    case "KITCHEN":
    case "ROOM_REMODEL":
    case "FLOORING":
    case "PAINTING":
    default:
      return "4:3";
  }
}

// ─── HTTP Helpers ───────────────────────────────────────────────────────────

async function piapiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const apiKey = env.PIAPI_API_KEY;
  if (!apiKey) {
    throw new Error("PIAPI_API_KEY is not configured");
  }

  const url = `${PIAPI_BASE_URL}${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-API-Key": apiKey,
      ...options?.headers,
    },
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "no body");
    throw new Error(
      `PiAPI request failed: ${response.status} ${response.statusText} — ${text}`,
    );
  }

  return response.json() as Promise<T>;
}

async function downloadImageAsBase64(
  imageUrl: string,
): Promise<{ base64Data: string; mimeType: string }> {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    IMAGE_DOWNLOAD_TIMEOUT_MS,
  );

  try {
    const response = await fetch(imageUrl, { signal: controller.signal });
    if (!response.ok) {
      throw new Error(
        `Image download failed: ${response.status} ${response.statusText}`,
      );
    }

    const contentType = response.headers.get("content-type") || "image/png";
    const arrayBuffer = await response.arrayBuffer();
    const base64Data = Buffer.from(arrayBuffer).toString("base64");

    return { base64Data, mimeType: contentType.split(";")[0].trim() };
  } finally {
    clearTimeout(timeout);
  }
}

// ─── Task Lifecycle ─────────────────────────────────────────────────────────

async function createTask(request: PiAPICreateRequest): Promise<string> {
  const result = await piapiFetch<PiAPITaskResponse>("/task", {
    method: "POST",
    body: JSON.stringify(request),
  });

  if (result.code !== 200 || !result.data?.task_id) {
    throw new Error(
      `PiAPI create task failed: code=${result.code} message=${result.message}`,
    );
  }

  return result.data.task_id;
}

async function pollTask(taskId: string): Promise<PiAPITaskResponse["data"]> {
  for (let attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
    const result = await piapiFetch<PiAPITaskResponse>(`/task/${taskId}`);

    const status = result.data?.status;

    if (status === "completed") {
      return result.data;
    }

    if (status === "failed") {
      const errMsg =
        result.data?.error?.message ||
        result.data?.error?.raw_message ||
        "Unknown error";
      throw new Error(`PiAPI task failed: ${errMsg}`);
    }

    // Still pending/processing — wait before next poll
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
  }

  throw new Error(
    `PiAPI task ${taskId} timed out after ${(MAX_POLL_ATTEMPTS * POLL_INTERVAL_MS) / 1000}s`,
  );
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
  options: PiAPIGenerateOptions,
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

  const taskType = "nano-banana-pro";

  logger.info(
    {
      taskType,
      projectType: context.projectType,
      qualityTier: context.qualityTier,
      aspectRatio,
      hasRefPhoto: imageUrls.length > 0,
    },
    "Starting PiAPI image generation",
  );

  try {
    // Attempt with nano-banana-pro first
    const result = await attemptGeneration(
      taskType,
      prompt,
      imageUrls,
      aspectRatio,
    );
    if (result) {
      const durationMs = Date.now() - startMs;
      logger.info(
        { durationMs, taskType, provider: "piapi" },
        "PiAPI generation completed",
      );
      return { ...result, durationMs };
    }
  } catch (proErr) {
    logger.warn(
      { err: proErr, taskType },
      "PiAPI nano-banana-pro failed, trying nano-banana-2 fallback",
    );
  }

  // Fallback: try nano-banana-2 within PiAPI
  try {
    const fallbackResult = await attemptGeneration(
      "nano-banana-2",
      prompt,
      imageUrls,
      aspectRatio,
    );
    if (fallbackResult) {
      const durationMs = Date.now() - startMs;
      logger.info(
        { durationMs, taskType: "nano-banana-2", provider: "piapi-fallback" },
        "PiAPI fallback generation completed",
      );
      return { ...fallbackResult, durationMs };
    }
  } catch (fallbackErr) {
    logger.error(
      { err: fallbackErr },
      "PiAPI nano-banana-2 fallback also failed",
    );
  }

  return null;
}

async function attemptGeneration(
  taskType: string,
  prompt: string,
  imageUrls: string[],
  aspectRatio: string,
): Promise<Omit<GeneratedImage, "durationMs"> | null> {
  const request: PiAPICreateRequest = {
    model: "gemini",
    task_type: taskType,
    input: {
      prompt,
      output_format: "png",
      aspect_ratio: aspectRatio,
      resolution: "2K",
      ...(imageUrls.length > 0 ? { image_urls: imageUrls } : {}),
      ...(taskType === "nano-banana-pro" ? { safety_level: "high" } : {}),
    },
  };

  const taskId = await createTask(request);
  logger.info(
    { taskId, taskType },
    "PiAPI task created, polling for completion",
  );

  const completedTask = await pollTask(taskId);

  // Extract image URL from output
  const imageUrl =
    completedTask.output?.image_urls?.[0] || completedTask.output?.image_url;

  if (!imageUrl) {
    logger.warn(
      { taskId, taskType },
      "PiAPI task completed but no image URL in output",
    );
    return null;
  }

  // Download image and convert to base64
  const { base64Data, mimeType } = await downloadImageAsBase64(imageUrl);
  return { base64Data, mimeType };
}

// ─── Prompt Building ────────────────────────────────────────────────────────
//
// PiAPI used to maintain its own slim system prompt for nano-banana. We've
// moved that to the per-ProjectType prompt library so the same trade-aware
// language drives both Google GenAI and PiAPI generations. Reference-photo
// edits append a tight preservation directive on top.

function buildPiAPIPrompt(
  userPrompt: string,
  context: ImageGenContext,
  hasReferencePhoto: boolean,
): string {
  const promptCtx = toPromptContext(context);
  const systemPrompt = getImagePrompt(promptCtx);

  if (hasReferencePhoto) {
    return `${systemPrompt}

EDIT INSTRUCTION
The provided photo is the actual property/room. Edit it in place: keep
the same camera angle, same vantage point, same structural elements
(walls, windows, roofline, lot boundaries, plant beds present). Only
change the finishes, plants, materials, and surfaces to show the
COMPLETED project as described below.

Contractor's request: "${userPrompt}"

Photorealistic only. No text, no labels, no watermarks.`;
  }

  return `${systemPrompt}

CONTRACTOR'S REQUEST
"${userPrompt}"

Photograph this completed project from the most flattering angle that
satisfies the framing rules above. Photorealistic only.`;
}
