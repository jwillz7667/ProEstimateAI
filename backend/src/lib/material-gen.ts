import { env } from '../config/env';
import { logger } from '../config/logger';

// DeepSeek is OpenAI-compatible. `deepseek-chat` supports JSON-mode output
// via `response_format: { type: 'json_object' }`. We reuse the same transport
// shape as estimate-gen.ts (native fetch + retry/backoff) to keep the
// dependency surface small and the failure modes consistent.
const DEEPSEEK_ENDPOINT = 'https://api.deepseek.com/chat/completions';
const DEEPSEEK_MODEL = 'deepseek-chat';

const MAX_ATTEMPTS = 3;
const INITIAL_BACKOFF_MS = 500;
const REQUEST_TIMEOUT_MS = 60_000;

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

export interface LaborEstimate {
  taskName: string;
  hoursEstimate: number;
  ratePerHour: number;
  category: string;
}

/**
 * Use DeepSeek to generate a detailed material list for a remodel project.
 * Returns structured JSON with materials, estimated costs, quantities, and
 * categories. Pricing is anchored to low-end US retail (Home Depot / Lowe's
 * sale pricing) so the generated estimates stay competitive for small
 * contractors rather than drifting toward MSRP.
 */
export async function generateMaterialSuggestions(
  userPrompt: string,
  context: MaterialGenContext
): Promise<GeneratedMaterial[]> {
  if (!env.DEEPSEEK_API_KEY) {
    logger.warn('DEEPSEEK_API_KEY not configured — skipping material generation');
    return [];
  }

  const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();
  const qualityTier = context.qualityTier.toLowerCase();

  const systemPrompt = `You are a professional construction estimator helping a small contractor win a job with COMPETITIVE, HOMEOWNER-FRIENDLY pricing. This is a fast quote — not a full general-contractor bid. Every price you pick must be at the LOW end of realistic 2025-2026 US retail, because the contractor is trying to beat other bids on price.

PROJECT:
- Type: ${projectType}
- Quality tier: ${qualityTier}
- Title: "${context.projectTitle}"
${context.projectDescription ? `- Description: ${context.projectDescription}` : ''}
${context.squareFootage ? `- Area: ${context.squareFootage} sq ft` : ''}
${context.dimensions ? `- Dimensions: ${context.dimensions}` : ''}
- User's request: "${userPrompt}"

STRICT PRICING RULES (follow these exactly — the app's usefulness depends on it):
- ALWAYS pick the LOW end of any realistic retail range. Never the middle. Never the top. If a gallon of paint runs $22-40, pick $22-28.
- Use Home Depot / Lowe's SALE or VALUE-LINE pricing — never MSRP, never contractor supply houses, never luxury brands (unless tier = luxury).
- Be CONSERVATIVE with quantities. A 10x12 room has 120 sq ft, not 150. Do NOT round up aggressively.
- Include only a 5% waste factor baked into quantities.

CONCRETE PRICE ANCHORS (standard tier, pick at or below these):
- Interior paint: $22-30/gallon
- Exterior paint: $28-40/gallon
- Vinyl plank flooring: $1.29-2.49/sq ft
- Basic ceramic tile: $0.79-1.99/sq ft
- Porcelain tile: $1.49-2.99/sq ft
- Laminate flooring: $0.99-2.29/sq ft
- Quartz counter slab (material only): $28-45/sq ft
- Stock kitchen cabinets: $70-140/linear ft
- Drywall 4x8 sheet: $11-14
- Bathroom vanity (24-36"): $150-380
- Toilet: $110-210
- Kitchen/bath faucet: $50-130
- Shower valve + trim: $80-170
- Standard vinyl window (36x48): $160-260
- Entry door: $200-360
- Interior door slab: $35-85
- Trim/baseboard: $0.65-1.25/linear ft
- Miscellaneous Supplies (fasteners, caulk, tape, drop cloths, sandpaper combined): $30-90 total

TOTAL PROJECT TARGETS (standard tier — aim at or BELOW these totals):
- Paint a single room: $120-280
- Bathroom refresh (paint, vanity, fixtures, no retile): $500-1,600
- Full bathroom remodel (tile, tub, fixtures): $1,400-3,200
- Kitchen cabinet refresh (paint + new hardware): $250-600
- Kitchen refresh (counters + fixtures, keep cabinets): $1,500-3,500
- Full kitchen remodel (new cabinets, counters, fixtures, no appliances): $2,500-5,500
- Flooring replace, ~200 sq ft: $350-850
- Single-face siding refresh: $1,400-3,200
- Small roof patch: $400-900

QUALITY TIER MULTIPLIER:
- standard: the anchors above as-is — low-end retail.
- premium: multiply each anchor by ~1.3x (mid-range retail: Delta, Moen, LifeProof, Allen+Roth).
- luxury: multiply each anchor by ~1.75x (upper retail: Kohler, KitchenAid). Never more than 2x.

OUTPUT:
- Generate 5-12 PRIMARY materials only. Do NOT pad the list with tiny incidental items.
- Group ALL minor items (fasteners, adhesives, caulk, tape, drop cloths, sandpaper, shims) into ONE "Miscellaneous Supplies" line at $30-90 standard / $50-130 premium / $80-180 luxury.

For each material:
- name: specific product (e.g. "LVP Flooring - Oak Look" not just "flooring")
- category: one of "Countertops", "Cabinets", "Flooring", "Tile", "Fixtures", "Lighting", "Plumbing", "Electrical", "Paint", "Hardware", "Appliances", "Lumber", "Drywall", "Insulation", "Roofing", "Siding", "Windows", "Doors", "Trim", "Other"
- estimatedCost: per-unit cost in USD — ALWAYS the LOW end of realistic retail for the tier
- unit: "sq ft", "linear ft", "each", "gallon", "box", "sheet", "bundle", "roll", "bag", "set"
- quantity: conservative, not padded
- supplierName: Home Depot, Lowe's, Floor & Decor, Menards, etc.

Respond with ONLY a JSON object shaped exactly like this — no prose, no markdown, no preamble:
{"materials":[{"name":"...","category":"...","estimatedCost":0.00,"unit":"...","quantity":0,"supplierName":"..."}]}`;

  logger.info({ projectType, qualityTier, provider: 'deepseek' }, 'Generating material suggestions');

  try {
    const text = await callDeepSeekWithRetry(systemPrompt, 'Produce the materials JSON now. Output the JSON object only.');
    const parsed = JSON.parse(text) as { materials?: unknown };
    const arr = Array.isArray(parsed?.materials) ? parsed.materials : [];

    const materials: GeneratedMaterial[] = arr.map((raw, i) => {
      const m = (raw ?? {}) as Record<string, unknown>;
      return {
        name: String(m.name ?? 'Unknown Material'),
        category: String(m.category ?? 'Other'),
        estimatedCost: Number(m.estimatedCost) || 0,
        unit: String(m.unit ?? 'each'),
        quantity: Number(m.quantity) || 1,
        supplierName: typeof m.supplierName === 'string' && m.supplierName.trim()
          ? String(m.supplierName)
          : undefined,
        sortOrder: i,
      };
    });

    logger.info({ count: materials.length }, 'Material suggestions generated');
    return materials;
  } catch (err) {
    logger.error({ err }, 'Material suggestion generation failed');
    return [];
  }
}

