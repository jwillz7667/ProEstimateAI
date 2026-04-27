import {
  GoogleGenAI,
  HarmBlockThreshold,
  HarmCategory,
  createPartFromBase64,
  createPartFromText,
  createUserContent,
} from "@google/genai";
import { env } from "../config/env";
import { logger } from "../config/logger";
import { generatePreviewImagePiAPI } from "./piapi-image-gen";
import { getImagePrompt } from "./prompts";
import {
  PromptContext,
  QualityTier,
  RecurrenceFrequency,
} from "./prompts/types";

const NANO_BANANA_2_MODEL = "gemini-3.1-flash-image-preview";

let genAI: GoogleGenAI | null = null;

function getClient(): GoogleGenAI {
  if (!genAI) {
    if (!env.GOOGLE_AI_API_KEY) {
      throw new Error("GOOGLE_AI_API_KEY is not configured");
    }
    genAI = new GoogleGenAI({ apiKey: env.GOOGLE_AI_API_KEY });
  }
  return genAI;
}

export interface GeneratedImage {
  base64Data: string;
  mimeType: string;
  durationMs: number;
}

export interface MaterialSpec {
  name: string;
  category?: string;
  quantity?: number;
  unit?: string;
}

/**
 * Everything the orchestrator hands to the image-gen pipeline. The optional
 * measurement fields (`lawnAreaSqFt`, `roofAreaSqFt`, `zip`) are populated by
 * the maps integration; the recurrence fields drive LAWN_CARE bids; both are
 * forwarded into the prompt library so the per-type module can ground its
 * scene description in real numbers.
 */
export interface ImageGenContext {
  projectType: string;
  qualityTier: string;
  squareFootage?: string;
  dimensions?: string;
  projectTitle: string;
  projectDescription?: string;
  materials?: MaterialSpec[];

  // Property measurements (optional — populated by maps integration).
  lawnAreaSqFt?: number | null;
  roofAreaSqFt?: number | null;
  zip?: string | null;

  // Recurrence (LAWN_CARE only).
  isRecurring?: boolean;
  recurrenceFrequency?: RecurrenceFrequency | null;
  visitsPerMonth?: number | null;
  contractMonths?: number | null;
}

/**
 * Map the orchestrator-facing `ImageGenContext` (string-typed for legacy
 * reasons) into the strictly-typed `PromptContext` the prompt library
 * consumes. Centralizing the coercion here means new fields only need to
 * be added once.
 */
export function toPromptContext(ctx: ImageGenContext): PromptContext {
  const tier = (ctx.qualityTier?.toUpperCase() ?? "STANDARD") as QualityTier;
  const sf = ctx.squareFootage ? Number(ctx.squareFootage) : null;
  return {
    projectType: ctx.projectType.toUpperCase(),
    qualityTier: tier === "LUXURY" || tier === "PREMIUM" ? tier : "STANDARD",
    squareFootage: Number.isFinite(sf) ? sf : null,
    dimensions: ctx.dimensions ?? null,
    projectTitle: ctx.projectTitle,
    projectDescription: ctx.projectDescription ?? null,
    materials: ctx.materials,
    lawnAreaSqFt: ctx.lawnAreaSqFt ?? null,
    roofAreaSqFt: ctx.roofAreaSqFt ?? null,
    zip: ctx.zip ?? null,
    isRecurring: ctx.isRecurring,
    recurrenceFrequency: ctx.recurrenceFrequency ?? null,
    visitsPerMonth: ctx.visitsPerMonth ?? null,
    contractMonths: ctx.contractMonths ?? null,
  };
}

/**
 * Determine the best aspect ratio for a given project type. LANDSCAPING /
 * LAWN_CARE / EXTERIOR / ROOFING / SIDING are outdoor wide shots and benefit
 * from 16:9; BATHROOM is portrait; everything else stays 4:3.
 */
