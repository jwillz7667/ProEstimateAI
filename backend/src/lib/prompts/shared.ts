/**
 * Shared helpers used across every per-ProjectType prompt module.
 *
 * Keeping these in one place ensures that the framing, output JSON contract,
 * and quality-tier vocabulary stay consistent — a kitchen estimate and a
 * lawn-care estimate must produce JSON the orchestrator can parse with a
 * single schema.
 */

import { PromptContext, QualityTier } from "./types";
import { LABOR_RATE_BOUNDS, renderTierBoundsBlock } from "./tier-bounds";

/**
 * Human-readable quality tier description, woven into both image and
 * material prompts so the AI ladders pricing and visual fidelity to the
 * tier the contractor chose. Pairs with `tierBoundsBlock()` below — this
 * function gives the model brand vocabulary and design language; the
 * bounds block gives it the numeric rails the orchestrator enforces.
 */
export function tierLanguage(tier: QualityTier): {
  label: string;
  visualDescription: string;
  materialAnchor: string;
  pricingMultiplier: string;
  laborRateRange: string;
} {
  const labor = LABOR_RATE_BOUNDS[tier];
  const laborRateRange = `$${labor.min}–$${labor.max}/hr`;
  switch (tier) {
    case "LUXURY":
      return {
        label: "luxury",
        visualDescription:
          "top-of-market, designer-spec materials and finishes; bespoke detailing; magazine-grade composition; thoughtful uplighting; spotless staging.",
        materialAnchor:
          "high-end specialty retailer or designer-grade SKUs (Ferguson, The Tile Shop, Restoration Hardware, SiteOne premium imports).",
        pricingMultiplier: `roughly 1.75× mid-market; labor ${laborRateRange}`,
        laborRateRange,
      };
    case "PREMIUM":
      return {
        label: "premium",
        visualDescription:
          "upgraded mid-market materials; clean, considered design; soft natural light with a warm key; well-staged but not theatrical.",
        materialAnchor:
          "upper-tier mainstream retail (Home Depot Pro, Lowe's Pro, Floor & Decor, SiteOne mid-grade).",
        pricingMultiplier: `roughly 1.3× mid-market; labor ${laborRateRange}`,
        laborRateRange,
      };
    case "STANDARD":
    default:
      return {
        label: "standard",
        visualDescription:
          "clean, contemporary, builder-grade quality; honest natural light; realistic — not aspirational.",
        materialAnchor:
          "mass-market big-box pricing (Home Depot, Lowe's, Menards everyday SKUs).",
        pricingMultiplier: `mid-market floor; labor ${laborRateRange}`,
        laborRateRange,
      };
  }
}

/**
 * Numeric tier-bounds block. Per-type prompt modules splice this in below
 * their narrative PRICING ANCHORS section so the model sees the same
 * ranges the post-AI clamp will enforce. Categories are passed in by the
 * caller (each project type cares about a different subset).
 */
export function tierBoundsBlock(
  tier: QualityTier,
  categories: string[],
): string {
  return renderTierBoundsBlock(tier, categories);
}

/**
 * Renders the universal output-contract block appended to every material
 * prompt. The contract is identical regardless of project type so the
 * orchestrator can deserialize results with one Zod schema.
 *
 * INVARIANT: `estimatedCost` is the per-unit price in USD, where the unit
 * is the value of the sibling `unit` field. The downstream estimate
 * line-item math is `lineTotal = quantity * estimatedCost * (1 + markup)`,
 * so handing back a TOTAL here multiplies the cost by `quantity` again
 * and produces N× inflated estimates. Every per-type prompt module's
 * PRICING ANCHORS section quotes per-unit ranges already — this contract
 * line keeps the model's output consistent with those anchors instead of
 * forcing it to silently convert.
 */
