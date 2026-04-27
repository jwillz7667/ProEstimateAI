import { PromptContext } from "./types";
import {
  imageFrame,
  laborJsonContract,
  materialJsonContract,
  projectFactsBlock,
  supplierGuidance,
  tierLanguage,
} from "./shared";

/**
 * LANDSCAPING — sold as a ONE-TIME install contract: planting design,
 * hardscape (pavers, walls, edging), irrigation install, lighting,
 * grading. Distinct from LAWN_CARE (recurring service contracts).
 *
 * The image prompt emphasizes a Year-1 photo (plants are sized to spec
 * but not yet matured) so the homeowner sees what they actually receive
 * — not a 5-year-grown beauty shot that sets unrealistic expectations.
 */
export function imagePrompt(ctx: PromptContext): string {
  return `
${imageFrame(ctx)}

SUBJECT
A finished LANDSCAPE install at the property in the reference photo —
photographed at delivery / "the day after we left." 16:9 framing from
the front of the property showing the installed plant beds, hardscape
(pavers, walls, edging), mulch coverage, freshly graded turf, and any
lighting fixtures.

THIS IS A YEAR-1 SHOT. DO NOT show fully-grown specimens. Plants are
nursery-size at install (1 gal, 3 gal, 7 gal containers per spec). Trees
are balled-and-burlapped or 15-gal container size — visibly young, not
mature canopy.

DESIGN GUIDANCE BY TIER
${landscapeTierGuidance(ctx)}

PLANT-BED DETAIL
- Mulch: 2–3" depth, hardwood bark by default; rich brown, not the orange
  cypress color. Even coverage right up to (but not over) the trunk
  flare. No volcano-mulching.
- Edging: clean spade-cut natural edge OR powder-coated steel edging
  flush with turf. NEVER plastic landscape edging.
- Plant spacing: realistic for nursery-size plants — there is intentional
  space between specimens that will fill in as they grow. Do not show
  jungly, fully-grown beds.
- Drip irrigation tubing tucked just under the mulch where visible.

HARDSCAPE DETAIL
- Pavers laid level, joints swept full with polymeric sand. Border
  course in a contrasting laying pattern.
- Retaining walls plumb (or with the proper backslope). Caps continuous,
  no gaps. Drainage gravel visible at the back if section view.
- Stairs: equal rise/run; treads pitched 1/4"/ft for drainage.

LIGHTING
- Path lights spaced ~8 ft apart, brass or bronze finish for PREMIUM/
  LUXURY, black powder-coat for STANDARD.
- Up-lights at the bases of feature plants and the foundation; warm 2700K.
- Photographed at twilight / blue hour ONLY when lighting is the focus;
  otherwise daylight.

NEGATIVE SPACE
- Lawn turf at install is freshly seeded straw OR fresh-laid sod (visible
  seams). Don't show a lush established lawn — that comes later.

${projectFactsBlock(ctx)}
`.trim();
}

