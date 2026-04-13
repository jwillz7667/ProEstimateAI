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

    const prompt = `You are a professional construction estimator helping homeowners and small contractors get accurate, competitive material pricing. Generate a materials list with realistic 2025-2026 US retail pricing that a homeowner would actually pay at Home Depot or Lowe's.

PROJECT:
- Type: ${projectType}
- Quality tier: ${qualityTier}
- Title: "${context.projectTitle}"
${context.projectDescription ? `- Description: ${context.projectDescription}` : ''}
${context.squareFootage ? `- Area: ${context.squareFootage} sq ft` : ''}
${context.dimensions ? `- Dimensions: ${context.dimensions}` : ''}
- User's request: "${userPrompt}"

IMPORTANT PRICING RULES:
- Use the LOWEST reasonable retail price for the quality tier — what someone would actually pay, not MSRP or inflated contractor-supply pricing.
- Standard tier = budget-friendly big-box store pricing. Think sale prices and value lines.
- Do NOT inflate prices. A gallon of interior paint is $25-40, not $50+. Vinyl plank flooring is $1.50-3.50/sq ft, not $5+. Basic ceramic tile is $1-3/sq ft.
- The total project cost for materials should feel reasonable to a homeowner — a standard bathroom should be $1,500-4,000 in materials, a standard kitchen $3,000-8,000, painting a room $200-500.
- Include a 5% waste factor in quantities (not 10%).

Generate only PRIMARY materials (5-12 items). Group minor items (fasteners, adhesives, caulk, tape) into one "Miscellaneous Supplies" line at $50-150.

For each material:
- name: specific product (e.g. "LVP Flooring - Oak Look" not just "flooring")
- category: one of "Countertops", "Cabinets", "Flooring", "Tile", "Fixtures", "Lighting", "Plumbing", "Electrical", "Paint", "Hardware", "Appliances", "Lumber", "Drywall", "Insulation", "Roofing", "Siding", "Windows", "Doors", "Trim", "Other"
- estimatedCost: per-unit cost in USD — use the LOW END of realistic retail pricing for the tier
- unit: "sq ft", "linear ft", "each", "gallon", "box", "sheet", "bundle", "roll", "bag", "set"
- quantity: conservative estimate (don't over-order)
- supplierName: Home Depot, Lowe's, Floor & Decor, etc.

QUALITY TIER PRICING:
- standard: lowest reasonable retail (Home Depot/Lowe's value lines, e.g. Hampton Bay, StyleSelections, TrafficMaster)
- premium: mid-range retail (e.g. Delta, Moen, LifeProof, Allen + Roth)
- luxury: upper retail (e.g. Kohler, KitchenAid, custom options)

Respond with ONLY a JSON array:
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

    const prompt = `You are a professional construction estimator. Estimate the labor needed for this remodel project with competitive 2025-2026 US rates. Use rates that a small contractor or handyman would charge — NOT high-end general contractor rates.

PROJECT:
- Type: ${projectType}
- Quality tier: ${qualityTier}
- Title: "${context.projectTitle}"
${context.squareFootage ? `- Area: ${context.squareFootage} sq ft` : ''}

Generate labor line items for only the trades actually needed. Don't add trades that aren't relevant to this project type. Be conservative with hours — don't pad estimates.

For each task:
- taskName: descriptive name (e.g. "Tile Installation - Floor")
- hoursEstimate: realistic hours (lean, not padded)
- ratePerHour: competitive rate in USD (use the LOW END of the range)
- category: the trade

RATE GUIDE (per hour — use the low end for standard tier):
- General labor/demolition/cleanup: $25-40
- Carpentry/framing: $35-55
- Plumbing: $45-75
- Electrical: $45-70
- Tile/stone: $40-60
- Painting: $25-45
- HVAC: $50-80
- Premium tier: use mid-range of these rates
- Luxury tier: use upper range

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
