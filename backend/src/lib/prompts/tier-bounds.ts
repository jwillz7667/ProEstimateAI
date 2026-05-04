/**
 * Quality-tier numeric source of truth.
 *
 * The per-type prompt modules quote pricing anchors as narrative ranges,
 * which the model interprets loosely. This file is the structured backstop:
 * for every common material category, it defines the per-unit USD price
 * floor and ceiling at each tier. After the AI returns a material list,
 * `clampMaterialCost` snaps each item into its tier's range — items >2x
 * outside the range are treated as hallucinations and pulled all the way
 * back to the boundary. Same idea for labor in `clampLaborRate`.
 *
 * This is intentionally one file: bounds are the contract every part of
 * the pipeline (prompts, validators, audit logs) reads from.
 */
import type { QualityTier } from "./types";

export interface TierRange {
  /** Per-unit USD floor. Items below this are floored up. */
  min: number;
  /** Per-unit USD ceiling. Items above this are capped down. */
  max: number;
}

export interface CategoryBounds {
  /**
   * Canonical unit for this category. Items reported in any other unit
   * skip clamping (we can't safely normalize $/each → $/sq_ft). Use "*"
   * for catch-all categories where any unit is acceptable.
   */
  unit: string;
  /** Synonym list — the AI may use any of these in place of the canonical unit. */
  unitAliases?: string[];
  STANDARD: TierRange;
  PREMIUM: TierRange;
  LUXURY: TierRange;
  /**
   * Optional hint the prompt builder splices in next to the per-tier range.
   * Keeps the narrative voice without losing the numeric guarantee.
   */
  promptHint?: string;
}

/**
 * Per-tier labor rate bands, USD/hr, applied uniformly across all project
 * types. Per-type prompt modules can still suggest tighter bands inside
 * their narrative; this is the floor/ceiling the validator enforces.
 */
export const LABOR_RATE_BOUNDS: Record<QualityTier, TierRange> = {
  STANDARD: { min: 35, max: 80 },
  PREMIUM: { min: 55, max: 120 },
  LUXURY: { min: 95, max: 200 },
};

/**
 * Per-category, per-tier bounds keyed by lowercased category name.
 * Categories absent from this table fall back to `_default` and skip
 * unit-aware clamping.
 *
 * Numbers are calibrated to the existing per-type prompt PRICING ANCHORS
 * blocks so post-AI clamping aligns with the model's instructed ranges.
 * Adjust them here, in one place, instead of editing every prompt.
 */
