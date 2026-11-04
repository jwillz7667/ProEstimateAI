import sharp from "sharp";
import { env } from "../config/env";
import { logger } from "../config/logger";
import { aspectRatioForProjectType } from "./image-framing";
import type { GeneratedImage, ReferencePhoto } from "./image-gen";

const QUEUE_ORIGIN = "https://queue.fal.run";
const MODEL = "fal-ai/flux-2/flash";
const LIFECYCLE_TIMEOUT_MS = 150_000;
const REQUEST_TIMEOUT_MS = 30_000;
const POLL_INTERVAL_MS = 1_000;
const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
const MAX_JSON_BYTES = 256 * 1024;
const MAX_OUTPUT_PIXELS = 1024 * 1024;
const MAX_INPUT_PIXELS = 64 * 1024 * 1024;

interface ImageSize { width: number; height: number }
interface FalTask {
  request_id: string;
  status_url: string;
  response_url: string;
  cancel_url: string;
}
interface FalStatus { status: string; error?: unknown; error_type?: unknown }
interface FalResult {
  images?: Array<{ url?: string }>;
  has_nsfw_concepts?: boolean[];
}

/** A moderation rejection is terminal: retrying another provider would bypass it. */
export class ImageSafetyError extends Error {
  constructor() {
    super("Image generation was rejected by the provider safety checks");
    this.name = "ImageSafetyError";
  }
}

class FalRequestError extends Error {
  constructor(readonly reason: string) { super(reason); }
}

/** Keep source framing while bounding the output to one 1024² pixel budget. */
function imageSize(width: number, height: number): ImageSize {
  const ratio = width / height;
  if (!Number.isFinite(ratio) || ratio < 0.25 || ratio > 4) {
    // Fal's 512..2048 limits cannot preserve more extreme panoramas.
    throw new FalRequestError("unsupported-reference-ratio");
  }
  let targetWidth = Math.floor(Math.sqrt(MAX_OUTPUT_PIXELS * ratio));
  let targetHeight = Math.floor(targetWidth / ratio);
  if (targetWidth < 512) {
    targetWidth = 512;
    targetHeight = Math.floor(512 / ratio);
  }
  if (targetHeight < 512) {
    targetHeight = 512;
    targetWidth = Math.floor(512 * ratio);
  }
  return { width: targetWidth, height: targetHeight };
}

function queueUrl(value: string): string {
  const url = new URL(value);
  if (url.origin !== QUEUE_ORIGIN || url.username || url.password
      || !url.pathname.startsWith("/fal-ai/flux-2/requests/")) {
    throw new FalRequestError("invalid-queue-url");
  }
  return url.href;
}

function imageUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.port || url.username || url.password
      || !(url.hostname === "fal.media" || url.hostname.endsWith(".fal.media")
        || url.hostname === "storage.googleapis.com")) {
    throw new FalRequestError("invalid-image-url");
  }
  return url.href;
}

async function readBounded(response: Response, maxBytes: number): Promise<Buffer> {
  if (Number(response.headers.get("content-length")) > maxBytes) {
    await response.body?.cancel();
    throw new FalRequestError("response-too-large");
  }
  if (!response.body) throw new FalRequestError("empty-response");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxBytes) {
        await reader.cancel();
        throw new FalRequestError("response-too-large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  return Buffer.concat(chunks, length);
}

function isSafetyError(value: unknown): boolean {
  // Provider errors are classified, never logged: they may include user input.
  return /content_policy|content.policy|safety|nsfw|moderation/i.test(JSON.stringify(value));
}

async function requestJson<T>(url: string, signal: AbortSignal, init?: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    redirect: "error",
    signal: AbortSignal.any([signal, AbortSignal.timeout(REQUEST_TIMEOUT_MS)]),
    headers: {
      "Authorization": `Key ${env.FAL_KEY}`,
      "Content-Type": "application/json",
      "X-Fal-Store-IO": "0",
      ...init?.headers,
    },
  });
  const bytes = await readBounded(response, MAX_JSON_BYTES);
  let body: unknown;
  try { body = JSON.parse(bytes.toString("utf8")); }
  catch { throw new FalRequestError("invalid-json-response"); }
  if (body && typeof body === "object") {
    const errors = body as { error?: unknown; error_type?: unknown; detail?: unknown };
    if (isSafetyError([errors.error, errors.error_type, errors.detail])) throw new ImageSafetyError();
  }
  if (!response.ok) {
    throw new FalRequestError(`http-${response.status}`);
  }
  return body as T;
}

async function waitForPoll(signal: AbortSignal): Promise<void> {
  signal.throwIfAborted();
  await new Promise<void>((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(signal.reason); };
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", abort);
      resolve();
    }, POLL_INTERVAL_MS);
    signal.addEventListener("abort", abort, { once: true });
  });
}

/**
 * Low-cost FLUX.2 Flash generation. Reference bytes are auto-oriented and sent
 * as a data URI, so an edit never depends on public asset hosting. Ordinary
 * provider failures return null; safety rejections propagate without fallback.
 * https://fal.ai/models/fal-ai/flux-2/flash/edit/api
 */
