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
 * CUSTOM is the registry's fallback. It runs when:
 *   - The project type is `CUSTOM` (contractor explicitly chose generic).
 *   - The orchestrator encounters a future enum value not yet wired into
 *     a dedicated module.
 *
 * It instructs the AI to lean on `projectDescription` to figure out the
 * trade rather than committing to one.
 */
export function imagePrompt(ctx: PromptContext): string {
  return `
${imageFrame(ctx)}

SUBJECT
A finished construction or remodeling project as described by the
contractor in the notes below. Use the description to determine the
appropriate framing and subject matter; if the description is sparse,
default to a 4:3 interior shot of the completed scope.

INFERENCE RULES
- If the description mentions roof / shingles / drip edge → roofing shot.
- If it mentions plant beds / sod / mulch → landscape shot.
- If it mentions sink / vanity / shower → bathroom shot.
- If it mentions cabinets / counters → kitchen shot.
- If it mentions deck / fence / pergola → exterior outdoor-living shot.
- Otherwise default to a clean interior remodel shot.

${projectFactsBlock(ctx)}
`.trim();
}

export function materialPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);

  return `
You are a senior general estimator. The project type was not specified
or doesn't fit a standard trade — infer the appropriate trade from the
project description and produce a realistic material list anchored to
${tier.materialAnchor}

${projectFactsBlock(ctx)}

ALLOWED CATEGORIES
Materials, Lumber, Drywall, Paint, Hardware, Plumbing, Electrical,
Lighting, Flooring, Tile, Trim, Insulation, Roofing, Siding, Windows,
Doors, Concrete, Plants, Sod, Mulch, Hardscape, Other

GUIDANCE
- Read the project description carefully and infer the dominant trade
  before producing the list.
- Use realistic categories for the inferred trade — don't over-broaden.
- Always include exactly ONE final "Miscellaneous Supplies" line.

${supplierGuidance(ctx)}

${materialJsonContract()}
`.trim();
}

export function laborPrompt(ctx: PromptContext): string {
  const tier = tierLanguage(ctx.qualityTier);
  return `
You are a senior general estimator producing a labor schedule. The
project type wasn't specified — infer the trade from the description.

${projectFactsBlock(ctx)}

ALLOWED LABOR CATEGORIES
General Labor, Demolition, Carpentry, Plumbing, Electrical, Tile,
Drywall, Painting, Flooring, Roofing, Siding, Landscaping, Cleanup,
Final Punch, Supervision

TIER RATE MULTIPLIER: ${tier.pricingMultiplier}.

${laborJsonContract()}
`.trim();
}
