import { env } from "../config/env";
import { logger } from "../config/logger";
import { getMaterialPrompt, getLaborPrompt } from "./prompts";
import {
  PromptContext,
  QualityTier,
  RecurrenceFrequency,
} from "./prompts/types";

// DeepSeek is OpenAI-compatible. `deepseek-chat` supports JSON-mode output
// via `response_format: { type: 'json_object' }`. We reuse the same transport
// shape as estimate-gen.ts (native fetch + retry/backoff) to keep the
// dependency surface small and the failure modes consistent.
const DEEPSEEK_ENDPOINT = "https://api.deepseek.com/chat/completions";
const DEEPSEEK_MODEL = "deepseek-chat";

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
  /**
   * Retailer-friendly query string the iOS client deep-links to a
   * supplier search page (Home Depot / Lowe's / SiteOne / etc.) so the
   * contractor can verify the AI estimate against live retail pricing.
   */
  supplierSearchQuery?: string;
  sortOrder: number;
}

/**
 * Context handed to the material/labor generators by the orchestrator.
 * Mirrors `ImageGenContext` but only carries the fields the text models
 * need. Optional measurement/recurrence fields are populated from the
 * project record when available.
 */
export interface MaterialGenContext {
  projectType: string;
  qualityTier: string;
  squareFootage?: string;
  dimensions?: string;
  projectTitle: string;
  projectDescription?: string;

  // Property measurements (optional — populated by maps integration).
  lawnAreaSqFt?: number | null;
  roofAreaSqFt?: number | null;
  zip?: string | null;

  // Recurrence (LAWN_CARE).
  isRecurring?: boolean;
  recurrenceFrequency?: RecurrenceFrequency | null;
  visitsPerMonth?: number | null;
  contractMonths?: number | null;
}

export interface LaborEstimate {
  taskName: string;
  hoursEstimate: number;
  ratePerHour: number;
  category: string;
}

