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
 *
 * These are fully-burdened CHARGE-OUT rates (the number that appears on the
 * client's estimate), not a tradesperson's take-home wage. They bundle wages,
 * payroll burden, insurance, vehicle/tooling, and overhead — which is why the
 * STANDARD floor is $65/hr, not minimum wage. The previous $35 floor let the
 * model bill installed skilled labor at unskilled rates, producing the
 * "$700 in materials / $20 in labor" estimates this calibration fixes.
 * Anchors: 2026 US contractor charge-out data (HomeAdvisor, Angi, Thumbtack,
 * RSMeans crew rates) for general remodel labor through master-trade work.
 */
export const LABOR_RATE_BOUNDS: Record<QualityTier, TierRange> = {
  STANDARD: { min: 65, max: 110 },
  PREMIUM: { min: 95, max: 160 },
  LUXURY: { min: 135, max: 250 },
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

  // ─── Pool & outdoor-living (project-scale anchors, USD 2026) ───
  // Numbers are calibrated to current US contractor pricing for the Sun
  // Belt + Midwest mid-volume markets. Sources: HomeAdvisor 2026 reports,
  // Pool & Spa Marketing Quarterly, NARI cost vs. value 2026.
  pool_shell: {
    // Whole-pool unit (gunite/vinyl/fiberglass shell, plumbing, finish).
    // The orchestrator sees one big "Pool" line item — clamping is at
    // project scale, not at material scale.
    unit: "each",
    STANDARD: { min: 25000, max: 60000 },
    PREMIUM: { min: 50000, max: 95000 },
    LUXURY: { min: 90000, max: 160000 },
    promptHint: "vinyl-liner / fiberglass shell → gunite mid-size → custom gunite with tanning ledge / spa",
  },
  pool_equipment: {
    // Pump + filter + heater + automation as a packaged line.
    unit: "each",
    STANDARD: { min: 2500, max: 7000 },
    PREMIUM: { min: 6500, max: 15000 },
    LUXURY: { min: 14000, max: 32000 },
    promptHint: "Hayward standard package → Pentair IntelliConnect → smart automation + UV/salt + heat pump",
  },
  swim_up_bar: {
    unit: "each",
    STANDARD: { min: 5000, max: 12000 },
    PREMIUM: { min: 11000, max: 28000 },
    LUXURY: { min: 26000, max: 55000 },
    promptHint: "concrete bar with stools → tiled bar with seating + grill stub → custom shade + outdoor TV + wet bar",
  },
  outdoor_kitchen: {
    unit: "each",
    STANDARD: { min: 3000, max: 10000 },
    PREMIUM: { min: 9000, max: 28000 },
    LUXURY: { min: 26000, max: 70000 },
    promptHint: "drop-in grill + island → built-in grill + side burner + sink → Lynx/Wolf grill + smoker + pizza oven + fridge",
  },
  pool_decking: {
    // Around-the-pool flatwork (broom-finish concrete, exposed
    // aggregate, travertine, premium pavers).
    unit: "sq_ft",
    unitAliases: ["sf"],
    STANDARD: { min: 8, max: 22 },
    PREMIUM: { min: 20, max: 38 },
    LUXURY: { min: 35, max: 70 },
    promptHint: "broom-finish concrete → stamped concrete / travertine → cut natural stone / premium imported pavers",
  },
  decking: {
    // Built-up wood / composite deck (separate from pool_decking).
    unit: "sq_ft",
    unitAliases: ["sf"],
    STANDARD: { min: 20, max: 40 },
    PREMIUM: { min: 35, max: 60 },
    LUXURY: { min: 55, max: 100 },
    promptHint: "pressure-treated SYP → cedar / Trex Enhance composite → ipé / TimberTech AZEK Vintage / mahogany",
  },
  railing: {
    unit: "linear_ft",
    unitAliases: ["lf"],
    STANDARD: { min: 25, max: 60 },
    PREMIUM: { min: 55, max: 130 },
    LUXURY: { min: 120, max: 280 },
    promptHint: "PT 2x2 baluster → aluminum / cable rail → bronze cable / glass panel / custom welded steel",
  },
  pavers: {
    unit: "sq_ft",
    unitAliases: ["sf"],
    STANDARD: { min: 12, max: 28 },
    PREMIUM: { min: 25, max: 48 },
    LUXURY: { min: 45, max: 90 },
    promptHint: "Belgard standard → Techo-Bloc / Unilock signature → bluestone / travertine / imported clay",
  },
  concrete: {
    unit: "sq_ft",
    unitAliases: ["sf"],
    STANDARD: { min: 5, max: 11 },
    PREMIUM: { min: 9, max: 18 },
    LUXURY: { min: 16, max: 35 },
    promptHint: "broom finish 4\" → stamped or stained → polished / decorative integral color",
  },
  excavation: {
    unit: "cubic_yard",
    unitAliases: ["cy", "yd3"],
    STANDARD: { min: 20, max: 60 },
    PREMIUM: { min: 40, max: 100 },
    LUXURY: { min: 80, max: 200 },
    promptHint: "soil dig & haul → rock breaking / limited access → blast / shoring / crane-set",
  },
  aggregate: {
    unit: "ton",
    STANDARD: { min: 15, max: 50 },
    PREMIUM: { min: 30, max: 80 },
    LUXURY: { min: 60, max: 160 },
    promptHint: "crushed limestone / 57 stone → washed gravel / pea pebble → decorative river rock / Mexican beach",
  },
  fencing: {
    unit: "linear_ft",
    unitAliases: ["lf"],
    STANDARD: { min: 18, max: 40 },
    PREMIUM: { min: 35, max: 75 },
    LUXURY: { min: 70, max: 160 },
    promptHint: "PT shadowbox / dog-ear → cedar privacy / vinyl premium → ornamental aluminum / custom steel / horizontal cedar",
  },
  sod: {
    unit: "sq_ft",
    unitAliases: ["sf"],
    STANDARD: { min: 0.4, max: 0.9 },
    PREMIUM: { min: 0.85, max: 1.6 },
    LUXURY: { min: 1.5, max: 4.0 },
    promptHint: "Bermuda / Kentucky bluegrass roll → Zoysia premium → certified Empire / Palmetto / specialty cultivar",
  },
  mulch: {
    unit: "cubic_yard",
    unitAliases: ["cy", "yd3"],
    STANDARD: { min: 25, max: 55 },
    PREMIUM: { min: 45, max: 95 },
    LUXURY: { min: 85, max: 180 },
    promptHint: "double-shredded hardwood → dyed black / brown premium → cypress / cedar / decorative pine bark nuggets",
  },
  plants: {
    unit: "each",
    STANDARD: { min: 8, max: 80 },
    PREMIUM: { min: 50, max: 280 },
    LUXURY: { min: 200, max: 1500 },
    promptHint: "1-gal nursery → 7–15 gal field-grown → mature specimen tree (B&B 6\" caliper)",
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
