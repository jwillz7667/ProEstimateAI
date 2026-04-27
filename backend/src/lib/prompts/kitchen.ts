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
A finished, fully-built KITCHEN remodel. Camera positioned at counter
height, framing the working triangle (sink → range → fridge) with the
island or peninsula in the foreground. Show countertops, backsplash, base
and upper cabinets, the range hood, pendant lighting, and a slice of the
flooring — every surface a homeowner would scrutinize.

DESIGN GUIDANCE
- Cabinetry: shaker or slab door style appropriate to the tier; soft-close
  hardware; toe kicks tight to floor; no visible filler-strip mistakes.
- Counters: continuous slabs with clean mitered seams. No obvious tile
  grout on the counter unless the tier is explicitly STANDARD rustic.
- Backsplash: full height behind the range; clean tile layout; outlets
  centered in the field, not crashing into a tile edge.
- Lighting: 2700–3000K warm white. Pendants over the island. Under-cabinet
  light on. No mixed color temps.
- Appliances: stainless or panel-ready, fingerprint-clean, doors closed.
- Staging: a single cutting board + one small herb plant. Nothing else
  cluttering the counters.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior kitchen remodel estimator at a US general contractor.
Produce a realistic material list for the project below, anchored to current
${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES (use exactly these strings)
Cabinets, Countertops, Tile, Flooring, Plumbing, Lighting, Electrical,
Appliances, Hardware, Paint, Drywall, Trim, Other

PRICING ANCHORS (US, current market)
- Stock shaker cabinets: $150–$250 per linear foot installed (cabinets
  only, no install labor here).
- Semi-custom cabinets: $250–$450/lf. Inset custom: $500–$900/lf.
- Quartz countertop slabs: $55–$95/sf (STANDARD), $95–$140/sf (PREMIUM),
  $140–$220/sf (LUXURY). Granite roughly $50–$120/sf.
- Subway tile: $4–$12/sf. Designer ceramic: $12–$30/sf. Natural stone
  mosaics: $25–$60/sf.
- Engineered hardwood: $4–$9/sf STANDARD, $9–$14/sf PREMIUM.
- 30" gas range: $700 (STANDARD GE/Whirlpool), $1,800 (PREMIUM Bosch/KA),
  $5,000+ (LUXURY Wolf/Thermador).
- Cabinet hardware: $4–$8/pull STANDARD, $14–$28/pull PREMIUM.

QUANTITY GUIDANCE
- Estimate linear feet of cabinetry from the project description or square
  footage (typical kitchen: 18–28 lf base + similar uppers).
- Estimate counter sf as ~roughly 0.55x the linear feet of base cabinets
  for L-kitchens, ~0.65x for U-kitchens with island.
- Backsplash sf is usually 30–50 sf for a typical kitchen.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a kitchen remodel project manager building a labor schedule.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Demolition, Carpentry, Cabinet Install, Countertop Install, Plumbing,
Electrical, Tile, Painting, Flooring, Appliance Install, Final Punch,
General Labor

LABOR GUIDANCE
- Demolition + haul: 8–16 hr.
- Cabinet install (stock or semi-custom): 12–24 hr for a typical kitchen.
- Countertop template + install: subbed; 4–6 hr coordination.
- Plumbing rough + finish: 8–14 hr if no relocations; +6 hr per relocation.
- Electrical (outlets, lighting circuits, range): 10–18 hr.
- Tile backsplash install: 1–1.5 hr per sf for typical patterns.
- Painting walls + ceiling: 12–20 hr.
- Appliance set + final punch: 4–8 hr.

TIER MULTIPLIER: ${tier.pricingMultiplier} on rates. Do NOT inflate hours
beyond the realistic range above.

${laborJsonContract()}
`.trim();
}
