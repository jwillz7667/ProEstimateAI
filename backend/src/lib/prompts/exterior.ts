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
A completed general EXTERIOR remodel — typically a deck, porch, pergola,
fence run, exterior stairs, garage refresh, or combined façade upgrade
that spans multiple trades. 16:9 framing from the curb or yard, late-
afternoon golden hour light raking across the structure to reveal grain,
shadows, and material texture.

DESIGN GUIDANCE
- Lumber decks/porches: alternating board direction is OK on transitions
  but consistent within each section. Visible joists wear full-coverage
  stain; deck boards are level (no cupping).
- Composite decks (Trex, TimberTech, Fiberon): hidden fasteners on board
  faces; matching fascia hides joist ends; picture-frame border around
  the field.
- Fences: posts plumb, top rail dead-level, gaps consistent. Hardware
  black or matching stain.
- Pergolas: rafter ends decorative-cut consistently (sword, ogee, or
  square depending on style); no visible toe-screw heads on top.
- Stairs: stringer cuts crisp; treads same overhang front and sides;
  nosing returns.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior outdoor-living estimator. Produce a realistic material
list for the exterior project below, anchored to current
${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES
Lumber, Composite Decking, Fasteners, Hardware, Concrete, Stain/Paint,
Railing, Fencing, Lighting, Other

PRICING ANCHORS
- Pressure-treated 2×8 SYP 12 ft: $18–$26. 5/4×6 deck board 12 ft: $11–$16.
- Cedar 5/4×6 deck board 12 ft: $26–$38.
- Composite deck board 12 ft (Trex Enhance / TimberTech AZEK):
  STANDARD $48–$68, PREMIUM $80–$120, LUXURY capped polymer $130–$200.
- Composite fascia 12 ft: $35–$55. Composite hidden fastener bucket
  (Camo / Cortex) per 100 sf: $80–$110.
- Galvanized joist hangers: $1.50–$3 each. Simpson SDWS structural screws
  5" 50 ct: $42–$65.
- Concrete deck-block / 80 lb bag: $7–$9. Sonotube + bag concrete pier
  for footing: ~$25 each + 1 bag rebar.
- 4×4×8 cedar fence picket: $4–$7. 6 ft pre-built fence panel: $80–$140.
- Outdoor low-voltage path light: $25 STANDARD; $80 PREMIUM (brass).

QUANTITY GUIDANCE
- Deck boards: deck sf × 1.10 / board face coverage; account for picture-
  frame border (12 lf at perimeter).
- Joists: joist on-center spacing usually 16" (composite) or 12" (capped).
- Fence: 1 picket per 7" of run; 1 post per 8 ft section.
- Stain coverage: 200 sf/gal first coat on rough lumber; 350 sf/gal on
  composite + sealer.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are an outdoor-living crew foreman.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Site Prep, Footings & Posts, Framing, Decking Install, Railing,
Stair Build, Stain & Seal, Fence Install, Cleanup, General Labor

LABOR GUIDANCE
- Footings (manual auger): 1.5 hr each.
- Joist framing: ~0.10 hr/sf of deck.
- Composite decking install (hidden fastener): ~0.18 hr/sf with picture
  frame; 0.13/sf without.
- Cable or aluminum railing: 0.40 hr/lf.
- Stairs: 4–6 hr per 3-rise flight; +6 hr if landing.
- 6-ft cedar fence panel install: 1.0–1.5 hr per 8 ft section + post setting.

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}. Outdoor-living crews
typically $60–$80/hr STANDARD, $80–$110/hr PREMIUM, $110–$150/hr LUXURY.

${laborJsonContract()}
`.trim();
}
