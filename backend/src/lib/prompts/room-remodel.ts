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
A finished general ROOM REMODEL — living room, bedroom, basement family
room, or home office. 4:3 framing showing the room from a corner with at
least two walls visible, ceiling line, flooring, and any major built-ins
or focal features.

DESIGN GUIDANCE
- Walls: clean drywall, crisp inside corners, even paint sheen.
- Trim: baseboards, casing, and crown molding all consistent in profile,
  paint sharp, miters tight.
- Flooring: appropriate to the room's use; transitions to adjacent rooms
  visible only at thresholds.
- Lighting: ceiling fixtures or recessed cans laid out symmetrically.
  Switches and outlets aligned (top of plate consistent height).
- Staging: minimal — a sofa or bed and one accent piece. No clutter.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior remodel estimator scoping a room-level remodel.
Anchor pricing to ${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES
Drywall, Trim, Flooring, Paint, Lighting, Electrical, Doors, Hardware,
Insulation, Other

PRICING ANCHORS
- 1/2" drywall sheet 4×8: $14–$18. Mud + tape per sheet ~$8.
- Baseboard MDF 5.25" 16': $14–$22. Casing 2.5" 16': $11–$16.
- Hollow-core door pre-hung 30" interior: $90–$140 STANDARD; solid-core
  $200–$320 PREMIUM; barn door package $400+ LUXURY.
- 6" recessed LED can: $18–$28 STANDARD; $35–$55 PREMIUM (Halo, Lithonia
  thin-can).
- Switch + Decora outlet: $4–$8 STANDARD; $12–$18 PREMIUM (smart).
- Ceiling fan: $80 STANDARD; $250 PREMIUM; $700+ LUXURY.

QUANTITY GUIDANCE
- Drywall sheets ≈ wall sf / 32 (per 4×8 sheet) plus ceiling sf / 32; add
  10% waste.
- Baseboard lf ≈ room perimeter minus door openings.
- Recessed cans: 1 per ~25 sf of ceiling for general lighting.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are a remodel project manager scoping a single-room remodel.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Demolition, Framing, Drywall, Electrical, Trim Carpentry, Painting,
Flooring, Final Punch, General Labor

LABOR GUIDANCE
- Demo (light): 0.05 hr/sf of room.
- Drywall hang + tape + finish (level 4): ~0.15 hr/sf of wall+ceiling.
- Trim install: ~0.10 hr/lf baseboard, 0.20 hr/lf crown.
- Door hang: 1.5 hr per pre-hung door.
- Electrical (cans + switches + outlets, no service work): 1 hr per
  device.
- Paint: see painting module estimates.

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}.

${laborJsonContract()}
`.trim();
}