export function materialJsonContract(): string {
  return `
OUTPUT CONTRACT
Return ONLY a JSON object of the form:
{
  "materials": [
    {
      "name": "string — short, retailer-friendly product name",
      "category": "string — see allowed categories per project type",
      "estimatedCost": number,                  // PER-UNIT price in USD (per the unit below)
      "unit": "string — sq_ft | linear_ft | cubic_yard | each | gallon | bag | ton | hour | visit | sheet | bundle | square (roofing) | pallet",
      "quantity": number,                       // numeric quantity in the unit above
      "supplierName": "string — e.g., Home Depot, Lowe's, SiteOne, Ferguson",
      "supplierSearchQuery": "string — VERBATIM phrase a contractor would type into the retailer's search bar to verify pricing. Include brand or grade modifiers when meaningful.",
      "sortOrder": number                       // 0-based; primary materials first, miscellaneous last
    }
  ]
}
Rules:
- 5–14 PRIMARY line items + exactly ONE final "Miscellaneous Supplies" line
  (fasteners, caulk, blades, sandpaper, drop cloths, tape, etc.) priced at
  $80–$300 TOTAL — i.e., for that one Misc line, set unit="each", quantity=1,
  and estimatedCost between 80 and 300.
- estimatedCost is PER UNIT — the cost of ONE unit of the item, not the
  total for the quantity. The line total is computed downstream as
  quantity * estimatedCost. Returning a total instead of a unit price
  produces wildly inflated estimates.
  WORKED EXAMPLE (luxury kitchen quartz):
    name="Calacatta Quartz Slab", unit="sq_ft", quantity=45, estimatedCost=180
    → downstream lineTotal = 45 * 180 = $8,100 ✓
    Returning estimatedCost=8100 here would produce 45 * 8100 = $364,500 ✗.
  When unit="each" and the item is a single unit (one range, one sink),
  per-unit price IS the line total — quantity should be 1.
- estimatedCost MUST be a number (not a string, no currency symbol).
- The PRICING ANCHORS section above quotes prices in the same per-unit
  format (e.g., "$140–$220/sf"). Anchor your numbers directly to that
  range; do not multiply them by quantity.
- supplierSearchQuery should be specific enough to land on the right product
  (e.g., "Hardie Plank cedarmill 8.25 inch" — NOT just "siding").
- DO NOT include labor lines here; labor is generated separately.
- DO NOT wrap the JSON in markdown fences.
`.trim();
}

export function laborJsonContract(): string {
  return `
OUTPUT CONTRACT
Return ONLY a JSON object of the form:
{
  "labor": [
    {
      "taskName": "string — short verb-led task (e.g., 'Demo old roof', 'Mow & trim weekly')",
      "hoursEstimate": number,
      "ratePerHour": number,
      "category": "string — see allowed labor categories per project type"
    }
  ]
}
Rules:
- Round hours to the nearest 0.5; round rate to the nearest dollar.
- DO NOT bundle materials into labor.
- DO NOT wrap the JSON in markdown fences.
`.trim();
}

/**
 * Produce a compact "facts about this project" block that every prompt
 * starts with. Eliminates inconsistencies in how each module formats the
 * known facts and ensures `dimensions` / measured areas are always
 * surfaced first.
 */
export function projectFactsBlock(ctx: PromptContext): string {
  const lines: string[] = [];

  lines.push(`Project: ${ctx.projectTitle}`);
  lines.push(`Type: ${humanizeType(ctx.projectType)}`);
  lines.push(`Quality tier: ${tierLanguage(ctx.qualityTier).label}`);

  if (ctx.lawnAreaSqFt && ctx.lawnAreaSqFt > 0) {
    lines.push(`Measured lawn area: ${ctx.lawnAreaSqFt.toFixed(0)} sq ft`);
  }
  if (ctx.roofAreaSqFt && ctx.roofAreaSqFt > 0) {
    const squares = (ctx.roofAreaSqFt / 100).toFixed(1);
    lines.push(
      `Measured roof area: ${ctx.roofAreaSqFt.toFixed(0)} sq ft (${squares} squares)`,
    );
  }
  if (ctx.squareFootage && ctx.squareFootage > 0) {
    lines.push(`Project square footage: ${ctx.squareFootage} sq ft`);
  }
  if (ctx.dimensions) {
    lines.push(`Dimensions: ${ctx.dimensions}`);
  }
  if (ctx.zip) {
    lines.push(`Property ZIP: ${ctx.zip}`);
  }
  if (ctx.projectDescription) {
    lines.push(`Notes from contractor: ${ctx.projectDescription}`);
  }
  if (ctx.materials?.length) {
    const list = ctx.materials
      .map((m) => {
        const qty = m.quantity
          ? `${m.quantity}${m.unit ? " " + m.unit : ""} `
          : "";
        return `- ${qty}${m.name}`;
      })
      .join("\n");
    lines.push(
      `Contractor-specified materials (honor these names verbatim):\n${list}`,
    );
  }
  if (ctx.isRecurring) {
    lines.push(
      `Recurring contract: ${ctx.recurrenceFrequency ?? "WEEKLY"}, ` +
        `${ctx.visitsPerMonth ?? 4} visits/mo, ` +
        `${ctx.contractMonths ?? 12} month term.`,
    );
  }

  return lines.join("\n");
}

export function humanizeType(t: string): string {
  return t.replace(/_/g, " ").toLowerCase();
}

