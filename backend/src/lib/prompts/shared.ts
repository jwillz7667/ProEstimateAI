/**
 * Shared helpers used across every per-ProjectType prompt module.
 *
 * Keeping these in one place ensures that the framing, output JSON contract,
 * and quality-tier vocabulary stay consistent — a kitchen estimate and a
 * lawn-care estimate must produce JSON the orchestrator can parse with a
 * single schema.
 */

import { PromptContext, QualityTier } from "./types";

/**
 * Human-readable quality tier description, woven into both image and
 * material prompts so the AI ladders pricing and visual fidelity to the
 * tier the contractor chose.
 */
export function tierLanguage(tier: QualityTier): {
  label: string;
  visualDescription: string;
  materialAnchor: string;
  pricingMultiplier: string;
} {
  switch (tier) {
    case "LUXURY":
      return {
        label: "luxury",
        visualDescription:
          "top-of-market, designer-spec materials and finishes; bespoke detailing; magazine-grade composition; thoughtful uplighting; spotless staging.",
        materialAnchor:
          "high-end specialty retailer or designer-grade SKUs (Ferguson, The Tile Shop, Restoration Hardware, SiteOne premium imports). Honest labor rates 1.6–1.9x mid-market.",
        pricingMultiplier: "1.75x mid-market floor",
      };
    case "PREMIUM":
      return {
        label: "premium",
        visualDescription:
          "upgraded mid-market materials; clean, considered design; soft natural light with a warm key; well-staged but not theatrical.",
        materialAnchor:
          "upper-tier mainstream retail (Home Depot Pro, Lowe's Pro, Floor & Decor, SiteOne mid-grade). Labor rates 1.2–1.4x standard.",
        pricingMultiplier: "1.3x mid-market floor",
      };
    case "STANDARD":
    default:
      return {
        label: "standard",
        visualDescription:
          "clean, contemporary, builder-grade quality; honest natural light; realistic — not aspirational.",
        materialAnchor:
          "mass-market big-box pricing (Home Depot, Lowe's, Menards everyday SKUs). Honest, competitive labor rates.",
        pricingMultiplier: "1.0x — anchor to current big-box retail",
      };
  }
}

/**
 * Renders the universal output-contract block appended to every material
 * prompt. The contract is identical regardless of project type so the
 * orchestrator can deserialize results with one Zod schema.
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
      "estimatedCost": number,                  // total cost for the quantity (USD)
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
  (fasteners, caulk, blades, sandpaper, drop cloths, tape, etc.) at $80–$300
  depending on tier and project size.
- Prices are TOTAL for the quantity, NOT unit price.
- estimatedCost MUST be a number (not a string, no currency symbol).
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