function aspectRatioForProjectType(projectType: string): string {
  switch (projectType.toUpperCase()) {
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

/**
 * The full prompt sent to the image model. For the reference-photo path
 * (PiAPI / Google with attached photo) we want a tight edit instruction
 * that preserves the room/property; for the text-to-image path we lead
 * with the per-type prompt and append the contractor's user prompt.
 */
function buildFullPrompt(
  userPrompt: string,
  context: ImageGenContext,
  hasReferencePhoto: boolean,
): string {
  const promptCtx = toPromptContext(context);
  const systemPrompt = getImagePrompt(promptCtx);

  if (hasReferencePhoto) {
    // Edit-mode: keep the camera and structure of the reference photo.
    // The per-type system prompt establishes design + photographic rules;
    // the editing directive forces the model to preserve the existing
    // scene rather than imagining a new one.
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
satisfies the framing rules above. Make it look so real and aspirational
that the client will immediately approve.`;
}

export interface ReferencePhoto {
  base64Data: string;
  mimeType: string;
}

/**
 * Generate a preview image using the best available provider.
 *
 * Provider strategy:
 *   1. Google GenAI (Gemini 3.1 Flash Image) when GOOGLE_AI_API_KEY is set.
 *   2. PiAPI nano-banana-pro/2 when PIAPI_API_KEY is set.
 *
 * Both return GeneratedImage with the same shape; the caller is unaware
 * of which provider fulfilled the request.
 */
export async function generatePreviewImage(
  userPrompt: string,
  context: ImageGenContext,
  referencePhoto?: ReferencePhoto,
  referenceAssetUrl?: string,
): Promise<GeneratedImage | null> {
  if (env.GOOGLE_AI_API_KEY) {
    try {
      logger.info(
        { provider: "google" },
        "Attempting Google GenAI image generation (primary)",
      );
      const googleResult = await generatePreviewImageGoogle(
        userPrompt,
        context,
        referencePhoto,
      );
      if (googleResult) {
        logger.info(
          { provider: "google", durationMs: googleResult.durationMs },
          "Google GenAI generation succeeded",
        );
        return googleResult;
      }
      logger.warn(
        { provider: "google" },
        "Google GenAI returned null — falling through to PiAPI",
      );
    } catch (googleErr) {
      logger.error(
        { err: googleErr, provider: "google" },
        "Google GenAI generation failed — falling through to PiAPI",
      );
    }
  }

  if (env.PIAPI_API_KEY) {
    try {
      logger.info(
        { provider: "piapi" },
        "Attempting PiAPI image generation (fallback)",
      );
      const piResult = await generatePreviewImagePiAPI({
        userPrompt,
        context,
        referencePhoto,
        referenceAssetUrl,
      });
      if (piResult) {
        logger.info(
          { provider: "piapi", durationMs: piResult.durationMs },
          "PiAPI generation succeeded",
        );
        return piResult;
      }
      logger.warn(
        { provider: "piapi" },
        "PiAPI returned null — no provider produced an image",
      );
    } catch (piErr) {
      logger.error(
        { err: piErr, provider: "piapi" },
        "PiAPI generation failed",
      );
    }
  }

  logger.error(
    "No image generation provider produced an image (need GOOGLE_AI_API_KEY or PIAPI_API_KEY)",
  );
  return null;
}

async function generatePreviewImageGoogle(
  userPrompt: string,
  context: ImageGenContext,
  referencePhoto?: ReferencePhoto,
): Promise<GeneratedImage | null> {
  try {
    const ai = getClient();
    const fullPrompt = buildFullPrompt(userPrompt, context, !!referencePhoto);
    const startMs = Date.now();

    const aspectRatio = aspectRatioForProjectType(context.projectType);

    logger.info(
      {
        model: NANO_BANANA_2_MODEL,
        provider: "google",
        projectType: context.projectType,
        qualityTier: context.qualityTier,
        aspectRatio,
        imageSize: "2K",
        hasReferencePhoto: !!referencePhoto,
      },
      "Starting Google GenAI image generation (primary)",
    );

    const contents = referencePhoto
      ? createUserContent([
          createPartFromBase64(
            referencePhoto.base64Data,
            referencePhoto.mimeType,
          ),
          createPartFromText(fullPrompt),
        ])
      : fullPrompt;

    const response = await ai.models.generateContent({
      model: NANO_BANANA_2_MODEL,
      contents,
      config: {
        temperature: 1,
        topP: 0.95,
        maxOutputTokens: 32768,
        responseModalities: referencePhoto ? ["TEXT", "IMAGE"] : ["IMAGE"],
        safetySettings: [
          {
            category: HarmCategory.HARM_CATEGORY_HARASSMENT,
            threshold: HarmBlockThreshold.OFF,
          },
          {
            category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,
            threshold: HarmBlockThreshold.OFF,
          },
          {
            category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
            threshold: HarmBlockThreshold.OFF,
          },
          {
            category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
            threshold: HarmBlockThreshold.OFF,
          },
        ],
        imageConfig: {
          aspectRatio,
          imageSize: "2K",
        },
      },
    });

    const durationMs = Date.now() - startMs;
    logger.info(
      { durationMs, model: NANO_BANANA_2_MODEL, provider: "google" },
      "Google GenAI generation complete",
    );

    const parts = response.candidates?.[0]?.content?.parts;
    if (!parts) {
      logger.warn("Google GenAI returned no parts");
      return null;
    }

    for (const part of parts) {
      if (part.inlineData) {
        return {
          base64Data: part.inlineData.data as string,
          mimeType: (part.inlineData.mimeType as string) || "image/png",
          durationMs,
        };
      }
    }

    logger.warn("Google GenAI returned no image data in parts");
    return null;
  } catch (err) {
    logger.error(
      { err, provider: "google" },
      "Google GenAI image generation failed",
    );
    return null;
  }
}

/**
 * Returns the system prompt for a given context — stored on the generation
 * record so we can audit exactly what we asked the model.
 */
export function getSystemPrompt(context: ImageGenContext): string {
  return getImagePrompt(toPromptContext(context));
}
