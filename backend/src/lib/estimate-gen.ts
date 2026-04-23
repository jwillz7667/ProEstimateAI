import { env } from '../config/env';
import { logger } from '../config/logger';
import { AppError } from './errors';

// DeepSeek is OpenAI-compatible. `deepseek-chat` is the V3 alias and supports
// JSON-mode output. No SDK needed — the request shape is a standard chat
// completion over HTTPS, so we use native fetch to keep the dep surface small.
const DEEPSEEK_ENDPOINT = 'https://api.deepseek.com/chat/completions';
const DEEPSEEK_MODEL = 'deepseek-chat';

/// Max attempts including the initial one — 3 tries covers the vast majority
/// of DeepSeek transient 5xxs while keeping the caller's worst-case latency
/// bounded at ~30s.
const MAX_ATTEMPTS = 3;
/// Initial backoff; doubles each retry. 500ms, 1s, 2s.
const INITIAL_BACKOFF_MS = 500;
/// Per-attempt timeout so a hung TCP connection doesn't hold the request.
const REQUEST_TIMEOUT_MS = 60_000;

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
  if (!env.DEEPSEEK_API_KEY) {
    throw new AppError(
      503,
      'AI_UNCONFIGURED',
      'AI estimating is not configured on this server. Please start a blank estimate.',
    );
  }

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

  const systemPrompt = `You are a senior estimator at "${context.companyName}". You are preparing a client-ready estimate for a prospective customer. The document will be presented as if written by a seasoned human professional — tone should be confident, warm, direct, and specific. Absolutely no emojis, no exclamation marks, no sales fluff, no industry jargon the homeowner wouldn't immediately understand.

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

RULES:
- Include EVERY selected material as a materials line item at the given quantity and unit cost. Apply ${markupPct}% markup unless specialty-priced.
- Consolidate related work into one line where possible — this keeps the estimate under ~22 total line items. Group rough-in tasks, group finish work, group cleanup + punch list. Quality over quantity.
- Add labor tasks that actually happen on a ${projectType} job: protection, demo, rough-in, installation, finish, cleanup. Use company labor rates where provided; otherwise honest regional rates for ${qualityTier} tier.
- Add relevant "other" line items: permits, dumpster, site protection, disposal, deliveries.
- Materials are taxed at ${(taxRate * 100).toFixed(2)}% — express taxRate as the fraction ${taxRate.toFixed(4)}. Labor is not taxed (taxRate = 0). Tax goods in "other", not services.
- Match pricing language to quality tier: luxury = Kohler/KitchenAid/custom millwork; premium = Delta/Moen/LifeProof; standard = Home Depot/Lowe's value lines.
- Descriptions: one short, concrete sentence. No filler. Overview ≤ 3 sentences. Assumptions, exclusions, terms ≤ 2 sentences each.
- No emojis, no exclamation marks, no preamble, no markdown.

OUTPUT SHAPE — produce a single JSON object matching this exact schema:
{
  "title": "short, presentable estimate title — not a generic placeholder",
  "overview": "2 to 4 sentences of scope-of-work prose written directly to the client. No bullet points.",
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

Respond with ONLY the JSON object. No markdown fences, no preamble, no trailing commentary.`;

  logger.info(
    {
      projectType,
      qualityTier,
      companyName: context.companyName,
      materialCount: context.selectedMaterials.length,
      provider: 'deepseek',
    },
    'Generating AI estimate'
  );

  const text = await callDeepSeekWithRetry(systemPrompt);

  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (err) {
    logger.error({ err, textPreview: text.slice(0, 500) }, 'Failed to parse estimate-gen JSON');
    throw new AppError(
      502,
      'AI_UNPARSEABLE',
      'The AI returned an unexpected response. Please try again.',
    );
  }

  return normalizeGenerated(raw, context);
}

// ---------------------------------------------------------------------------
// DeepSeek transport with retry/backoff
// ---------------------------------------------------------------------------

async function callDeepSeekWithRetry(prompt: string): Promise<string> {
  let lastErr: unknown;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    try {
      const text = await callDeepSeek(prompt);
      if (!text.trim()) {
        throw new AppError(502, 'AI_EMPTY_RESPONSE', 'AI returned an empty response.');
      }
      return text;
    } catch (err) {
      lastErr = err;

      // Don't retry on non-retryable errors (bad auth, validation).
      if (err instanceof AppError && !isRetryableStatus(err.statusCode)) {
        throw err;
      }

      const isLastAttempt = attempt === MAX_ATTEMPTS - 1;
      if (isLastAttempt) {
        break;
      }

      const delay = INITIAL_BACKOFF_MS * Math.pow(2, attempt);
      logger.warn(
        { attempt: attempt + 1, delayMs: delay, err: errorSummary(err) },
        'DeepSeek call failed — retrying',
      );
      await sleep(delay);
    }
  }

  // All attempts failed — surface a retryable error the client can show.
  logger.error({ err: lastErr }, 'DeepSeek call failed after all retries');
  throw new AppError(
    503,
    'AI_TEMPORARILY_UNAVAILABLE',
    'AI estimating is temporarily unavailable. Please try again in a moment, or start a blank estimate.',
    undefined,
    true, // retryable
  );
}

