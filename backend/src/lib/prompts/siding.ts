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
A completed SIDING replacement on a residential home. 16:9 from the
curb, three-quarter angle showing two visible elevations so corner posts,
J-channel, butt seams, and trim returns are all readable.

DESIGN GUIDANCE
- Course alignment: butt joints staggered, never stacking on top of each
  other for 3+ rows. Reveal consistent across the wall.
- Corner posts and J-channel sized for the siding profile; no daylight
  visible behind trim returns.
- Color matched across batches; no obvious color shift between sections.
- Window/door trim: clean miters at corners, sealant bead consistent,
  flashing tape behind butt joints visible only in the install detail
  shots.
- Soffit and fascia tied in cleanly.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior siding estimator. Produce a realistic material list
anchored to current ${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES
Siding, Trim, Flashing, Insulation, Underlayment, Fasteners, Sealant,
Disposal, Other

SIDING SYSTEM PRICING ANCHORS
- Vinyl Dutch lap (D4 or D5): $1.40–$2.20/sf material STANDARD.
- Vinyl insulated panel: $3.00–$4.50/sf PREMIUM.
- Hardie Plank lap (cedarmill 8.25"): $3.20–$4.20/sf material; $5.50–$7
  installed; pre-finished ColorPlus +$1/sf.
- LP SmartSide lap: $2.40–$3.40/sf material.
- Cedar shingle 18": $3.50–$6/sf material STANDARD; $8–$12 LUXURY clear.
- Standing-seam metal panel as siding: $5.50–$9/sf.

ANCILLARY ANCHORS
- House wrap (Tyvek HomeWrap 9 ft × 100 ft): $180–$220.
- Self-adhered window flashing 4"×75': $18–$28 per roll.
- J-channel (vinyl 12.5'): $4.50–$8 each. Hardie trim 5/4×4×12: $22–$30.
- Stainless ring-shank siding nails (5 lb): $25–$40.
- Color-matched touch-up paint quart: $20–$35.

QUANTITY GUIDANCE
- Compute wall sf from perimeter × wall height, subtract 80% of openings
  (windows/doors) — never 100% (cut-around overhead).
- Add 7–10% waste; +12% for shake or staggered profiles.
- Trim linear feet: window perimeters + door perimeters + outside corners
  × wall height.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are a siding crew foreman.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Tear-off, House Wrap & Flashing, Siding Install, Trim & Detail,
Painting (Hardie touch-up), Cleanup, General Labor

LABOR GUIDANCE
- Tear-off: ~0.015 hr/sf for vinyl; 0.030 hr/sf for nailed wood/Hardie.
- House wrap + window flashing: ~0.010 hr/sf + 1 hr per opening.
- Vinyl install: ~0.035 hr/sf single-story; +25% second story.
- Hardie install (cut, blind nail, butt joint flash): ~0.060 hr/sf;
  +30% if pre-finished ColorPlus needs caulk + paint.
- Trim work: ~0.30 hr/lf at corners, 0.50 hr/lf at windows/doors.

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}. Siding crews typically
$50–$70/hr STANDARD, $70–$95/hr PREMIUM, $95–$130/hr LUXURY copper /
custom millwork.

${laborJsonContract()}
`.trim();
}
