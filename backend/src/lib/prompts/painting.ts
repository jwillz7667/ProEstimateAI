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
A finished interior or exterior PAINT project, photographed to show
crisp cut-lines at trim, ceilings, baseboards, and corners. The newly
painted walls should be the hero — uniform sheen, no roller stipple, no
brush marks at corners.

DESIGN GUIDANCE
- Sheen sequence: matte/eggshell on walls, satin on doors and trim,
  semi-gloss on bath/kitchen trim only.
- Cut lines are razor sharp where wall meets ceiling and trim. No paint
  bleed onto trim from sloppy taping.
- For exterior: even color across siding planes, dark color reads true in
  shade as well as full sun, no patchy coverage on darker accent colors
  (where 3 coats often required).
- Existing trim, hardware, and switch covers reinstalled cleanly.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior painting estimator. Produce a realistic material list
anchored to current ${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES
Paint, Primer, Caulk, Patching, Masking, Tools/Consumables, Other

PAINT PRODUCT ANCHORS
- STANDARD: Behr Premium Plus, Valspar Optimus — $35–$45/gal interior;
  $40–$50/gal exterior.
- PREMIUM: Sherwin-Williams ProMar 200, BM Regal Select — $55–$75/gal
  interior; $70–$90/gal exterior.
- LUXURY: SW Emerald Designer Edition, BM Aura — $90–$120/gal.
- Primer (drywall PVA or stain-block Kilz): $30–$45/gal.

COVERAGE GUIDANCE
- Interior wall paint: ~350 sf/gal at 1 coat; quote 2 coats minimum.
- Trim paint: ~300 sf/gal; doors usually ~50 sf each side.
- Exterior body: ~250 sf/gal on textured surfaces (T1-11, stucco), 350
  sf/gal on smooth Hardie or vinyl.

QUANTITY GUIDANCE
- Compute wall sf as perimeter × ceiling height; subtract 15 sf per door,
  20 sf per window.
- Always include caulk (1 tube per 200 lf of trim seam), masking tape, drop
  cloths, sandpaper, mini-rollers, and a 5-gal bucket grid as a single
  Miscellaneous Supplies line.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are a paint crew foreman.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Surface Prep, Masking & Protection, Priming, Painting, Trim & Doors,
Detail & Cleanup, General Labor

LABOR GUIDANCE
- Interior wall prep + paint (2 coats): ~0.012 hr/sf of wall surface.
- Trim paint (baseboard, casing): ~0.10 hr/lf.
- Doors (each side): ~0.5 hr.
- Exterior body 2-coat: ~0.020 hr/sf.
- Add 25% for popcorn ceilings or heavy patching.
- Hand-cut walls without taping is faster (0.010 hr/sf) only on simple
  rectangles; add 30% for cut-up rooms.

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}. Painters typically
$35–$50/hr STANDARD, $50–$70/hr PREMIUM, $70–$100/hr LUXURY (lacquer/
high-gloss specialty).

${laborJsonContract()}
`.trim();
}