export const CATEGORY_TIER_BOUNDS: Record<string, CategoryBounds> = {
  // --- Kitchen / cabinetry ---
  cabinets: {
    unit: "linear_ft",
    unitAliases: ["lf", "linear ft", "linear foot", "linear feet"],
    STANDARD: { min: 120, max: 280 },
    PREMIUM: { min: 240, max: 520 },
    LUXURY: { min: 480, max: 1100 },
    promptHint: "stock shaker → semi-custom → inset/custom",
  },
  countertops: {
    unit: "sq_ft",
    unitAliases: ["sf", "sq ft", "sqft", "square foot", "square feet"],
    STANDARD: { min: 35, max: 95 },
    PREMIUM: { min: 85, max: 150 },
    LUXURY: { min: 140, max: 280 },
    promptHint: "laminate / butcher block → granite / quartz → quartzite / Calacatta / soapstone",
  },

  // --- Vanities (bathroom) ---
  vanity: {
    unit: "each",
    STANDARD: { min: 250, max: 800 },
    PREMIUM: { min: 700, max: 2400 },
    LUXURY: { min: 2200, max: 8000 },
  },

  // --- Tile ---
  tile: {
    unit: "sq_ft",
    unitAliases: ["sf", "sq ft", "sqft"],
    STANDARD: { min: 2.5, max: 12 },
    PREMIUM: { min: 9, max: 32 },
    LUXURY: { min: 25, max: 95 },
    promptHint: "subway / 12x24 porcelain → designer ceramic → handmade / natural stone mosaics",
  },

  // --- Flooring ---
  flooring: {
    unit: "sq_ft",
    unitAliases: ["sf", "sq ft", "sqft"],
    STANDARD: { min: 2.5, max: 9 },
    PREMIUM: { min: 8, max: 17 },
    LUXURY: { min: 15, max: 38 },
    promptHint: "LVP / engineered → wide-plank engineered / luxury LVP → solid hardwood / wide-plank white oak",
  },

  // --- Appliances ---
  appliances: {
    unit: "each",
    STANDARD: { min: 350, max: 1500 },
    PREMIUM: { min: 1200, max: 4500 },
    LUXURY: { min: 4000, max: 18000 },
    promptHint: "GE / Whirlpool → Bosch / KitchenAid → Wolf / Sub-Zero / Thermador",
  },

  // --- Plumbing fixtures (faucets, valves, sinks, toilets, shower trim) ---
  plumbing: {
    unit: "each",
    STANDARD: { min: 50, max: 450 },
    PREMIUM: { min: 300, max: 1500 },
    LUXURY: { min: 1200, max: 6000 },
    promptHint: "Glacier Bay / Project Source → Delta / Moen → Kohler Components / Brizo / Waterworks",
  },
  fixtures: {
    unit: "each",
    STANDARD: { min: 50, max: 450 },
    PREMIUM: { min: 300, max: 1500 },
    LUXURY: { min: 1200, max: 6000 },
  },

  // --- Lighting ---
  lighting: {
    unit: "each",
    STANDARD: { min: 25, max: 250 },
    PREMIUM: { min: 180, max: 1100 },
    LUXURY: { min: 800, max: 5500 },
  },

  // --- Electrical (outlets, switches, breakers, wire runs) ---
  electrical: {
    unit: "each",
    STANDARD: { min: 8, max: 180 },
    PREMIUM: { min: 18, max: 280 },
    LUXURY: { min: 35, max: 600 },
  },

  // --- Hardware (pulls, knobs, hinges) ---
  hardware: {
    unit: "each",
    STANDARD: { min: 2, max: 14 },
    PREMIUM: { min: 10, max: 38 },
    LUXURY: { min: 28, max: 140 },
  },

  // --- Paint ---
  paint: {
    unit: "gallon",
    unitAliases: ["gal"],
    STANDARD: { min: 22, max: 55 },
    PREMIUM: { min: 45, max: 90 },
    LUXURY: { min: 80, max: 160 },
    promptHint: "Behr / Valspar → Sherwin-Williams ProClassic → Farrow & Ball / Benjamin Moore Aura",
  },

  // --- Drywall ---
  drywall: {
    unit: "sheet",
    STANDARD: { min: 11, max: 26 },
    PREMIUM: { min: 16, max: 40 },
    LUXURY: { min: 28, max: 65 },
  },

  // --- Trim ---
  trim: {
    unit: "linear_ft",
    unitAliases: ["lf"],
    STANDARD: { min: 0.8, max: 6 },
    PREMIUM: { min: 4, max: 16 },
    LUXURY: { min: 12, max: 45 },
  },

  // --- Glass (shower enclosures, partitions) ---
  glass: {
    unit: "each",
    STANDARD: { min: 250, max: 700 },
    PREMIUM: { min: 700, max: 1800 },
    LUXURY: { min: 1700, max: 5500 },
  },

  // --- Roofing (per square = 100 sf) ---
  roofing: {
    unit: "square",
    STANDARD: { min: 95, max: 220 },
    PREMIUM: { min: 200, max: 450 },
    LUXURY: { min: 400, max: 1300 },
    promptHint: "30-yr architectural → impact-rated / designer → metal / slate / cedar / clay",
  },
  shingles: {
    unit: "bundle",
    STANDARD: { min: 32, max: 50 },
    PREMIUM: { min: 50, max: 85 },
    LUXURY: { min: 95, max: 220 },
  },
  underlayment: {
    unit: "square",
    STANDARD: { min: 18, max: 45 },
    PREMIUM: { min: 38, max: 80 },
    LUXURY: { min: 75, max: 220 },
  },
  flashing: {
    unit: "each",
    STANDARD: { min: 6, max: 30 },
    PREMIUM: { min: 18, max: 90 },
    LUXURY: { min: 60, max: 240 },
  },
  ventilation: {
    unit: "each",
    STANDARD: { min: 10, max: 45 },
    PREMIUM: { min: 25, max: 110 },
    LUXURY: { min: 80, max: 320 },
  },
  fasteners: {
    unit: "*",
    STANDARD: { min: 4, max: 220 },
    PREMIUM: { min: 6, max: 320 },
    LUXURY: { min: 12, max: 600 },
  },

  // --- Siding ---
  siding: {
    unit: "sq_ft",
    unitAliases: ["sf"],
    STANDARD: { min: 2.5, max: 8 },
    PREMIUM: { min: 7, max: 18 },
    LUXURY: { min: 16, max: 45 },
    promptHint: "vinyl / engineered wood → fiber cement / cedar shake → real stone / true cedar / ipé",
  },

  // --- Lawn / landscape (per-sq-ft and per-bag pricing) ---
  fertilizer: {
    unit: "bag",
    STANDARD: { min: 25, max: 60 },
    PREMIUM: { min: 50, max: 95 },
    LUXURY: { min: 90, max: 220 },
  },
  seed: {
    unit: "bag",
    STANDARD: { min: 90, max: 200 },
    PREMIUM: { min: 180, max: 380 },
    LUXURY: { min: 350, max: 900 },
  },
  fuel: {
    unit: "gallon",
    unitAliases: ["gal"],
    STANDARD: { min: 3, max: 6 },
    PREMIUM: { min: 3, max: 6 },
    LUXURY: { min: 3, max: 6 },
  },

  // --- Disposal / dumpsters / permits ---
  disposal: {
    unit: "*",
    STANDARD: { min: 40, max: 900 },
    PREMIUM: { min: 60, max: 1400 },
    LUXURY: { min: 100, max: 2400 },
  },

  // --- Catch-all ---
  other: {
    unit: "*",
    STANDARD: { min: 1, max: 2500 },
    PREMIUM: { min: 1, max: 6000 },
    LUXURY: { min: 1, max: 18000 },
  },
};

