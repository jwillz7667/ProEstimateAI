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
 * LAWN_CARE — sold as a RECURRING service contract (typically B2B / HOA /
 * commercial property) covering scheduled mow/trim/edge, fertilization
 * rounds, weed control, aeration, and seasonal cleanups.
 *
 * The estimator MUST quote per-visit AND surface the per-month / annual
 * roll-up. The image prompt shows the property post-service: striped mow
 * pattern, sharp edges, weed-free beds — the "after we left" look the
 * property manager paid for.
 */
export function imagePrompt(ctx: PromptContext): string {
  return `
${imageFrame(ctx)}

SUBJECT
A finished LAWN CARE service visit at the property in the reference
photo — photographed the moment after the crew left. 16:9 framing from
the curb showing the lawn, beds, sidewalk/driveway edges, and any visible
trees in the lawn.

THIS IS A POST-SERVICE SHOT. The service was just completed today.

VISIBLE EVIDENCE OF GOOD SERVICE
- Mow stripes: alternating light/dark bands running parallel to the
  longest viewing axis (usually the curb). Bands consistent in width
  and direction; no missed strips. Cut height appropriate to the species
  (3–3.5" cool-season fescue/bluegrass; 1.5–2" warm-season Bermuda).
- Edges: razor-sharp vertical cut where lawn meets sidewalk, driveway,
  and curb. NO overgrown grass spilling onto concrete.
- String trim around trees, fence posts, light poles, mailbox, AC condenser
  pads — clean halo, no scalped circles, no string-marks on bark.
- Beds: bark mulch refreshed where applicable; weed-free; clean spade-cut
  edge between turf and bed.
- Clippings: blown off all hardscape (driveway, walks, patio). NO grass
  clippings on the street. Clippings either bagged, mulched fine into
  the lawn (preferred for cool-season), or removed to the truck.
- Grass color: healthy green appropriate to the season. If service is
  fertilization round, grass is uniformly verdant — no missed strips.

NEGATIVE EVIDENCE TO AVOID
- No clumping of clippings on the lawn surface.
- No tire tracks across wet turf.
- No scalped corners where the mower made tight turns.
- No mulch flung into the lawn from the trim line.

LIGHTING & SEASON
${lawnCareSeasonalCue(ctx)}

${projectFactsBlock(ctx)}
`.trim();
}