async function callDeepSeek(systemPrompt: string): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(DEEPSEEK_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify({
        model: DEEPSEEK_MODEL,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: 'Produce the estimate JSON now. Output the JSON object only.' },
        ],
        temperature: 0.4,
        response_format: { type: 'json_object' },
        max_tokens: 8192,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new AppError(
        response.status,
        `DEEPSEEK_${response.status}`,
        `DeepSeek returned HTTP ${response.status}${body ? `: ${body.slice(0, 500)}` : ''}`,
      );
    }

    const payload = (await response.json()) as {
      choices?: Array<{ message?: { content?: string }; finish_reason?: string }>;
    };
    const choice = payload.choices?.[0];
    const content = choice?.message?.content ?? '';

    // A truncated completion is never salvageable as JSON — surface as a
    // retryable error so the outer retry can pick a lighter-weight pass.
    if (choice?.finish_reason === 'length') {
      throw new AppError(
        502,
        'AI_TRUNCATED',
        'AI response was truncated before completion.',
      );
    }

    return content;
  } catch (err: unknown) {
    if (err instanceof AppError) throw err;
    if (err instanceof Error && err.name === 'AbortError') {
      throw new AppError(504, 'AI_TIMEOUT', 'AI request timed out.');
    }
    throw new AppError(
      502,
      'AI_TRANSPORT_ERROR',
      err instanceof Error ? err.message : 'Network error calling DeepSeek',
    );
  } finally {
    clearTimeout(timer);
  }
}

function isRetryableStatus(status: number): boolean {
  // 502 covers our own AI_TRUNCATED / AI_TRANSPORT_ERROR — both are worth
  // another try. Everything ≥500 is retryable, plus the standard 408/429.
  return status === 408 || status === 409 || status === 425 || status === 429 || status >= 500;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function errorSummary(err: unknown): string {
  if (err instanceof AppError) return `${err.statusCode} ${err.code}: ${err.message}`;
  if (err instanceof Error) return `${err.name}: ${err.message}`;
  return String(err);
}

// ---------------------------------------------------------------------------
// Output normalization
// ---------------------------------------------------------------------------

function normalizeGenerated(raw: unknown, context: EstimateGenContext): GeneratedEstimate {
  const obj = (raw ?? {}) as Record<string, unknown>;
  const lineItemsRaw = Array.isArray(obj.lineItems) ? obj.lineItems : [];

  const lineItems: EstimateGenLineItem[] = lineItemsRaw.map((li) => {
    const item = (li ?? {}) as Record<string, unknown>;
    const categoryRaw = typeof item.category === 'string' ? item.category : 'other';
    const category: LineItemCategory = ['materials', 'labor', 'other'].includes(categoryRaw)
      ? (categoryRaw as LineItemCategory)
      : 'other';
    return {
      category,
      name: String(item.name ?? 'Untitled line item'),
      description: String(item.description ?? ''),
      quantity: Number(item.quantity) || 1,
      unit: String(item.unit ?? 'each'),
      unitCost: Number(item.unitCost) || 0,
      markupPercent: Number(item.markupPercent) || 0,
      taxRate: clampTaxFraction(Number(item.taxRate)),
    };
  });

  return {
    title: String(obj.title ?? context.projectTitle),
    overview: String(obj.overview ?? ''),
    lineItems,
    assumptions: String(obj.assumptions ?? ''),
    exclusions: String(obj.exclusions ?? ''),
    terms: String(obj.terms ?? ''),
    contingencyPercent: Number(obj.contingencyPercent) || (context.pricingProfile?.contingencyPercent ?? 10),
    validDays: Number(obj.validDays) || 30,
  };
}

/**
 * DeepSeek occasionally hands back `taxRate: 8.25` despite the fraction-form
 * instruction in the prompt. Normalize to a fraction in [0, 1] so the caller
 * stores the canonical representation.
 */
function clampTaxFraction(value: number): number {
  if (!Number.isFinite(value) || value <= 0) return 0;
  // If the model wrote 8.25 meaning "8.25%", divide by 100. Anything above 1
  // is nonsense as a fraction, so fold it into the fractional range.
  return value > 1 ? value / 100 : value;
}
