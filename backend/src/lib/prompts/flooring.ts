import { PromptContext } from "./types";
import {
  imageFrame,
  laborJsonContract,
  materialJsonContract,
  projectFactsBlock,
  supplierGuidance,
  tierBoundsBlock,
  tierLanguage,
} from "./shared";

const FLOORING_CATEGORIES = [
  "flooring",
  "underlayment",
  "trim",
  "hardware",
  "other",
];

export function imagePrompt(ctx: PromptContext): string {
  return `
${imageFrame(ctx)}

SUBJECT
A completed FLOORING installation, photographed at chair-rail height to
show the floor running away from camera into the room. Capture seam
patterns, plank/tile direction, and how the floor meets at doorways and
transitions. Existing baseboards reattached cleanly with matching shoe
mold or quarter-round.

DESIGN GUIDANCE
- Plank/tile direction follows the longest wall. Avoid awkward sliver
  cuts at the perimeter — show whole or near-whole boards along visible
  edges.
- Stagger pattern is realistic (random or 1/3, never 50/50 brick).
- Transition strips at doorways: T-mold for floors of equal height,
  reducer for height changes. NO visible quarter-round gaps.
- Lighting: warm natural daylight from the side; subtle bounce off the
  floor to reveal sheen and grain.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior flooring estimator. Produce a realistic material list
anchored to current ${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES
Flooring, Underlayment, Trim, Adhesive, Transition, Hardware, Other

${tierBoundsBlock(ctx.qualityTier, FLOORING_CATEGORIES)}

NARRATIVE EXAMPLES (informative — use the enforced ranges above as the source of truth)
- LVP (luxury vinyl plank): big-box budget → STANDARD; CoreTec / Karndean →
  PREMIUM; LVT designer → LUXURY.
- Engineered hardwood: domestic 3-ply → STANDARD; European multi-ply →
  PREMIUM; wide-plank rift/quartered oak → LUXURY.
- Porcelain tile 12x24 → STANDARD; large-format imported → PREMIUM.
- Carpet (residential cut pile) with pad → STANDARD/PREMIUM only; LUXURY
  rarely uses broadloom carpet.

QUANTITY GUIDANCE
- Add 7–10% waste for LVP/engineered, 10–15% for tile, 15% for diagonal
  patterns or herringbone.
- Quarter-round / shoe: linear feet ≈ room perimeter minus door openings.
- Underlayment: equal sf to floor sf if material doesn't include attached
  pad.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are a flooring crew lead.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Demolition, Subfloor Prep, Flooring Install, Trim Install, General Labor

LABOR GUIDANCE
- Demo carpet + pad: ~0.05 hr/sf. Demo glue-down: 0.2 hr/sf.
- Subfloor prep (level + screw): 0.05 hr/sf typical; 0.15/sf if patching.
- LVP/engineered click-lock install: 0.07–0.10 hr/sf.
- Glue-down hardwood: 0.15 hr/sf.
- Tile install (12x24 straight): 0.30 hr/sf.
- Trim re-install: 0.10 hr/lf.

TIER LABOR RATES: ${tier.pricingMultiplier}. The orchestrator clamps every
ratePerHour to the tier's band — quoting outside will be silently adjusted.

${laborJsonContract()}
`.trim();
}