export async function generatePreviewImageFal(options: {
  prompt: string;
  projectType: string;
  referencePhoto?: ReferencePhoto;
}): Promise<GeneratedImage | null> {
  if (!env.FAL_KEY) return null;
  const startedAt = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(new Error("Image generation timed out")), LIFECYCLE_TIMEOUT_MS);
  let task: FalTask | undefined;
  let completed = false;

  try {
    let size: ImageSize;
    let referenceDataUri: string | undefined;
    if (options.referencePhoto) {
      const encoded = options.referencePhoto.base64Data;
      if (encoded.length > Math.ceil(MAX_IMAGE_BYTES / 3) * 4) {
        throw new FalRequestError("reference-too-large");
      }
      const source = Buffer.from(encoded, "base64");
      const metadata = await sharp(source, { limitInputPixels: MAX_INPUT_PIXELS }).metadata();
      if (!metadata.width || !metadata.height || (metadata.pages ?? 1) > 1) {
        throw new FalRequestError("invalid-reference-image");
      }
      const rotated = metadata.orientation !== undefined && metadata.orientation >= 5 && metadata.orientation <= 8;
      size = imageSize(rotated ? metadata.height : metadata.width, rotated ? metadata.width : metadata.height);
      const input = await sharp(source, { limitInputPixels: MAX_INPUT_PIXELS })
        .rotate().resize(size.width, size.height, { fit: "fill" })
        .png().timeout({ seconds: 10 }).toBuffer();
      referenceDataUri = `data:image/png;base64,${input.toString("base64")}`;
    } else {
      const [width, height] = aspectRatioForProjectType(options.projectType).split(":").map(Number);
      size = imageSize(width, height);
    }
    controller.signal.throwIfAborted();

    task = await requestJson<FalTask>(`${QUEUE_ORIGIN}/${MODEL}${referenceDataUri ? "/edit" : ""}`, controller.signal, {
      method: "POST",
      headers: { "X-Fal-Request-Start-Timeout": "120" },
      body: JSON.stringify({
        prompt: options.prompt,
        image_size: size,
        num_images: 1,
        enable_prompt_expansion: false,
        enable_safety_checker: true,
        output_format: "png",
        ...(referenceDataUri ? { image_urls: [referenceDataUri] } : {}),
      }),
    });
    if (!task?.request_id) throw new FalRequestError("invalid-task-response");
    const statusUrl = queueUrl(task.status_url);
    const responseUrl = queueUrl(task.response_url);
    queueUrl(task.cancel_url);

    for (;;) {
      const status = await requestJson<FalStatus>(statusUrl, controller.signal);
      if (status?.error || status?.error_type) {
        completed = true;
        if (isSafetyError([status.error, status.error_type])) throw new ImageSafetyError();
        throw new FalRequestError("generation-failed");
      }
      if (status?.status === "COMPLETED") { completed = true; break; }
      if (status?.status !== "IN_QUEUE" && status?.status !== "IN_PROGRESS") {
        throw new FalRequestError("invalid-task-status");
      }
      await waitForPoll(controller.signal);
    }

    const result = await requestJson<FalResult>(responseUrl, controller.signal);
    if (result?.has_nsfw_concepts?.some(Boolean)) throw new ImageSafetyError();
    const outputUrl = result?.images?.[0]?.url;
    if (!outputUrl) throw new FalRequestError("missing-output-image");
    const response = await fetch(imageUrl(outputUrl), {
      redirect: "error",
      signal: AbortSignal.any([controller.signal, AbortSignal.timeout(REQUEST_TIMEOUT_MS)]),
    });
    if (!response.ok) throw new FalRequestError("image-download-failed");
    const data = await readBounded(response, MAX_IMAGE_BYTES);
    const metadata = await sharp(data, { limitInputPixels: MAX_INPUT_PIXELS }).metadata();
    if (!metadata.width || !metadata.height || !["png", "jpeg", "webp"].includes(metadata.format ?? "")
        || (metadata.pages ?? 1) > 1
        || Math.abs((metadata.width / metadata.height) / (size.width / size.height) - 1) > 0.02) {
      throw new FalRequestError("invalid-output-image");
    }
    // Fully decode, strip metadata and normalize minor provider rounding. No crop.
    const normalized = await sharp(data, { limitInputPixels: MAX_INPUT_PIXELS })
      .resize(size.width, size.height, { fit: "fill" }).png().timeout({ seconds: 10 }).toBuffer();
    controller.signal.throwIfAborted();
    const durationMs = Date.now() - startedAt;
    logger.info({ provider: "fal", durationMs, ...size }, "FLUX.2 Flash image generation succeeded");
    return { base64Data: normalized.toString("base64"), mimeType: "image/png", durationMs };
  } catch (error) {
    if (error instanceof ImageSafetyError) throw error;
    logger.warn({ provider: "fal", reason: error instanceof FalRequestError ? error.reason : "request-failed" },
      "FLUX.2 Flash image generation unavailable");
    return null;
  } finally {
    clearTimeout(timer);
    if (task?.cancel_url && !completed) {
      // Cancellation has its own small deadline after the lifecycle is aborted.
      try {
        await fetch(queueUrl(task.cancel_url), {
          method: "PUT",
          headers: { "Authorization": `Key ${env.FAL_KEY}` },
          signal: AbortSignal.timeout(3_000),
          redirect: "error",
        });
      } catch { /* Best effort: retain the original failure. */ }
    }
  }
}