function landscapeTierGuidance(ctx: PromptContext): string {
  switch (ctx.qualityTier) {
    case "LUXURY":
      return `Designer-spec plant palette featuring specimen Japanese maples,
hydrangea standards, boxwood parterres, ornamental grasses massed in
drifts. Bluestone or full-thickness travertine pavers; segmental dry-
stacked stone walls; full landscape lighting plan with hub-and-spoke
12V transformer; precision drip irrigation with smart controller.`;
    case "PREMIUM":
      return `Curated mid-size palette: hydrangea, Limelight, knockout roses,
boxwood, liriope, ornamental grasses. Concrete paver hardscape (Belgard
Cambridge Cobble, Techo-Bloc Blu); steel edging; LED path lighting;
inline drip irrigation in beds + rotor spray for turf.`;
    case "STANDARD":
    default:
      return `Workhorse big-box palette: arborvitae, juniper, daylilies,
Stella d'Oro, hostas, hardwood mulch, river-rock dry creek if grading
demands it. Concrete pavers (basic Pavestone Plaza or Holland Stone);
spade-cut natural edge; basic spray irrigation if quoted.`;
  }
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  const lawnNote =
    ctx.lawnAreaSqFt && ctx.lawnAreaSqFt > 0
      ? `Measured installable area: ${ctx.lawnAreaSqFt.toFixed(0)} sq ft. Quantity sod, mulch, and turf-related materials against this.`
      : `Estimate area from project description and typical residential lots (3,000–8,000 sq ft useable in front + side yards).`;

  return `
You are a senior landscape estimator at a US landscape design/build
firm. Anchor pricing to ${tier.materialAnchor} For specialty plant
material, prefer SiteOne Landscape Supply or a regional wholesale
nursery; supplierName should reflect that.

${projectFactsBlock(ctx)}
${lawnNote}

ALLOWED CATEGORIES
Plants, Trees, Sod, Seed, Mulch, Soil & Amendments, Hardscape Pavers,
Edging, Stone & Boulders, Irrigation, Lighting, Drainage, Fabric,
Disposal, Other

PLANT MATERIAL ANCHORS (per container, retail wholesale via SiteOne)
- 1 gal perennial (daylily, hosta, Stella d'Oro): $7–$12 STANDARD;
  $12–$18 PREMIUM (named cultivar); $18–$30 LUXURY (designer cultivar).
- 3 gal shrub (boxwood, knockout rose, hydrangea): $22–$35 STANDARD;
  $35–$55 PREMIUM; $55–$95 LUXURY (Limelight standards, Endless Summer).
- 7 gal evergreen (Emerald arb, Hicks yew): $45–$80 STANDARD;
  $80–$140 PREMIUM (specimen).
- B&B tree 1.5–2" caliper deciduous (red maple, river birch, redbud):
  $180–$320 STANDARD; $320–$500 PREMIUM (Japanese maple); $500–$1,200
  LUXURY (Bloodgood, weeping forms).
- Specimen evergreen 6–8 ft (Norway spruce, Green Giant): $250–$450.

GROUNDCOVER & TURF
- Sod (cool-season blend, fescue, bluegrass): $0.70–$1.40/sf STANDARD;
  $1.40–$2.20/sf PREMIUM (zoysia, certified). Per-pallet: ~450 sf/pallet.
- Grass seed (premium fescue blend) 50 lb bag: $180–$240 (covers 8,000–
  12,000 sf at overseed rate).
- Hardwood mulch (bulk, dyed brown): $40–$55 per cubic yard STANDARD;
  $55–$80 PREMIUM (cedar). Bagged 2 cu ft: $4–$7. 1 cy ≈ 100 sf at 3"
  depth.
- Topsoil / planting mix (bulk): $35–$55 per cu yd. Compost: $45–$70.

HARDSCAPE
- Concrete paver (Holland stone / Plaza): $2.50–$4.50/sf material STANDARD;
  $5.50–$9.00/sf PREMIUM (Belgard, Techo-Bloc); $10–$18/sf LUXURY (full
  bluestone, travertine).
- Paver base (3/4" road base) per ton: $30–$45; covers ~80 sf at 4"
  compacted.
- Concrete sand (1" setting bed) per ton: $35–$50; covers ~120 sf at 1".
- Polymeric sand 50 lb: $35–$45.
- Modular block retaining (Allan Block, Versa-Lok), per face foot: $7–$11.
- Capstones for retaining wall, per LF: $8–$15.
- Steel edging (Edge Pro, Permaloc) 16 ft: $55–$95 STANDARD; $95–$140
  PREMIUM aluminum.

IRRIGATION (if scope includes)
- 4" pop-up rotor (Hunter PGP, Rain Bird 5000): $14–$20 each.
- 12" pop-up spray + nozzle: $4–$8 each.
- Drip emitter tubing (1/2" + 1/4" lateral): $0.30–$0.50 per LF.
- Smart controller (Hunter Hydrawise, Rain Bird ESP): $180–$320.
- 1" PVC schedule 40, 10 ft: $7–$11.

LIGHTING (if scope includes)
- LED path light (Volt, FX): $35–$80 STANDARD; $80–$160 PREMIUM brass.
- Up-light: $25 STANDARD; $80–$140 PREMIUM brass + lens.
- 12V transformer 300W: $180–$280.
- 12 AWG direct-burial cable per 100 ft: $80–$120.

DISPOSAL & PREP
- 20 yd dumpster (sod/dirt/debris): $400–$650.
- Soil amendment incorporation: budget 1 cy compost per 500 sf bed.

QUANTITY GUIDANCE
- Mulch cu yd = bed sf × (depth in inches / 324). 3" depth = 100 sf/cy.
- Plants per bed: 1 plant per 6–9 sf for shrubs, 1 per 2–3 sf for
  perennials. Don't over-plant — Year-1 spacing matters.
- Always quote a final "Plant Establishment Warranty" by adding +5%
  contingency on plant value as a separate Other-category line.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are a landscape design/build crew foreman scoping a ONE-TIME
landscape install.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
Site Prep, Demolition, Grading, Excavation, Hardscape Install,
Plant Install, Tree Install, Sod & Seeding, Irrigation, Lighting,
Mulch & Cleanup, Equipment Rental, General Labor

LABOR GUIDANCE
- Site prep (sod stripping + minor grade): 0.05 hr/sf.
- Major grading with skid-steer (rented): 1 hr per 200 sf + rental.
- Plant install (typical 3 gal shrub): 0.40 hr each.
- Tree install (B&B 1.5–2" caliper): 1.5 hr each + 1 hr if staking required.
- Sod laying: 0.012 hr/sf (~12 hr per 1,000 sf).
- Mulch spread: 0.30 hr per cu yd installed.
- Paver install: 0.50–0.80 hr/sf (excavation + base + edge + lay + sand).
- Modular retaining wall: 1.0–1.4 hr per face foot.
- Drip irrigation install: 4–6 hr per zone.
- Spray irrigation install: 1.5 hr per head + 4 hr for valve manifold +
  4 hr controller wire.
- Low-voltage lighting install: 0.5 hr per fixture + 4 hr for transformer
  & home-run wire.

EQUIPMENT
- Skid-steer rental day: $280–$420 STANDARD; mini-excavator $380–$550.
- Plate compactor day: $80–$120.
- Sod cutter day: $90–$130.

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}. Landscape laborers
typically $40–$55/hr STANDARD, $55–$75/hr PREMIUM, $75–$110/hr LUXURY
(certified hardscape installer, ICPI / NCMA cert).

${laborJsonContract()}
`.trim();
}
