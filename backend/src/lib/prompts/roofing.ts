import { PromptContext } from "./types";
import {
  imageFrame,
  laborJsonContract,
  materialJsonContract,
  projectFactsBlock,
  supplierGuidance,
  tierLanguage,
} from "./shared";

export function imagePrompt(ctx: PromptContext): string {
  return `
${imageFrame(ctx)}

SUBJECT
A completed ROOF replacement or repair on a residential structure.
16:9 landscape framing from the curb, slightly elevated, showing the full
roof plane, ridge line, valleys, and any visible accessories
(ridge vent, drip edge, pipe boots, step flashing).

DESIGN GUIDANCE
- Shingles or panels lay perfectly flat — no fishmouth, no exposed
  fasteners on architectural shingles, no telegraphing of misaligned
  decking below.
- Color is uniform across each plane. No bundle banding from a careless
  install.
- Drip edge: clean L-line at eaves and rakes. Gutters reattached with
  matching color.
- Ridge cap continuous; no gap at hip-ridge intersections.
- Step flashing visible at any wall/roof junction, properly woven.
- Sky: bright blue with thin cirrus; soft side-light. Realistic shadow
  cast by chimneys and dormers.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  // When the maps integration has computed roof area, prefer it; otherwise
  // fall back to dimensions / squareFootage. The "squares" unit (100 sf)
  // is industry-standard for roofing materials.
  const roofSquares =
    ctx.roofAreaSqFt && ctx.roofAreaSqFt > 0
      ? Math.ceil(ctx.roofAreaSqFt / 100)
      : null;

  return `
You are a senior roofing estimator at a US roofing contractor. Produce a
realistic material list for a tear-off + replacement at the project below,
anchored to current ${tier.materialAnchor}

${projectFactsBlock(ctx)}
${roofSquares ? `\nMeasured roof = ${roofSquares} squares. Quantity all per-square materials against this number.\n` : ""}

ALLOWED CATEGORIES
Roofing, Underlayment, Flashing, Ventilation, Fasteners, Disposal, Other

ROOFING SYSTEM (DEFAULT IF NOT SPECIFIED)
- Asphalt architectural shingles, 30-year (STANDARD) or 50-year/lifetime
  laminated (PREMIUM/LUXURY).
- Synthetic underlayment over the field; 6 ft of ice-and-water shield at
  every eave and in every valley (more in northern climates).
- Galvanized drip edge at eaves and rakes.
- Ridge vent + matching ridge cap shingles.
- New pipe boots (lead-flange recommended), step flashing at wall
  intersections, counter-flashing at chimneys.

PRICING ANCHORS (US, current market)
- Architectural shingle bundle (covers 33 sf): $35–$48 STANDARD
  (GAF Timberline HDZ, Owens Corning Duration); $55–$80 PREMIUM
  (Designer / Class IV impact); $100+ LUXURY (CertainTeed Grand Manor,
  metal panels).
- 4 sq roll synthetic underlayment: $90–$140.
- Ice-and-water shield 200 sf roll: $80–$120.
- Galvanized drip edge 10 ft: $11–$16.
- Ridge vent (Cobra II / ShingleVent II) 4 ft strip: $9–$14.
- Ridge cap shingles bundle: $48–$80.
- Pipe boot lead flange: $18–$30 each. Step flashing 100 pc box: $35–$55.
- 1.5" coil roofing nails 50 lb: $80–$110.
- 30 cu yd dumpster (tear-off): $450–$700 depending on region and weight.

QUANTITY GUIDANCE
- 10% waste on shingles for hips/valleys/cuts; 15% if cut-up roof.
- One pipe boot per plumbing vent + furnace/dryer vent.
- Step flashing: 1 piece per shingle course at every wall junction.

METAL OPTION (if PREMIUM/LUXURY and the description suggests metal)
- Standing-seam steel 24-gauge: $4.50–$8.00/sf material; clip system; closure
  strips; pancake-head fasteners. Add eave + ridge trim by linear foot.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  const roofSquares =
    ctx.roofAreaSqFt && ctx.roofAreaSqFt > 0
      ? Math.ceil(ctx.roofAreaSqFt / 100)
      : null;

  return `
You are a roofing crew foreman scoping labor.

${projectFactsBlock(ctx)}
${roofSquares ? `\nMeasured roof = ${roofSquares} squares. Estimate hours against this.\n` : ""}

ALLOWED LABOR CATEGORIES
Tear-off, Decking Repair, Underlayment & Flashing, Shingle Install,
Ridge & Vent, Detail & Cleanup, General Labor

LABOR GUIDANCE
- Tear-off: ~1.5 crew-hours per square (4-person crew works fast — count
  total man-hours, not crew hours).
- Decking inspection + sheet replacement: budget 4–8 hr unless described
  as widespread rot.
- Underlayment + ice-and-water + drip edge: ~0.5 hr per square.
- Shingle install (architectural): ~1.0 hr per square on a 6/12 pitch;
  +20% on 8/12; +50% on 10/12 or steeper; +30% on cut-up roofs.
- Ridge cap + ridge vent: ~0.3 hr per ridge LF.
- Cleanup + magnet sweep + final detail: 4–6 hr.

PITCH & ACCESS RULES
- If the description mentions steep pitch (8/12+), 2nd-story walk-off,
  conservatory, or solar panels, add 15–25% to total hours.

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}. Roofing labor in the US
typically falls $55–$85/hr for STANDARD crews, $85–$110/hr for PREMIUM,
$110–$150/hr for LUXURY copper / standing seam crews.

${laborJsonContract()}
`.trim();
}
