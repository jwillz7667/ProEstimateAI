/**
 * Labor pricing guardrails — the structured backstop that keeps auto-generated
 * estimates from under-bidding labor.
 *
 * The AI material/labor generators occasionally return labor as a fraction of
 * an hour at an unrealistic rate (e.g. 0.5 hr × $35), which — combined with a
 * material list worth hundreds of dollars — produces the "$700 in materials /
 * $20 in labor" estimates contractors flagged. This module enforces three
 * independent floors, all calibrated to 2026 US contractor charge-out data:
 *
 *   1. Minimum billable hours per task (no 6-minute service calls).
 *   2. A configurable labor markup % (the contractor's margin on labor),
 *      defaulting to 25% when a company hasn't set its own.
 *   3. A labor-to-materials ratio floor + an absolute service-call minimum,
 *      so total labor can never collapse to a rounding error next to a
 *      material-heavy line list.
 *
 * Per-unit hourly rates are still clamped by `clampLaborRate` in tier-bounds.ts;
 * this module operates one layer up, on task hours, markup, and aggregate
 * labor totals. Both estimate-assembly paths (the auto-estimate created after
 * image generation, and the standalone AI-estimate generator) import from here
 * so the floors are defined once.
 */
import type { QualityTier } from "./prompts/types";
import { LABOR_RATE_BOUNDS } from "./prompts/tier-bounds";

/** Minimum billable hours for any single labor task. */
export const MIN_BILLABLE_HOURS = 1;

/**
 * Default labor markup % applied to labor line items when a company has not
 * configured its own `laborMarkupPercent`. Represents the contractor's margin
 * and supervision overhead on labor — separate from material markup.
 */
export const DEFAULT_LABOR_MARKUP_PERCENT = 25;

/**
 * Absolute minimum total labor (a trip / service-call floor) for service
 * trades, in USD. Even a trivial repair bills the truck roll. Remodel-style
 * trades get $0 here and rely on the ratio floor instead.
 */
export const SERVICE_CALL_MINIMUM_USD = 95;

/**
 * Labor-to-materials ratio floors. Service trades are labor-dominant (labor
 * should at least equal materials); remodels are material-heavy but labor
 * should still be a meaningful share of the bill.
 */
const LABOR_FLOOR_RATIO_SERVICE = 1.0;
const LABOR_FLOOR_RATIO_REMODEL = 0.45;

/**
 * Trades that are short, labor-dominant service calls rather than multi-day
 * material-heavy builds. Mirrors the home-service set in
 * `DEFAULT_LABOR_BY_PROJECT_TYPE` (generations.service.ts).
 */
const SERVICE_TRADES: ReadonlySet<string> = new Set([
  "PLUMBING",
  "ELECTRICAL",
  "HVAC",
  "APPLIANCE_REPAIR",
  "HANDYMAN",
  "PEST_CONTROL",
  "HOUSE_CLEANING",
  "JUNK_REMOVAL",
  "PRESSURE_WASHING",
  "GUTTER_SERVICES",
  "GARAGE_DOOR",
  "WINDOW_CLEANING",
  "LAWN_CARE",
]);

export function isServiceTrade(projectType: string): boolean {
  return SERVICE_TRADES.has(projectType.toUpperCase());
}

export function laborFloorRatio(projectType: string): number {
  return isServiceTrade(projectType)
    ? LABOR_FLOOR_RATIO_SERVICE
    : LABOR_FLOOR_RATIO_REMODEL;
}

/**
 * Raise sub-minimum or missing task hours up to the minimum billable window.
 * Non-finite / non-positive inputs (a model that returned 0 or null) snap to
 * the minimum rather than disappearing.
 */
export function floorBillableHours(hours: number): number {
  if (!Number.isFinite(hours) || hours <= 0) return MIN_BILLABLE_HOURS;
  return Math.max(hours, MIN_BILLABLE_HOURS);
}

/**
 * Resolve the effective labor markup %. Accepts a Prisma Decimal, number,
 * string, null, or undefined (the shapes a company column can take) and falls
 * back to the platform default for anything missing or invalid. A company that
 * deliberately sets 0% gets 0% — only `null`/absent triggers the default.
 */
export function resolveLaborMarkupPercent(value: unknown): number {
  if (value === null || value === undefined) {
    return DEFAULT_LABOR_MARKUP_PERCENT;
  }
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return DEFAULT_LABOR_MARKUP_PERCENT;
  return n;
}

export interface LaborFloorResult {
  /** True when current labor is below the floor and a top-up line is needed. */
  needed: boolean;
  /** Pre-tax USD of labor to add so total labor reaches the floor. */
  additionalAmount: number;
  /** `additionalAmount` expressed as hours at `ratePerHour`. */
  impliedHours: number;
  /** The tier's floor hourly rate used to derive `impliedHours`. */
  ratePerHour: number;
  /** The labor floor (max of ratio floor and absolute service-call minimum). */
  targetLabor: number;
}

/**
 * Compare current aggregate labor against the floor for this project type and
 * tier. When labor falls short, returns the dollar gap plus an implied
 * hours/rate breakdown the caller can surface as a single "additional labor"
 * line. Pre-tax dollars in, pre-tax dollars out (labor is untaxed).
 */
export function computeLaborFloor(params: {
  projectType: string;
  tier: QualityTier;
  materialsPreTax: number;
  laborPreTax: number;
}): LaborFloorResult {
  const { projectType, tier, materialsPreTax, laborPreTax } = params;
  const ratePerHour = LABOR_RATE_BOUNDS[tier].min;

  const materials = Number.isFinite(materialsPreTax)
    ? Math.max(0, materialsPreTax)
    : 0;
  const labor = Number.isFinite(laborPreTax) ? Math.max(0, laborPreTax) : 0;

  const ratioFloor = laborFloorRatio(projectType) * materials;
  const absoluteFloor = isServiceTrade(projectType) ? SERVICE_CALL_MINIMUM_USD : 0;
  const targetLabor = Math.max(ratioFloor, absoluteFloor);

  if (targetLabor <= 0 || labor >= targetLabor) {
    return {
      needed: false,
      additionalAmount: 0,
      impliedHours: 0,
      ratePerHour,
      targetLabor,
    };
  }

  const additionalAmount = targetLabor - labor;
  const impliedHours = ratePerHour > 0 ? additionalAmount / ratePerHour : 0;
  return {
    needed: true,
    additionalAmount,
    impliedHours,
    ratePerHour,
    targetLabor,
  };
}

/**
 * Round implied hours up to the next quarter-hour (never below the minimum
 * billable window) so the top-up line reads cleanly on the estimate and the
 * resulting line total meets or slightly exceeds the floor — never under it.
 */
export function roundUpBillableHours(hours: number): number {
  const safe = Number.isFinite(hours) && hours > 0 ? hours : MIN_BILLABLE_HOURS;
  return Math.max(MIN_BILLABLE_HOURS, Math.ceil(safe * 4) / 4);
}