/**
 * Universal supplier hint block. Every material prompt ends with this so the
 * AI knows we're producing a search-string for live verification, not a
 * hard-link.
 */
export function supplierGuidance(ctx: PromptContext): string {
  const localHint = ctx.zip
    ? `Append "${ctx.zip}" to supplierSearchQuery only when the product is regional (e.g., concrete pavers, sod). For nationally-stocked SKUs the bare query is better.`
    : "No ZIP available; produce nationally-searchable queries.";

  return `
SUPPLIER GUIDANCE
- supplierName must be a real retailer the contractor can actually buy from
  this week (Home Depot, Lowe's, Menards, Ace Hardware, Floor & Decor,
  Ferguson, SiteOne Landscape Supply, Ewing Outdoor, John Deere Landscapes,
  Amazon Business, Grainger). Pick the one most likely to carry the SKU.
- supplierSearchQuery is the literal string a contractor would paste into
  that retailer's search box to find the same item. Be specific:
  brand + product line + key spec. Examples:
    GOOD:  "GAF Timberline HDZ Charcoal architectural shingles bundle"
    BAD:   "shingles"
    GOOD:  "Scotts Turf Builder Lawn Food 15000 sq ft"
    BAD:   "fertilizer"
- ${localHint}
`.trim();
}

/**
 * Image-generation framing block injected at the top of every imagePrompt.
 * The shared frame keeps photographic quality consistent (camera, lens,
 * staging discipline) while leaving room for each project type to specify
 * subject-matter detail.
 */
export function imageFrame(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
ROLE
You are a world-class architectural and landscape visualization
photographer. You produce ONE photorealistic, magazine-ready hero shot of
the COMPLETED project — not a render, not a sketch, not a photo of work in
progress.

PHOTOGRAPHIC RULES (apply to every shot)
- Realistic exposure with natural color and white balance. No HDR halos.
  No oversaturation. No vignette.
- Accurate, physically-plausible shadows and reflections.
- 35mm full-frame look. Sharp center, gentle falloff at edges.
- No text, no watermarks, no UI overlays, no decorative borders.
- No people in the frame unless absolutely necessary for scale.
- No brand logos visible on products or signage.
- No before/after split composition. ONE clean "after" image only.

QUALITY TIER VISUAL LANGUAGE
${tier.visualDescription}
`.trim();
}

/**
 * Edit-mode framing block. Used INSTEAD of `imageFrame` when a reference
 * photo is attached: it strips the camera-direction language ("from the
 * curb", "16:9 wide", "golden hour") and instead commands the model to
 * lock the source camera, exposure, and framing exactly. The previous
 * shared frame buried a soft "keep angle" line below per-type framing
 * rules like "shoot from the yard at golden hour" — and the model
 * obeyed the directive that came first, producing reframed afters that
 * no longer matched the before. This block must come first in the
 * prompt and forbid any reframing.
 */
export function imageEditFrame(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
ROLE
You are a high-end architectural retoucher. You receive a real
photograph of a property/room and return the SAME photograph with the
remodel completed in place. The output is an edit, not a new shot.

CAMERA LOCK — non-negotiable
- The output MUST share the input's camera position, focal length,
  height, tilt, framing, and crop pixel-for-pixel.
- DO NOT reframe, recompose, zoom in or out, change angle, push in,
  pull back, switch from eye-level to aerial, or rotate the view.
- DO NOT swap to a "more flattering" angle — the goal is a true
  before/after where the divider slider can blend the two on top of
  each other and the underlying scene aligns perfectly.
- DO NOT change the time of day, weather, or sun direction. Match the
  input's exposure, white balance, and shadow direction. If the input
  is overcast, the output is overcast. If sun is camera-left, sun
  stays camera-left.
- DO NOT add or remove neighbors' houses, the sky region, the lot
  outline, the driveway, the fence line, or any structure outside the
  scope of the contractor's request.

WHAT TO CHANGE
Only the surfaces, finishes, materials, plantings, and built additions
called out in the contractor's request. Everything else — including
the surrounding house, landscape, sky, and unrelated structures —
must remain as photographed.

PHOTOGRAPHIC RULES (apply to the edit)
- Realistic exposure that matches the source. No HDR halos.
- Physically-plausible shadows that follow the source sun direction.
- No text, watermarks, UI overlays, decorative borders.
- No people unless they were in the source.
- No brand logos visible.
- ONE clean "after" image only — no split composition, no diptych.

QUALITY TIER VISUAL LANGUAGE
${tier.visualDescription}
`.trim();
}