/** Default fallback when a category isn't in the table. */
const DEFAULT_BOUNDS: CategoryBounds = {
  unit: "*",
  STANDARD: { min: 1, max: 5000 },
  PREMIUM: { min: 1, max: 12000 },
  LUXURY: { min: 1, max: 40000 },
};

export type ClampReason =
  | "below_floor"
  | "above_ceiling"
  | "rejected_outlier_low"
  | "rejected_outlier_high";

export interface ClampResult {
  /** Final per-unit cost after clamping. */
  estimatedCost: number;
  /** True when the original cost was outside the tier's range. */
  clamped: boolean;
  /** When clamped, why. Used for structured logging. */
  reason?: ClampReason;
  /** The cost the AI returned, before clamping. */
  originalCost: number;
}

/**
 * Normalize a unit string from the AI into our canonical form. The AI
 * sometimes writes "sq ft", sometimes "sf", sometimes "square foot" — we
 * fold them into "sq_ft" so unit comparisons are stable.
 */
export function normalizeUnit(unit: string): string {
  const cleaned = unit.trim().toLowerCase().replace(/[\s.-]+/g, "_");
  // Common shorthand → canonical.
  const map: Record<string, string> = {
    sf: "sq_ft",
    sqft: "sq_ft",
    square_foot: "sq_ft",
    square_feet: "sq_ft",
    lf: "linear_ft",
    linear_foot: "linear_ft",
    linear_feet: "linear_ft",
    cy: "cubic_yard",
    yd3: "cubic_yard",
    gal: "gallon",
    gallons: "gallon",
    sheets: "sheet",
    bundles: "bundle",
    pallets: "pallet",
    each_unit: "each",
    ea: "each",
  };
  return map[cleaned] ?? cleaned;
}

/**
 * Look up bounds for a category, normalizing the casing. Returns the
 * default catch-all when the category isn't in the table — never null,
 * so callers don't need a guard.
 */
export function boundsForCategory(category: string): CategoryBounds {
  const key = category.trim().toLowerCase();
  return CATEGORY_TIER_BOUNDS[key] ?? DEFAULT_BOUNDS;
}

/**
 * Snap an AI-generated material cost into its tier's range.
 *
 * Behavior:
 *  - When the unit doesn't match the category's canonical unit, skip clamping
 *    and pass the cost through (we can't safely compare $/each to $/sq_ft).
 *  - When the cost is above 2× the ceiling or below ½× the floor, treat it
 *    as a hallucination and snap to the boundary.
 *  - Otherwise soft-clamp into [min, max].
 *
 * Returns a `ClampResult` so callers can log clamps without re-deriving
 * the original value.
 */
