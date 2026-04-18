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

export type LineItemCategory = 'materials' | 'labor' | 'other';

export interface EstimateGenLineItem {
  category: LineItemCategory;
  name: string;
  description: string;
  quantity: number;
  unit: string;
  unitCost: number;
  markupPercent: number;
  taxRate: number;
}

export interface GeneratedEstimate {
  title: string;
  overview: string;
  lineItems: EstimateGenLineItem[];
  assumptions: string;
  exclusions: string;
  terms: string;
  contingencyPercent: number;
  validDays: number;
}

export interface EstimateGenMaterial {
  name: string;
  category: string;
  estimatedCost: number;
  unit: string;
  quantity: number;
}

export interface EstimateGenLaborRate {
  category: string;
  ratePerHour: number;
}

export interface EstimateGenPricingProfile {
  defaultMarkupPercent: number;
  contingencyPercent: number;
  wasteFactor: number;
  laborRates: EstimateGenLaborRate[];
}

export interface EstimateGenContext {
  // Project
  projectType: string;
  qualityTier: string;
  projectTitle: string;
  projectDescription?: string;
  squareFootage?: string;
  dimensions?: string;

  // Company — brand + defaults
  companyName: string;
  companyPhone?: string;
  companyEmail?: string;
  companyAddress?: string;
  companyWebsite?: string;
  defaultMarkupPercent?: number;
  defaultTaxRate?: number;

  // Materials the user has selected — must appear in the output
  selectedMaterials: EstimateGenMaterial[];

  // Company-specific pricing (optional)
  pricingProfile?: EstimateGenPricingProfile;
}

/**
 * Generate a complete, client-ready estimate from project + company context
 * and any materials the user has already selected. The model is instructed to
 * produce a professional document (overview, line items across materials /
 * labor / other, assumptions, exclusions, terms) that could be handed to a
 * prospective customer as if a human estimator wrote it.
 *
 * The generator never creates DB records — it returns a structured object
 * that the estimates service converts into a real `Estimate` + line items.
 */