function toPromptContext(ctx: MaterialGenContext): PromptContext {
  const tier = (ctx.qualityTier?.toUpperCase() ?? "STANDARD") as QualityTier;
  const sf = ctx.squareFootage ? Number(ctx.squareFootage) : null;
  return {
    projectType: ctx.projectType.toUpperCase(),
    qualityTier: tier === "LUXURY" || tier === "PREMIUM" ? tier : "STANDARD",
    squareFootage: Number.isFinite(sf) ? sf : null,
    dimensions: ctx.dimensions ?? null,
    projectTitle: ctx.projectTitle,
    projectDescription: ctx.projectDescription ?? null,
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
 * Generate a detailed material list using the per-ProjectType prompt
 * library. The prompt module knows the trade-specific categories,
 * pricing anchors, and supplier guidance — material-gen.ts is now a thin
 * dispatcher around DeepSeek transport.
 */
export async function generateMaterialSuggestions(
  userPrompt: string,
  context: MaterialGenContext,
): Promise<GeneratedMaterial[]> {
  if (!env.DEEPSEEK_API_KEY) {
    logger.warn(
      "DEEPSEEK_API_KEY not configured — skipping material generation",
    );
    return [];
  }

  const promptCtx = toPromptContext(context);
  const systemPrompt = `${getMaterialPrompt(promptCtx)}

CONTRACTOR'S REQUEST
"${userPrompt}"`;

  logger.info(
    {
      projectType: promptCtx.projectType,
      qualityTier: promptCtx.qualityTier,
      provider: "deepseek",
    },
    "Generating material suggestions",
  );

  try {
    const text = await callDeepSeekWithRetry(
      systemPrompt,
      "Produce the materials JSON now. Output the JSON object only.",
    );
    const parsed = JSON.parse(text) as { materials?: unknown };
    const arr = Array.isArray(parsed?.materials) ? parsed.materials : [];

    const materials: GeneratedMaterial[] = arr.map((raw, i) => {
      const m = (raw ?? {}) as Record<string, unknown>;
      const name = String(m.name ?? "Unknown Material");
      const supplierName =
        typeof m.supplierName === "string" && m.supplierName.trim()
          ? String(m.supplierName)
          : undefined;
      // Prefer the model's explicit supplierSearchQuery; if it omitted one,
      // fall back to a sensible default so the iOS client always has
      // something to deep-link with.
      const explicitQuery =
        typeof m.supplierSearchQuery === "string" &&
        m.supplierSearchQuery.trim()
          ? String(m.supplierSearchQuery).trim()
          : undefined;
      const supplierSearchQuery = explicitQuery ?? defaultSearchQuery(name);
      const sortOrderRaw = Number(m.sortOrder);
      return {
        name,
        category: String(m.category ?? "Other"),
        estimatedCost: Number(m.estimatedCost) || 0,
        unit: String(m.unit ?? "each"),
        quantity: Number(m.quantity) || 1,
        supplierName,
        supplierSearchQuery,
        sortOrder: Number.isFinite(sortOrderRaw) ? sortOrderRaw : i,
      };
    });

    logger.info({ count: materials.length }, "Material suggestions generated");
    return materials;
  } catch (err) {
    logger.error({ err }, "Material suggestion generation failed");
    return [];
  }
}

/**
 * Generate a labor schedule via the per-ProjectType prompt library. The
 * prompt module owns the trade-specific labor categories, hour anchors,
 * and rate guide; this function is the transport.
 */
export async function generateLaborEstimates(
  context: MaterialGenContext,
): Promise<LaborEstimate[]> {
  if (!env.DEEPSEEK_API_KEY) {
    logger.warn("DEEPSEEK_API_KEY not configured — skipping labor generation");
    return [];
  }

  const promptCtx = toPromptContext(context);
  const systemPrompt = getLaborPrompt(promptCtx);

  logger.info(
    {
      projectType: promptCtx.projectType,
      qualityTier: promptCtx.qualityTier,
      provider: "deepseek",
    },
    "Generating labor estimates",
  );

  try {
    const text = await callDeepSeekWithRetry(
      systemPrompt,
      "Produce the labor JSON now. Output the JSON object only.",
    );
    const parsed = JSON.parse(text) as {
      labor?: unknown;
      laborItems?: unknown;
    };
    // Older prompts produced `laborItems`; the new contract uses `labor`.
    // Accept both so a partial deploy doesn't break in flight.
    const arr = Array.isArray(parsed?.labor)
      ? parsed.labor
      : Array.isArray(parsed?.laborItems)
        ? parsed.laborItems
        : [];

    const items: LaborEstimate[] = arr.map((raw) => {
      const l = (raw ?? {}) as Record<string, unknown>;
      return {
        taskName: String(l.taskName ?? "General Labor"),
        hoursEstimate: Number(l.hoursEstimate) || 1,
        ratePerHour: Number(l.ratePerHour) || 40,
        category: String(l.category ?? "General Labor"),
      };
    });

    logger.info({ count: items.length }, "Labor estimates generated");
    return items;
  } catch (err) {
    logger.error({ err }, "Labor estimate generation failed");
    return [];
  }
}

/**
 * Last-resort retailer search query when the model omits one. We can't
 * know the right retailer without context, so we just hand the iOS
 * client the cleaned material name — the iOS deep-link picker can pair
 * it with whichever supplier the user prefers.
 */
function defaultSearchQuery(materialName: string): string {
  return materialName
    .replace(/[^\w\s\-+&./]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// ---------------------------------------------------------------------------
// DeepSeek transport with retry/backoff
// ---------------------------------------------------------------------------

async function callDeepSeekWithRetry(
  systemPrompt: string,
  userKickoff: string,
): Promise<string> {
  let lastErr: unknown;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    try {
      const text = await callDeepSeek(systemPrompt, userKickoff);
      if (!text.trim()) {
        throw new Error("DeepSeek returned an empty response");
      }
      return text;
    } catch (err) {
      lastErr = err;
      const isLastAttempt = attempt === MAX_ATTEMPTS - 1;
      if (isLastAttempt) break;
      const delay = INITIAL_BACKOFF_MS * Math.pow(2, attempt);
      logger.warn(
        { attempt: attempt + 1, delayMs: delay },
        "DeepSeek call failed — retrying",
      );
      await sleep(delay);
    }
  }

  throw lastErr ?? new Error("DeepSeek call failed");
}

async function callDeepSeek(
  systemPrompt: string,
  userKickoff: string,
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(DEEPSEEK_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify({
        model: DEEPSEEK_MODEL,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userKickoff },
        ],
        // Low temperature locks the model onto the price anchors in the
        // prompt — higher values cause it to drift toward MSRP-style
        // numbers. 0.2 keeps variety between items without letting the
        // model reinvent the pricing scale.
        temperature: 0.2,
        response_format: { type: "json_object" },
        max_tokens: 4096,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(
        `DeepSeek HTTP ${response.status}${body ? `: ${body.slice(0, 500)}` : ""}`,
      );
    }

    const payload = (await response.json()) as {
      choices?: Array<{
        message?: { content?: string };
        finish_reason?: string;
      }>;
    };
    const choice = payload.choices?.[0];
    if (choice?.finish_reason === "length") {
      throw new Error("DeepSeek response truncated before completion");
    }
    return choice?.message?.content ?? "";
  } finally {
    clearTimeout(timer);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