export function clampMaterialCost(
  category: string,
  unit: string,
  estimatedCost: number,
  tier: QualityTier,
): ClampResult {
  const original = Number.isFinite(estimatedCost) ? estimatedCost : 0;
  if (original <= 0) {
    return { estimatedCost: 0, clamped: false, originalCost: original };
  }

  const bounds = boundsForCategory(category);
  // Skip when the unit doesn't match — we don't know how to compare prices
  // across units, and falsely clamping a $/each item against $/sq_ft bounds
  // would be worse than letting it through.
  if (bounds.unit !== "*") {
    const norm = normalizeUnit(unit);
    const allowed = [bounds.unit, ...(bounds.unitAliases ?? [])].map(normalizeUnit);
    if (!allowed.includes(norm)) {
      return { estimatedCost: original, clamped: false, originalCost: original };
    }
  }

  const range = bounds[tier];

  if (original > range.max * 2) {
    return {
      estimatedCost: range.max,
      clamped: true,
      reason: "rejected_outlier_high",
      originalCost: original,
    };
  }
  if (original < range.min / 2) {
    return {
      estimatedCost: range.min,
      clamped: true,
      reason: "rejected_outlier_low",
      originalCost: original,
    };
  }
  if (original > range.max) {
    return {
      estimatedCost: range.max,
      clamped: true,
      reason: "above_ceiling",
      originalCost: original,
    };
  }
  if (original < range.min) {
    return {
      estimatedCost: range.min,
      clamped: true,
      reason: "below_floor",
      originalCost: original,
    };
  }

  return { estimatedCost: original, clamped: false, originalCost: original };
}

/** Clamp a labor hourly rate into the tier's band. Same outlier rule as materials. */
export function clampLaborRate(
  ratePerHour: number,
  tier: QualityTier,
): ClampResult {
  const original = Number.isFinite(ratePerHour) ? ratePerHour : 0;
  if (original <= 0) {
    return { estimatedCost: 0, clamped: false, originalCost: original };
  }
  const range = LABOR_RATE_BOUNDS[tier];

  if (original > range.max * 2) {
    return {
      estimatedCost: range.max,
      clamped: true,
      reason: "rejected_outlier_high",
      originalCost: original,
    };
  }
  if (original < range.min / 2) {
    return {
      estimatedCost: range.min,
      clamped: true,
      reason: "rejected_outlier_low",
      originalCost: original,
    };
  }
  if (original > range.max) {
    return {
      estimatedCost: range.max,
      clamped: true,
      reason: "above_ceiling",
      originalCost: original,
    };
  }
  if (original < range.min) {
    return {
      estimatedCost: range.min,
      clamped: true,
      reason: "below_floor",
      originalCost: original,
    };
  }

  return { estimatedCost: original, clamped: false, originalCost: original };
}

/**
 * Render a compact table of the tier's bounds for injection into a prompt.
 * Only includes categories relevant to a project type (caller filters via
 * the `categories` argument). Format mirrors the existing PRICING ANCHORS
 * blocks so the model sees a familiar shape, just with our enforced
 * numbers.
 */
export function renderTierBoundsBlock(
  tier: QualityTier,
  categories: string[],
): string {
  const lines: string[] = [];
  lines.push(
    `ENFORCED ${tier} PRICING (per-unit USD; the orchestrator will clamp every`,
  );
  lines.push(
    `material to these ranges before saving — do not return numbers outside them):`,
  );
  for (const cat of categories) {
    const bounds = CATEGORY_TIER_BOUNDS[cat.toLowerCase()];
    if (!bounds) continue;
    const range = bounds[tier];
    const hint = bounds.promptHint ? ` — ${bounds.promptHint}` : "";
    const unit =
      bounds.unit === "*" ? "any unit" : bounds.unit.replace(/_/g, " ");
    lines.push(
      `- ${capitalize(cat)}: $${formatMoney(range.min)}–$${formatMoney(range.max)} per ${unit}${hint}`,
    );
  }
  const labor = LABOR_RATE_BOUNDS[tier];
  lines.push(
    `- Labor: $${formatMoney(labor.min)}–$${formatMoney(labor.max)}/hr (any trade)`,
  );
  return lines.join("\n");
}

function formatMoney(n: number): string {
  if (n < 1) return n.toFixed(2);
  if (n < 10) return n.toFixed(1).replace(/\.0$/, "");
  return Math.round(n).toString();
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
