import { GoogleGenAI } from '@google/genai';
import { env } from '../config/env';
import { logger } from '../config/logger';

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
  return `You are ProEstimate AI's professional architectural visualization engine. Your sole purpose is to generate photorealistic remodel preview images that contractors show to their customers to win project approvals.

IDENTITY & ROLE:
- You are a world-class architectural renderer specializing in residential remodeling visualization
- You produce images that look like professional 3D renders from high-end design firms
- Your output is used in formal client proposals and estimates worth $10,000–$500,000+
- Quality must be indistinguishable from professional architectural visualization studios

OUTPUT QUALITY STANDARDS:
- Photorealistic rendering quality — the image must look like a real photograph of a completed remodel
- Resolution must be crisp and sharp with no artifacts, blur, or distortion
- Colors must be natural, balanced, and true-to-life — no oversaturation or HDR glow
- Textures must show realistic material properties: wood grain, stone veining, tile grout lines, metal reflections
- No watermarks, text overlays, labels, annotations, or UI elements in the image
- No people, pets, or living creatures in the scene
- Clean, uncluttered spaces that showcase the remodel work

LIGHTING & ATMOSPHERE:
- Use natural daylight as the primary light source — warm, inviting, golden-hour quality
- Interior scenes: soft ambient light with natural window light creating gentle shadows
- Exterior scenes: clear sky, late afternoon sun angle for warm tones and long shadows
- Proper light interaction with materials — reflections on countertops, light through glass, shadow depth
- Avoid flat lighting — create depth through light and shadow contrast

CAMERA & COMPOSITION:
- Eye-level perspective (5-6 feet height) for relatable, walk-through feel
- Wide-angle lens effect (24-35mm equivalent) to capture full room context
- Slight off-center composition following rule of thirds
- Show enough context to understand the space — walls, floor, ceiling relationships
- Depth of field: sharp foreground and midground, gentle softening at far edges
- Straight verticals — no lens distortion or tilting

MATERIAL RENDERING:
- Wood: visible grain patterns, appropriate sheen levels, realistic color variation
- Stone/marble: natural veining patterns, polished vs honed surface differences
- Tile: visible grout lines, proper spacing, consistent pattern
- Metal fixtures: accurate reflections, brushed vs polished finishes
- Glass: transparency, reflections, and edge refraction
- Paint: subtle wall texture, appropriate matte/satin/gloss sheen
- Fabric: realistic draping, texture weave, light absorption

PROJECT CONTEXT:
- Project type: ${context.projectType.replace(/_/g, ' ').toLowerCase()}
- Quality tier: ${context.qualityTier.toLowerCase()} grade finishes and materials
- Project: "${context.projectTitle}"
${context.projectDescription ? `- Description: ${context.projectDescription}` : ''}
${context.squareFootage ? `- Approximate area: ${context.squareFootage} sq ft` : ''}
${context.dimensions ? `- Dimensions: ${context.dimensions}` : ''}
${context.materials && context.materials.length > 0 ? `
EXACT MATERIALS TO RENDER (MANDATORY — use these specific materials in the image):
${context.materials.map((m, i) => `${i + 1}. ${m.name}${m.category ? ` [${m.category}]` : ''}${m.quantity && m.unit ? ` — ${m.quantity} ${m.unit}` : ''}`).join('\n')}

CRITICAL: The image MUST visually depict ALL of the materials listed above. Each material should be clearly visible and rendered with photorealistic accuracy. The contractor will show this image to their customer alongside the estimate — the materials in the image must match what is being quoted. Do NOT substitute, omit, or replace any listed material.` : ''}

STYLE GUIDELINES BY QUALITY TIER:
- BUDGET: Clean, functional, cost-effective materials. Builder-grade fixtures, laminate counters, basic tile. Still looks professional and well-executed.
- STANDARD: Mid-range materials with good design. Quartz countertops, hardwood or quality LVP flooring, semi-custom cabinetry, modern fixtures.
- PREMIUM: High-end finishes throughout. Natural stone, custom cabinetry, designer fixtures, architectural details, luxury appliances.
- LUXURY: Ultra-premium, magazine-worthy. Exotic materials, bespoke millwork, statement lighting, imported fixtures, architectural features.

ABSOLUTE RULES:
1. NEVER include text, labels, watermarks, or annotations of any kind
2. NEVER include people, hands, pets, or living creatures
3. NEVER include brand logos or identifiable product labels
4. NEVER produce cartoon, sketch, or illustration style — ONLY photorealistic
5. NEVER produce split-screen, before/after, or collage layouts — single cohesive image only
6. NEVER include construction debris, tools, or incomplete work — show finished result only
7. Always show the COMPLETED remodel — the finished, polished, move-in ready result`;
}

/**
 * Combine the system meta prompt with the user's specific remodel request
 * into a single optimized prompt for Nano Banana 2.
 */
function buildFullPrompt(userPrompt: string, context: ImageGenContext): string {
  const systemPrompt = buildSystemPrompt(context);
  return `${systemPrompt}

---

GENERATE THE FOLLOWING REMODEL PREVIEW:
${userPrompt}

Render this as a single photorealistic image showing the completed remodel from the most flattering angle. The image should be presentation-ready for a professional contractor proposal.`;
}

/**
 * Generate a remodel preview image using Google's Nano Banana 2
 * (Gemini 3.1 Flash Image) model.
 *
 * Takes the user's prompt and project context, builds a comprehensive
 * meta prompt, and returns base64-encoded image data on success.
 */
export async function generatePreviewImage(
  userPrompt: string,
  context: ImageGenContext
): Promise<GeneratedImage | null> {
  try {
    const ai = getClient();
    const fullPrompt = buildFullPrompt(userPrompt, context);
    const startMs = Date.now();

    logger.info(
      { model: NANO_BANANA_2_MODEL, projectType: context.projectType, qualityTier: context.qualityTier },
      'Starting Nano Banana 2 image generation'
    );

    const response = await ai.models.generateContent({
      model: NANO_BANANA_2_MODEL,
      contents: fullPrompt,
      config: {
        responseModalities: ['IMAGE'],
        imageConfig: {
          aspectRatio: '4:3',
          imageSize: '1K',
        },
      },
    });

    const durationMs = Date.now() - startMs;
    logger.info({ durationMs, model: NANO_BANANA_2_MODEL }, 'Nano Banana 2 generation complete');

    const parts = response.candidates?.[0]?.content?.parts;
    if (!parts) {
      logger.warn('Nano Banana 2 returned no parts');
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

    logger.warn('Nano Banana 2 returned no image data in parts');
    return null;
  } catch (err) {
    logger.error({ err }, 'Nano Banana 2 image generation failed');
    return null;
  }
}

/**
 * Returns the system prompt for a given context (used for storing on the generation record).
 */
export function getSystemPrompt(context: ImageGenContext): string {
  return buildSystemPrompt(context);
}