/**
 * Use DeepSeek to estimate labor needed for a remodel project.
 * Rates are anchored to competitive small-contractor pricing — NOT
 * general-contractor markup — so the resulting estimates stay winnable
 * against independent trades and handyman bids.
 */
export async function generateLaborEstimates(
  context: MaterialGenContext
): Promise<LaborEstimate[]> {
  if (!env.DEEPSEEK_API_KEY) {
    logger.warn('DEEPSEEK_API_KEY not configured — skipping labor generation');
    return [];
  }

  const projectType = context.projectType.replace(/_/g, ' ').toLowerCase();
  const qualityTier = context.qualityTier.toLowerCase();

  const systemPrompt = `You are a professional construction estimator. Estimate the labor needed for this remodel project with COMPETITIVE 2025-2026 US rates. Use rates that a small contractor or handyman crew would charge — NOT high-end general contractor rates. Hours must be LEAN, never padded.

PROJECT:
- Type: ${projectType}
- Quality tier: ${qualityTier}
- Title: "${context.projectTitle}"
${context.squareFootage ? `- Area: ${context.squareFootage} sq ft` : ''}

RULES:
- Only include trades actually required by the scope. No padding, no "just in case" line items.
- Hours should reflect a skilled 2-person crew working efficiently.
- For the standard tier, use the LOW end of each rate range below. Premium = mid range. Luxury = upper range.
- Do not add markup — the caller handles markup separately.

RATE GUIDE (per hour, USD):
- General labor / demolition / cleanup: $25-40
- Carpentry / framing: $35-55
- Plumbing: $45-75
- Electrical: $45-70
- Tile / stone: $40-60
- Drywall / patch: $30-48
- Painting: $25-45
- HVAC: $50-80
- Roofing: $35-55
- Flooring install: $30-50

TYPICAL HOURS (small crew, standard tier — use AT or BELOW these):
- Paint a single room: 4-8 hrs
- Bathroom refresh: 10-18 hrs
- Full bathroom remodel: 28-55 hrs
- Kitchen cabinet refresh (paint + hardware): 8-14 hrs
- Kitchen counter + fixture swap: 12-22 hrs
- Full kitchen remodel: 40-80 hrs
- Flooring ~200 sq ft: 8-14 hrs
- Small roof patch: 6-12 hrs

For each task:
- taskName: descriptive name (e.g. "Tile Installation - Floor")
- hoursEstimate: realistic hours (lean, not padded)
- ratePerHour: USD — use the LOW end of the range for standard tier
- category: the trade

Respond with ONLY a JSON object shaped exactly like this — no prose, no markdown, no preamble:
{"laborItems":[{"taskName":"...","hoursEstimate":0,"ratePerHour":0,"category":"..."}]}`;

  logger.info({ projectType, qualityTier, provider: 'deepseek' }, 'Generating labor estimates');

  try {
    const text = await callDeepSeekWithRetry(systemPrompt, 'Produce the labor JSON now. Output the JSON object only.');
    const parsed = JSON.parse(text) as { laborItems?: unknown };
    const arr = Array.isArray(parsed?.laborItems) ? parsed.laborItems : [];

    const items: LaborEstimate[] = arr.map((raw) => {
      const l = (raw ?? {}) as Record<string, unknown>;
      return {
        taskName: String(l.taskName ?? 'General Labor'),
        hoursEstimate: Number(l.hoursEstimate) || 1,
        ratePerHour: Number(l.ratePerHour) || 40,
        category: String(l.category ?? 'General Labor'),
      };
    });

    logger.info({ count: items.length }, 'Labor estimates generated');
    return items;
  } catch (err) {
    logger.error({ err }, 'Labor estimate generation failed');
    return [];
  }
}

