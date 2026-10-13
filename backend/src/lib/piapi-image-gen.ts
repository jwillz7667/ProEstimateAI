import { env } from "../config/env";
import { logger } from "../config/logger";
import { aspectRatioForProjectType, aspectRatioForReferencePhoto } from "./image-framing";
import type {
  GeneratedImage,
  ImageGenContext,
  ReferencePhoto,
} from "./image-gen";
import { toPromptContext } from "./image-gen";
import { getImageEditPrompt, getImagePrompt } from "./prompts";

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
 * Reference edits require both the image bytes (for source dimensions) and
 * a publicly accessible URL pointing to that same image (for PiAPI's input).
 * An incomplete reference is rejected rather than becoming text-to-image.
 */
export interface PiAPIGenerateOptions {
  userPrompt: string;
  context: ImageGenContext;
  referencePhoto?: ReferencePhoto;
  referenceAssetUrl?: string;
}

/**
 * Generate a remodel preview image using PiAPI Nano Banana 2.1.
 *
 * Flow: create task → poll until complete → download image → return base64.
 * Primary model: nano-banana-2.1.
 * Fallback within PiAPI: nano-banana-2 if 2.1 is unavailable.
 */
export async function generatePreviewImagePiAPI(
  options: PiAPIGenerateOptions,
): Promise<GeneratedImage | null> {
  const { userPrompt, context, referencePhoto, referenceAssetUrl } = options;
  const startMs = Date.now();

  // The URL supplies PiAPI's image; the same image bytes supply its framing.
  // Refuse incomplete inputs instead of silently changing an edit into a new
  // scene, or guessing category framing for a URL whose dimensions are unknown.
  if ((referencePhoto || referenceAssetUrl) && (!referencePhoto || !referenceAssetUrl?.trim())) {
    logger.warn("PiAPI reference edit requires both image bytes and an asset URL");
    return null;
  }

  let aspectRatio: string;
  try {
    aspectRatio = referencePhoto
      ? await aspectRatioForReferencePhoto(referencePhoto)
      : aspectRatioForProjectType(context.projectType);
  } catch (err) {
    logger.warn({ err }, "PiAPI reference photo is unreadable — refusing generation");
    return null;
  }

  // Build prompt — same rich prompt as the Google GenAI path
  const prompt = buildPiAPIPrompt(userPrompt, context, !!referenceAssetUrl);

  // Build image_urls from the reference photo (PiAPI needs public URLs)
  const imageUrls: string[] = [];
  if (referenceAssetUrl) {
    imageUrls.push(referenceAssetUrl);
  }

  const taskType = "nano-banana-2.1";

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
    // Attempt with Nano Banana 2.1 first.
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
  } catch (primaryErr) {
    logger.warn(
      { err: primaryErr, taskType },
      "PiAPI nano-banana-2.1 failed, trying nano-banana-2 fallback",
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
// edits use the camera-locked `getImageEditPrompt` and deliberately do NOT
// splice in `getImagePrompt` — per-type modules carry framing language
// ("16:9 from the curb at golden hour") that overrode the soft "keep
// angle" hint and produced reframed afters.

function buildPiAPIPrompt(
  userPrompt: string,
  context: ImageGenContext,
  hasReferencePhoto: boolean,
): string {
  const promptCtx = toPromptContext(context);

  if (hasReferencePhoto) {
    const editFrame = getImageEditPrompt(promptCtx);
    return `${editFrame}

CONTRACTOR'S REQUEST (this is what to build/change in the existing scene)
"${userPrompt}"

Reinforcement — read before generating:
- The output is the SAME photograph with the renovation completed in
  place. It is NOT a new shot.
- Preserve the input's camera position, focal length, height, and tilt
  pixel-for-pixel. The before/after slider must blend the two on top of
  each other.
- Match the input's exposure, white balance, time of day, and shadow
  direction.
- Touch ONLY the surfaces, materials, plantings, and built additions
  called out above. Leave everything else exactly as it appears in the
  source photo.
- Photorealistic. No text, labels, watermarks, or imagined neighbors.`;
  }

  const systemPrompt = getImagePrompt(promptCtx);
  return `${systemPrompt}

CONTRACTOR'S REQUEST
"${userPrompt}"

Photograph this completed project from the most flattering angle that
satisfies the framing rules above. Photorealistic only.`;
}