export async function generateEstimate(context: EstimateGenContext): Promise<GeneratedEstimate> {
  const ai = getClient();
  const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();
  const qualityTier = context.qualityTier.toLowerCase();

  const materialsBlock = context.selectedMaterials.length > 0
    ? context.selectedMaterials
        .map(
          (m, i) =>
            `  ${i + 1}. ${m.name} (${m.category}) — ${m.quantity} ${m.unit} @ $${m.estimatedCost.toFixed(2)}/${m.unit}`
        )
        .join('\n')
    : '  (no materials have been pre-selected — propose an appropriate primary list for this project)';

  const laborRatesBlock = context.pricingProfile?.laborRates?.length
    ? context.pricingProfile.laborRates
        .map((r) => `  - ${r.category}: $${r.ratePerHour.toFixed(2)}/hr`)
        .join('\n')
    : '  (no company-specific labor rates set — use competitive regional rates for the quality tier)';

  const markupPct = context.pricingProfile?.defaultMarkupPercent
    ?? context.defaultMarkupPercent
    ?? 20;
  const contingencyPct = context.pricingProfile?.contingencyPercent ?? 10;
  const taxRate = context.defaultTaxRate ?? 0.0825;

  const prompt = `You are a senior estimator at "${context.companyName}". You are preparing a client-ready estimate for a prospective customer. The document will be presented as if written by a seasoned human professional — tone should be confident, warm, direct, and specific. Absolutely no emojis, no exclamation marks, no sales fluff, no industry jargon the homeowner wouldn't immediately understand.

COMPANY IDENTITY:
- Name: ${context.companyName}
${context.companyPhone ? `- Phone: ${context.companyPhone}\n` : ''}${context.companyEmail ? `- Email: ${context.companyEmail}\n` : ''}${context.companyAddress ? `- Address: ${context.companyAddress}\n` : ''}${context.companyWebsite ? `- Website: ${context.companyWebsite}\n` : ''}- Default markup: ${markupPct}%
- Default tax rate: ${(taxRate * 100).toFixed(2)}%
- Contingency: ${contingencyPct}%

PROJECT:
- Type: ${projectType}
- Quality tier: ${qualityTier}
- Title: "${context.projectTitle}"
${context.projectDescription ? `- Client's description: ${context.projectDescription}\n` : ''}${context.squareFootage ? `- Area: ${context.squareFootage} sq ft\n` : ''}${context.dimensions ? `- Dimensions: ${context.dimensions}\n` : ''}
SELECTED MATERIALS (the client has picked these — include every one as a line item with the exact quantity and unit cost listed, then add any supporting materials the job actually needs: fasteners, adhesives, caulk, trim, shims, patch drywall, sealant, paint, tape, drop cloths):
${materialsBlock}

COMPANY LABOR RATES:
${laborRatesBlock}

Produce a JSON object with this exact schema:
{
  "title": "short, presentable estimate title — not a generic placeholder",
  "overview": "2 to 4 sentences of scope-of-work prose written directly to the client. No bullet points. Explain what you will do and what the client will get.",
  "lineItems": [
    {
      "category": "materials" | "labor" | "other",
      "name": "Specific item name",
      "description": "One line of helpful detail",
      "quantity": 0,
      "unit": "sq ft" | "linear ft" | "each" | "hour" | "lot" | "gallon" | "box" | "sheet" | "bundle" | "roll" | "bag" | "set",
      "unitCost": 0.00,
      "markupPercent": 0,
      "taxRate": 0.0
    }
  ],
  "assumptions": "what you are assuming about permits, access, schedule, substrate condition, subfloor, existing plumbing, etc.",
  "exclusions": "what is explicitly NOT included (structural changes, asbestos / lead abatement, permit fees if owner pulls, relocation of fixtures, etc.)",
  "terms": "payment schedule, warranty period, change-order policy. Professional, concise, fair.",
  "contingencyPercent": ${contingencyPct},
  "validDays": 30
}

RULES:
- Include EVERY selected material as a materials line item at the given quantity and unit cost. Apply ${markupPct}% markup unless the material is already specialty-priced.
- Add all labor tasks that actually happen on a ${projectType} job: protection, demolition, rough-in, installation, finish work, cleanup, punch list. Use the company's labor rates where provided; otherwise use honest regional rates for ${qualityTier} tier.
- Add relevant "other" line items: permits (if company pulls), dumpster, site protection, disposal, deliveries.
- Materials are taxed at ${(taxRate * 100).toFixed(2)}%. Labor is not taxed (taxRate = 0). "Other" items are taxed if they are goods (dumpster rental, supplies) and not taxed if they are services (permits, disposal fees).
- For ${qualityTier} tier, match pricing language to the tier: luxury uses Kohler / KitchenAid / custom millwork references; premium uses Delta / Moen / LifeProof; standard uses Home Depot / Lowe's value lines.
- Keep overview, assumptions, exclusions, and terms in complete sentences. No emojis, no exclamation marks.

Respond with ONLY the JSON object. No markdown fences, no preamble, no trailing commentary.`;

  logger.info(
    {
      projectType,
      qualityTier,
      companyName: context.companyName,
      materialCount: context.selectedMaterials.length,
    },
    'Generating AI estimate'
  );

  const response = await ai.models.generateContent({
    model: GEMINI_TEXT_MODEL,
    contents: prompt,
    config: {
      temperature: 0.4,
      maxOutputTokens: 8192,
      responseMimeType: 'application/json',
    },
  });

  const text = response.text?.trim();
  if (!text) {
    throw new Error('AI estimate generation returned an empty response');
  }

  let raw: any;
  try {
    raw = JSON.parse(text);
  } catch (err) {
    logger.error({ err, text: text.slice(0, 500) }, 'Failed to parse estimate-gen JSON');
    throw new Error('AI estimate generation returned unparseable JSON');
  }

  const lineItems: EstimateGenLineItem[] = Array.isArray(raw.lineItems)
    ? raw.lineItems.map((li: any) => ({
        category: (['materials', 'labor', 'other'].includes(li.category)
          ? li.category
          : 'other') as LineItemCategory,
        name: String(li.name ?? 'Untitled line item'),
        description: String(li.description ?? ''),
        quantity: Number(li.quantity) || 1,
        unit: String(li.unit ?? 'each'),
        unitCost: Number(li.unitCost) || 0,
        markupPercent: Number(li.markupPercent) || 0,
        taxRate: Number(li.taxRate) || 0,
      }))
    : [];

  return {
    title: String(raw.title ?? context.projectTitle),
    overview: String(raw.overview ?? ''),
    lineItems,
    assumptions: String(raw.assumptions ?? ''),
    exclusions: String(raw.exclusions ?? ''),
    terms: String(raw.terms ?? ''),
    contingencyPercent: Number(raw.contingencyPercent) || contingencyPct,
    validDays: Number(raw.validDays) || 30,
  };
}
