import { GoogleGenAI, HarmBlockThreshold, HarmCategory, createPartFromBase64, createPartFromText, createUserContent } from '@google/genai';
import { env } from '../config/env';
import { logger } from '../config/logger';
import { generatePreviewImagePiAPI } from './piapi-image-gen';

const NANO_BANANA_2_MODEL = 'gemini-3.1-flash-image-preview';

let genAI: GoogleGenAI | null = null;

function getClient(): GoogleGenAI {
  if (!genAI) {
    if (!env.GOOGLE_AI_API_KEY) {
      throw new Error('GOOGLE_AI_API_KEY is not configured');
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

export interface ImageGenContext {
  projectType: string;
  qualityTier: string;
  squareFootage?: string;
  dimensions?: string;
  projectTitle: string;
  projectDescription?: string;
  materials?: MaterialSpec[];
}

/**
 * Determine the best aspect ratio for a given project type.
 * Exteriors and wide rooms benefit from 16:9; bathrooms from 3:4 (portrait);
 * kitchens and general rooms from 4:3.
 */
function aspectRatioForProjectType(projectType: string): string {
  const type = projectType.toUpperCase();
  switch (type) {
    case 'EXTERIOR':
    case 'ROOFING':
    case 'SIDING':
      return '16:9';   // wide landscape for exterior shots
    case 'BATHROOM':
      return '3:4';    // portrait for compact vertical spaces
    case 'KITCHEN':
    case 'ROOM_REMODEL':
    case 'FLOORING':
    case 'PAINTING':
    default:
      return '4:3';    // standard landscape for interior rooms
  }
}

/**
 * Build a comprehensive system-level meta prompt that instructs Nano Banana 2
 * on exactly what it is, how it should behave, and how to produce the output image.
 *
 * This prompt establishes:
 * 1. Identity & role — professional architectural visualization renderer
 * 2. Output quality standards — photorealistic, high-detail, proper lighting
 * 3. Composition rules — camera angle, framing, depth of field
 * 4. Material rendering — accurate textures, reflections, grain
 * 5. Context awareness — residential remodeling, contractor use case
 * 6. Safety & style guardrails — no people, no text overlays, clean output
 */
function buildSystemPrompt(context: ImageGenContext): string {
  const qualityTierDescriptions: Record<string, string> = {
    budget: 'Clean and functional with cost-effective builder-grade materials — laminate countertops, basic ceramic tile, painted MDF cabinetry, chrome fixtures. The space still looks professionally finished and well-maintained, just with practical, budget-friendly selections.',
    standard: 'Mid-range materials with tasteful design — quartz countertops, engineered hardwood or quality luxury vinyl plank flooring, semi-custom shaker cabinetry, brushed nickel or matte black fixtures, subway tile backsplash. A well-designed, modern space that feels curated.',
    premium: 'High-end finishes throughout — natural marble or quartzite countertops, solid hardwood flooring, custom cabinetry with soft-close hardware, designer lighting fixtures, frameless glass shower enclosures, premium appliances. Every detail feels intentional and luxurious.',
    luxury: 'Ultra-premium, magazine-editorial quality — exotic stone slabs with dramatic veining, bespoke millwork with intricate detailing, statement chandelier lighting, imported European fixtures, architectural ceiling features like coffered or barrel vaults, wide-plank reclaimed wood, museum-quality finishes.',
  };

  const tierDesc = qualityTierDescriptions[context.qualityTier.toLowerCase()] ?? qualityTierDescriptions['standard'];

  return `You are a world-class architectural visualization photographer. Generate a single photorealistic photograph of a beautifully completed ${context.projectType.replace(/_/g, ' ').toLowerCase()} remodel. This image will be presented to a homeowner in a professional contractor's proposal, so it must look like a real photograph taken by an interiors photographer for a design magazine.

Shoot the scene as if you are standing in the room with a full-frame camera and a 28mm wide-angle lens at eye level (about 5.5 feet high). Frame the composition using the rule of thirds, with the main focal point slightly off-center. Keep all vertical lines perfectly straight — no barrel distortion or keystoning.

Light the scene with warm, natural daylight streaming through windows, creating soft directional shadows that give the space depth and dimension. For interior scenes, supplement with recessed downlights casting gentle pools of warm light on countertops and floors. The overall mood should be inviting, bright, and aspirational — the kind of golden-hour warmth that makes a homeowner say "I want my home to look exactly like this."

Render every material with obsessive photorealistic detail. Wood surfaces should show natural grain variation and appropriate sheen. Stone and marble should display realistic veining patterns with subtle depth. Tile should have visible grout lines with proper spacing. Metal fixtures should show accurate reflections — distinguish between brushed, polished, and matte finishes. Glass should have proper transparency and edge refraction.

The finish level is ${context.qualityTier.toLowerCase()} grade: ${tierDesc}

Project: "${context.projectTitle}" — a ${context.projectType.replace(/_/g, ' ').toLowerCase()} project.
${context.projectDescription ? `The homeowner's vision: ${context.projectDescription}` : ''}
${context.squareFootage ? `The space is approximately ${context.squareFootage} square feet.` : ''}
${context.dimensions ? `Room dimensions: ${context.dimensions}.` : ''}
${context.materials && context.materials.length > 0 ? `
The following specific materials MUST be clearly visible and accurately rendered in the image, as they correspond to the line items on the contractor's estimate:
${context.materials.map((m, i) => `${i + 1}. ${m.name}${m.category ? ` (${m.category})` : ''}${m.quantity && m.unit ? ` — ${m.quantity} ${m.unit}` : ''}`).join('\n')}
Every listed material must appear in the scene. Do not substitute, omit, or invent materials not on this list.` : ''}

The scene must show only the finished, move-in-ready result — no construction debris, no tools, no unfinished work. The space should be clean, styled, and magazine-ready. Do not include any people, pets, hands, or living creatures. Do not include any text, labels, watermarks, annotations, brand logos, or UI overlays. Do not produce a cartoon, illustration, sketch, or split-screen layout — only a single cohesive photorealistic image.`;
}

/**
 * Combine the system meta prompt with the user's specific remodel request
 * into a single optimized prompt for Nano Banana 2.
 */
function buildFullPrompt(userPrompt: string, context: ImageGenContext, hasReferencePhoto: boolean = false): string {
  if (hasReferencePhoto) {
    // For image editing: keep the prompt concise and direct.
    // The model needs a clear instruction to EDIT the provided image, not generate from scratch.
    const qualityTier = context.qualityTier.toLowerCase();
    const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();

    return `Edit this photo to show a completed ${projectType} remodel. ${userPrompt}

Keep the exact same room, same layout, same camera angle, same perspective, same windows and doors. Only change the finishes, materials, and fixtures to show a beautiful ${qualityTier}-grade ${projectType} renovation. The result must look like a real photo of this exact same space after a professional remodel. Photorealistic only, no text or labels.`;
  }

  // For pure text-to-image generation (no reference photo)
  const systemPrompt = buildSystemPrompt(context);
  return `${systemPrompt}

The homeowner has described what they want: "${userPrompt}"

Photograph this completed remodel from the most flattering angle, capturing the full beauty of the finished space. Make it look so real and aspirational that the homeowner will immediately approve the project.`;
}

/**
 * Generate a remodel preview image using Nano Banana 2 (Gemini 3.1 Flash Image).
 *
 * Config: 2K resolution, context-aware aspect ratio, person generation disabled.
 * Prompt style: narrative scene description optimized for photorealistic output.
 */
/**
 * Optional reference photo that the model uses as the basis for the remodel.
 * The model sees the actual room/space and generates the remodel ON that space.
 */
export interface ReferencePhoto {
  base64Data: string;
  mimeType: string;
}

/**
 * Generate a preview image using the best available provider.
 *
 * Provider strategy (primary → fallback):
 *   1. PiAPI Nano Banana Pro (if PIAPI_API_KEY is set) — best quality, safety controls
 *      - Internal fallback: PiAPI Nano Banana 2
 *   2. Google GenAI direct (if GOOGLE_AI_API_KEY is set) — original provider
 *
 * Both providers produce the same GeneratedImage output (base64 + mimeType + durationMs).
 * The caller is unaware of which provider fulfilled the request.
 */
export async function generatePreviewImage(
  userPrompt: string,
  context: ImageGenContext,
  referencePhoto?: ReferencePhoto,
  referenceAssetUrl?: string
): Promise<GeneratedImage | null> {

  // ── Provider 1: PiAPI (primary) ─────────────────────────────────────────
  if (env.PIAPI_API_KEY) {
    try {
      logger.info({ provider: 'piapi' }, 'Attempting PiAPI image generation (primary)');
      const piResult = await generatePreviewImagePiAPI({
        userPrompt,
        context,
        referencePhoto,
        referenceAssetUrl,
      });

      if (piResult) {
        logger.info({ provider: 'piapi', durationMs: piResult.durationMs }, 'PiAPI generation succeeded');
        return piResult;
      }

      logger.warn({ provider: 'piapi' }, 'PiAPI returned null — falling through to Google GenAI');
    } catch (piErr) {
      logger.error({ err: piErr, provider: 'piapi' }, 'PiAPI generation failed — falling through to Google GenAI');
    }
  }

  // ── Provider 2: Google GenAI (fallback) ─────────────────────────────────
  if (env.GOOGLE_AI_API_KEY) {
    return generatePreviewImageGoogle(userPrompt, context, referencePhoto);
  }

  // ── No provider configured ──────────────────────────────────────────────
  logger.error('No image generation provider configured (need PIAPI_API_KEY or GOOGLE_AI_API_KEY)');
  return null;
}

/**
 * Google GenAI direct implementation (original Nano Banana 2 path).
 * Used as fallback when PiAPI is unavailable.
 */
async function generatePreviewImageGoogle(
  userPrompt: string,
  context: ImageGenContext,
  referencePhoto?: ReferencePhoto
): Promise<GeneratedImage | null> {
  try {
    const ai = getClient();
    const fullPrompt = buildFullPrompt(userPrompt, context, !!referencePhoto);
    const startMs = Date.now();

    const aspectRatio = aspectRatioForProjectType(context.projectType);

    logger.info(
      { model: NANO_BANANA_2_MODEL, provider: 'google', projectType: context.projectType, qualityTier: context.qualityTier, aspectRatio, imageSize: '2K', hasReferencePhoto: !!referencePhoto },
      'Starting Google GenAI image generation (fallback)'
    );

    const contents = referencePhoto
      ? createUserContent([
          createPartFromBase64(referencePhoto.base64Data, referencePhoto.mimeType),
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
        responseModalities: referencePhoto ? ['TEXT', 'IMAGE'] : ['IMAGE'],
        safetySettings: [
          { category: HarmCategory.HARM_CATEGORY_HARASSMENT, threshold: HarmBlockThreshold.OFF },
          { category: HarmCategory.HARM_CATEGORY_HATE_SPEECH, threshold: HarmBlockThreshold.OFF },
          { category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold: HarmBlockThreshold.OFF },
          { category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold: HarmBlockThreshold.OFF },
        ],
        imageConfig: {
          aspectRatio,
          imageSize: '2K',
        },
      },
    });

    const durationMs = Date.now() - startMs;
    logger.info({ durationMs, model: NANO_BANANA_2_MODEL, provider: 'google' }, 'Google GenAI generation complete');

    const parts = response.candidates?.[0]?.content?.parts;
    if (!parts) {
      logger.warn('Google GenAI returned no parts');
      return null;
    }

    for (const part of parts) {
      if (part.inlineData) {
        return {
          base64Data: part.inlineData.data as string,
          mimeType: (part.inlineData.mimeType as string) || 'image/png',
          durationMs,
        };
      }
    }

    logger.warn('Google GenAI returned no image data in parts');
    return null;
  } catch (err) {
    logger.error({ err, provider: 'google' }, 'Google GenAI image generation failed');
    return null;
  }
}

/**
 * Returns the system prompt for a given context (used for storing on the generation record).
 */
export function getSystemPrompt(context: ImageGenContext): string {
  return buildSystemPrompt(context);
}