// ---------------------------------------------------------------------------
// DeepSeek transport with retry/backoff
// ---------------------------------------------------------------------------

async function callDeepSeekWithRetry(systemPrompt: string, userKickoff: string): Promise<string> {
  let lastErr: unknown;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    try {
      const text = await callDeepSeek(systemPrompt, userKickoff);
      if (!text.trim()) {
        throw new Error('DeepSeek returned an empty response');
      }
      return text;
    } catch (err) {
      lastErr = err;
      const isLastAttempt = attempt === MAX_ATTEMPTS - 1;
      if (isLastAttempt) break;
      const delay = INITIAL_BACKOFF_MS * Math.pow(2, attempt);
      logger.warn({ attempt: attempt + 1, delayMs: delay }, 'DeepSeek call failed — retrying');
      await sleep(delay);
    }
  }

  throw lastErr ?? new Error('DeepSeek call failed');
}

async function callDeepSeek(systemPrompt: string, userKickoff: string): Promise<string> {
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
          { role: 'user', content: userKickoff },
        ],
        // Low temperature locks the model onto the price anchors in the
        // prompt — higher values cause it to drift toward MSRP-style
        // numbers. 0.2 keeps variety between items without letting the
        // model reinvent the pricing scale.
        temperature: 0.2,
        response_format: { type: 'json_object' },
        max_tokens: 4096,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`DeepSeek HTTP ${response.status}${body ? `: ${body.slice(0, 500)}` : ''}`);
    }

    const payload = (await response.json()) as {
      choices?: Array<{ message?: { content?: string }; finish_reason?: string }>;
    };
    const choice = payload.choices?.[0];
    if (choice?.finish_reason === 'length') {
      throw new Error('DeepSeek response truncated before completion');
    }
    return choice?.message?.content ?? '';
  } finally {
    clearTimeout(timer);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
