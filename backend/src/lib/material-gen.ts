import { GoogleGenAI } from '@google/genai';
import { env } from '../config/env';
import { logger } from '../config/logger';

const GEMINI_TEXT_MODEL = 'gemini-2.5-flash';

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

export interface GeneratedMaterial {
  name: string;
  category: string;
  estimatedCost: number;
  unit: string;
  quantity: number;
  supplierName?: string;
  sortOrder: number;
}

export interface MaterialGenContext {
  projectType: string;
  qualityTier: string;
  squareFootage?: string;
  dimensions?: string;
  projectTitle: string;
  projectDescription?: string;
}

/**
 * Use Gemini text model to generate a detailed material list for a remodel project.
 * Returns structured JSON with materials, estimated costs, quantities, and categories.
 */
export async function generateMaterialSuggestions(
  userPrompt: string,
  context: MaterialGenContext
): Promise<GeneratedMaterial[]> {
  try {
    const ai = getClient();
    const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();
    const qualityTier = context.qualityTier.toLowerCase();

    const prompt = `You are a professional construction estimator. Given this remodel project, generate a detailed materials list with realistic 2025-2026 US market pricing.

PROJECT:
- Type: ${projectType}
- Quality tier: ${qualityTier}
- Title: "${context.projectTitle}"
${context.projectDescription ? `- Description: ${context.projectDescription}` : ''}
${context.squareFootage ? `- Area: ${context.squareFootage} sq ft` : ''}
${context.dimensions ? `- Dimensions: ${context.dimensions}` : ''}
- User's request: "${userPrompt}"

Generate a comprehensive materials list. Include ALL materials needed for this project — primary materials, secondary materials, hardware, fixtures, adhesives, fasteners, finishing materials, etc.

For each material, provide:
- name: specific product name (e.g. "Quartz Countertop - Calacatta" not just "countertop")
- category: one of "Countertops", "Cabinets", "Flooring", "Tile", "Fixtures", "Lighting", "Plumbing", "Electrical", "Paint", "Hardware", "Appliances", "Lumber", "Drywall", "Insulation", "Roofing", "Siding", "Windows", "Doors", "Trim", "Adhesives & Sealants", "Fasteners", "Other"
- estimatedCost: per-unit cost in USD (realistic retail pricing)
- unit: "sq ft", "linear ft", "each", "gallon", "box", "sheet", "bundle", "roll", "bag", "set"
- quantity: estimated quantity needed for this project
- supplierName: suggest a real supplier (Home Depot, Lowe's, Floor & Decor, Ferguson, Build.com, Wayfair, etc.)

QUALITY TIER PRICING GUIDE:
- standard: mid-range retail pricing (Home Depot/Lowe's level)
- premium: upper-mid pricing (specialty retailers, upgraded brands)
- luxury: high-end pricing (designer brands, custom/exotic materials)

Respond with ONLY a JSON array, no markdown, no explanation:
[{"name":"...","category":"...","estimatedCost":0.00,"unit":"...","quantity":0,"supplierName":"..."}]`;

    logger.info({ projectType, qualityTier }, 'Generating material suggestions via Gemini');

    const response = await ai.models.generateContent({
      model: GEMINI_TEXT_MODEL,
      contents: prompt,
      config: {
        temperature: 0.3,
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',
      },
    });

    const text = response.text?.trim();
    if (!text) {
      logger.warn('Material generation returned no text');
      return [];
    }

    const materials: GeneratedMaterial[] = JSON.parse(text).map(
      (m: any, i: number) => ({
        name: String(m.name || 'Unknown Material'),
        category: String(m.category || 'Other'),
        estimatedCost: Number(m.estimatedCost) || 0,
        unit: String(m.unit || 'each'),
        quantity: Number(m.quantity) || 1,
        supplierName: m.supplierName ? String(m.supplierName) : undefined,
        sortOrder: i,
      })
    );

    logger.info({ count: materials.length }, 'Material suggestions generated');
    return materials;
  } catch (err) {
    logger.error({ err }, 'Material suggestion generation failed');
    return [];
  }
}

/**
 * Use Gemini to estimate labor hours and rates for a project.
 */
export interface LaborEstimate {
  taskName: string;
  hoursEstimate: number;
  ratePerHour: number;
  category: string;
}

export async function generateLaborEstimates(
  context: MaterialGenContext
): Promise<LaborEstimate[]> {
  try {
    const ai = getClient();
    const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();
    const qualityTier = context.qualityTier.toLowerCase();

    const prompt = `You are a professional construction estimator. Estimate the labor needed for this remodel project with 2025-2026 US contractor rates.

PROJECT:
- Type: ${projectType}
- Quality tier: ${qualityTier}
- Title: "${context.projectTitle}"
${context.squareFootage ? `- Area: ${context.squareFootage} sq ft` : ''}

Generate labor line items. Include all trades needed (demolition, framing, plumbing, electrical, tiling, painting, installation, cleanup, etc.)

For each task:
- taskName: descriptive name (e.g. "Tile Installation - Floor & Backsplash")
- hoursEstimate: realistic hours for this scope
- ratePerHour: typical contractor rate in USD for this trade
- category: the trade (e.g. "General Labor", "Plumbing", "Electrical", "Tiling", "Painting", "Carpentry", "Demolition", "HVAC", "Cleanup")

RATE GUIDE (per hour):
- General labor/demolition: $35-55
- Carpentry/framing: $45-75
- Plumbing: $65-120
- Electrical: $55-100
- Tile/stone: $50-85
- Painting: $35-65
- HVAC: $65-110
- Premium/specialty trades add 20-40%

Respond with ONLY a JSON array:
[{"taskName":"...","hoursEstimate":0,"ratePerHour":0,"category":"..."}]`;

    const response = await ai.models.generateContent({
      model: GEMINI_TEXT_MODEL,
      contents: prompt,
      config: {
        temperature: 0.3,
        maxOutputTokens: 4096,
        responseMimeType: 'application/json',
      },
    });

    const text = response.text?.trim();
    if (!text) return [];

    return JSON.parse(text).map((l: any) => ({
      taskName: String(l.taskName || 'General Labor'),
      hoursEstimate: Number(l.hoursEstimate) || 1,
      ratePerHour: Number(l.ratePerHour) || 50,
      category: String(l.category || 'General Labor'),
    }));
  } catch (err) {
    logger.error({ err }, 'Labor estimate generation failed');
    return [];
  }
}