function lawnCareSeasonalCue(ctx: PromptContext): string {
  // We don't know the season at request time, so leave general guidance.
  // The contractor can refine with description text ("fall cleanup
  // visit", "first spring mow") which appears in projectFactsBlock.
  return `Mid-day or late-afternoon natural light. Match the season the
contractor mentioned in the project notes — spring (vivid green, bulb
flowers in beds), summer (deep green, fully-leafed trees), fall
(some leaf litter on hardscape only briefly before blow-off, warm
sun), or early-spring after first cut (still some thatch tones).`;
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  // Lawn area is the single most important number. If we have a measured
  // value, anchor everything to it. If not, fall back to typical
  // commercial / HOA assumptions.
  const lawnArea = ctx.lawnAreaSqFt ?? null;
  const lawnNote = lawnArea
    ? `Measured lawn area: ${lawnArea.toFixed(0)} sq ft (${(lawnArea / 43560).toFixed(2)} acres). Use this as the basis for ALL per-application materials.`
    : `No measured area provided. Assume a typical small commercial / HOA common-area lot: 12,000–25,000 sq ft of maintained turf. State your assumption inside the first material's notes by adjusting quantity to the assumed area.`;

  // Recurrence shapes the bid.
  const recurrenceCue = ctx.isRecurring
    ? `\nRECURRING CONTRACT TERMS\nFrequency: ${ctx.recurrenceFrequency ?? "WEEKLY"}\nVisits/month: ${ctx.visitsPerMonth ?? 4}\nContract length: ${ctx.contractMonths ?? 8} months (cool-season growing season).\n\nPER-VISIT CONSUMABLES are quoted ONCE per visit. The orchestrator handles the multiplication when generating the contract; do not pre-multiply here.\n\nSEASONAL APPLICATIONS (fertilizer rounds, pre-emergent, fall aeration) are quoted ONCE for the round, not per visit. Use the unit "round" or "application".`
    : "\nONE-TIME VISIT — quote materials and consumables for a single visit only.";

  return `
You are a senior commercial lawn-care estimator (B2B, HOAs, property
managers). Anchor pricing to ${tier.materialAnchor} For turf
products (fertilizer, herbicide, pre-emergent), prefer SiteOne Landscape
Supply, John Deere Landscapes (Ewing), or Lesco branded SKUs at SiteOne.

${projectFactsBlock(ctx)}
${lawnNote}
${recurrenceCue}

ALLOWED CATEGORIES
Fuel, Mower Blades, String Trimmer Line, Fertilizer, Pre-Emergent,
Post-Emergent Herbicide, Insecticide, Fungicide, Seed, Aeration,
Soil Test, Equipment Wear, PPE, Disposal, Other

PER-VISIT CONSUMABLES (ALWAYS quote these as ONE visit's worth)
- Fuel: 1.0–1.5 gal per acre mowed (riding mower) + 0.5 gal per acre
  for 2-cycle equipment (trimmers, blowers, edgers). Quote at $4–$5/gal
  market price.
- String trimmer line (.095 round, 3-lb spool): 1 spool per 80,000 sf of
  string-trim work; cost $25–$40/spool, allocate per-visit fraction.
- Mower blade wear (set of 3 commercial blades): allocate $0.40–$0.80 per
  acre cut, quoted as the per-visit fractional consumption.
- Two-cycle oil mix bottle: ~$3–$5 per bottle, fractional per visit.

SEASONAL APPLICATIONS (quote ONCE per application, not per visit)
- Pre-emergent (Dimension, Prodiamine 65 WDG): 1 lb covers ~16,000 sf at
  1.5 oz/M rate. Wholesale $90–$140/lb at SiteOne. Apply spring + fall
  split.
- Granular slow-release N (Lesco 24-0-11 + iron, Scotts ProTurf 32-0-10):
  50 lb bag covers 12,500 sf at 4 lb/M. $35–$55 STANDARD; $55–$80 PREMIUM
  (organic, Holganix, slow-release polymer-coated).
- Liquid herbicide (3-way: 2,4-D + Dicamba + MCPP) for broadleaf control:
  2.5 gal jug $90–$150; covers ~120,000 sf at typical broadcast rate.
- Spot-spray Glyphosate 41% concentrate gallon: $40–$70.
- Insecticide for grub control (Acelepryn, Imidacloprid 75 WSP): bag
  $260–$420 / season for typical commercial property.
- Fungicide (Heritage, Eagle 20EW): used only on disease pressure;
  $180–$320 per spray for typical lot.
- Aeration: equipment rental day $90–$130 walk-behind, $280–$380 stand-on
  ride. Allocate per-property.
- Overseed (turf-type tall fescue blend, 50 lb bag): $180–$240 covers
  10,000–15,000 sf at overseed rate.

DISPOSAL
- Bagged clippings disposal at municipal yard waste: $5–$15 per visit
  if hauling.

QUANTITY GUIDANCE
- All per-acre and per-1000-sf numbers should be quantified directly
  against ${lawnArea ? `${lawnArea.toFixed(0)} sq ft = ${(lawnArea / 1000).toFixed(1)} M = ${(lawnArea / 43560).toFixed(2)} acres` : "the assumed area"}.
- For a 1-acre property mowed weekly, expect ~1.5 gal fuel + ~$0.50 blade
  wear per visit.
- For a 5-acre HOA common area, scale linearly.

IMPORTANT
- DO NOT inflate per-visit consumables — the bid hinges on staying
  competitive against route-density-optimized national franchises.
- DO NOT include labor or equipment rental as material lines; those go
  in the labor prompt response.
- DO add ONE final "Miscellaneous Supplies" line covering trash bags,
  flagging tape, ear protection consumables, etc., $40–$80 per visit.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  const lawnArea = ctx.lawnAreaSqFt ?? null;
  const acres = lawnArea ? lawnArea / 43560 : null;

  return `
You are a commercial lawn-care route manager scoping crew time.

${projectFactsBlock(ctx)}
${
  acres
    ? `\nMeasured lawn area: ${lawnArea!.toFixed(0)} sq ft (${acres.toFixed(2)} acres).`
    : `\nNo measured area; assume 0.5 acre maintained turf for a typical small commercial property unless the description suggests otherwise.`
}
${
  ctx.isRecurring
    ? `\nThis is a RECURRING contract: ${ctx.recurrenceFrequency ?? "WEEKLY"}, ${ctx.visitsPerMonth ?? 4} visits/mo over ${ctx.contractMonths ?? 8} months. Quote PER-VISIT labor only — the orchestrator will multiply.`
    : "\nQuote labor for a SINGLE visit."
}

ALLOWED LABOR CATEGORIES
Mowing, String Trim & Edge, Blow-off, Bed Maintenance, Fertilization,
Herbicide Application, Aeration, Seeding & Overseed, Drive Time,
Supervision, General Labor

LABOR GUIDANCE — PER-VISIT (per acre)
- Riding mower (commercial 60" zero-turn): ~0.20 hr per acre on open
  turf; +50% for cut-up properties with islands/obstacles.
- Push-mow 21" commercial: 1.0–1.5 hr per acre — only for areas the
  rider can't reach.
- String trim & edge (sidewalks, driveways, fence lines): 0.10 hr per
  100 LF of edge.
- Blow-off (driveway, walks, beds, street curb line): 0.10 hr per 1,000
  sf of hardscape.
- Bed maintenance (light hand-pull weeding + edge touch-up): 0.20 hr per
  100 sf of bed area.

LABOR GUIDANCE — SEASONAL APPLICATIONS
- Granular fertilizer broadcast (push spreader): 0.20 hr per acre.
- Liquid herbicide spray (50 gal skid sprayer): 0.50 hr per acre +
  10 min mix/calibrate setup per property.
- Aeration (stand-on ride aerator): 0.40 hr per acre.
- Overseed broadcast + drag: 0.50 hr per acre.

DRIVE TIME / ROUTE OVERHEAD
- For a recurring contract, allocate 10–15 min of fractional drive time
  per visit (commercial routes are stop-density optimized; long-distance
  one-offs need explicit drive time).

CREW SIZE
- For commercial / HOA properties, 2-person crew typical. For per-acre
  mowing time, double to total man-hours (one operator + one trim/edge).

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}. Lawn-care crew rates
typically $35–$50/hr STANDARD, $50–$70/hr PREMIUM (certified applicator,
liability-bonded), $70–$100/hr LUXURY (white-glove HOA, ITM-certified).

${laborJsonContract()}
`.trim();
}
