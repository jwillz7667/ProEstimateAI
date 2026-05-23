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

const BATHROOM_CATEGORIES = [
  "vanity",
  "countertops",
  "tile",
  "flooring",
  "plumbing",
  "fixtures",
  "lighting",
  "electrical",
  "hardware",
  "paint",
  "drywall",
  "glass",
];

export function imagePrompt(ctx: PromptContext): string {
  return `
${imageFrame(ctx)}

SUBJECT
A finished, fully-built BATHROOM remodel. Portrait-oriented composition
favored (3:4). Frame the vanity wall as the hero, with the shower or tub
visible at the side, mirror reflecting natural daylight, and a hint of
flooring at the bottom of the frame.

DESIGN GUIDANCE
- Vanity: solid wood or quality MDF with a single deep drawer or shaker
  doors. Honest hardware finish (matte black, brushed nickel, brushed gold)
  consistent with faucet + lighting.
- Counter + sink: undermount basin (or vessel for LUXURY) on a quartz or
  solid-surface top. No obvious silicone caulk smears.
- Backsplash + wet walls: porcelain tile or stone, level grout lines, no
  cut tiles smaller than half-tile width on visible edges.
- Shower: glass enclosure with chrome-free hardware finish; niche with a
  contrasting accent tile; linear or square drain.
- Lighting: 2700K vanity sconces flanking the mirror; soft ambient.
- Plumbing: faucet, valves, and showerhead all matching finish.
- Staging: rolled hand towel + one stem of greenery. Nothing else.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior bathroom remodel estimator at a US general contractor.
Produce a realistic material list anchored to current ${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES
Vanity, Countertops, Tile, Flooring, Plumbing, Fixtures, Lighting,
Electrical, Hardware, Paint, Drywall, Glass, Other

${tierBoundsBlock(ctx.qualityTier, BATHROOM_CATEGORIES)}

NARRATIVE EXAMPLES (informative — use the enforced ranges above as the source of truth)
- Stock 30–36" vanity, $300–$700, is STANDARD; custom solid wood $1,200–$2,200
  is PREMIUM; designer/built-in $3,000+ is LUXURY.
- Toilet examples: Glacier Bay (~$180), Toto Drake (~$450), Toto Neorest ($900+).
- Vanity faucet examples: Glacier Bay (~$90), Delta/Moen (~$250),
  Kohler Components / Brizo ($600+).
- Shower glass: framed (~$400), frameless ($900–$1,400+).

QUANTITY GUIDANCE
- A typical 5x8 bathroom: ~40 sf floor tile, ~80 sf wet wall tile (tub
  surround), 1 vanity, 1 toilet, 1 mirror, 2 sconces.
- 5x10 with separate shower: add ~50 sf shower wall tile + glass enclosure.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are a bathroom remodel project manager.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Demolition, Plumbing, Electrical, Carpentry, Tile, Drywall, Painting,
Glass Install, Final Punch, General Labor

LABOR GUIDANCE
- Demolition + haul: 6–10 hr (full gut).
- Plumbing rough + finish: 10–16 hr (no fixture relocation); +5 hr per moved fixture.
- Electrical (sconces, GFCI, fan circuit): 6–10 hr.
- Tile install: 1–1.5 hr/sf for floor; 1.5–2 hr/sf for shower walls (mud
  pan adds 6 hr).
- Vanity + toilet set: 4–6 hr.
- Glass enclosure: subbed; 2 hr coordination + measure.

TIER LABOR RATES: ${tier.pricingMultiplier}. The orchestrator clamps every
ratePerHour to the tier's band — quoting outside will be silently adjusted.

${laborJsonContract()}
`.trim();
}
