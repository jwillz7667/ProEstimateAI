/**
 * Per-ProjectType prompt library.
 *
 * Public surface:
 *   getImagePrompt(ctx)        → string  // text-to-image (no source photo)
 *   getImageEditPrompt(ctx)    → string  // edit-in-place (camera locked)
 *   getMaterialPrompt(ctx)     → string
 *   getLaborPrompt(ctx)        → string
 *
 * Each call dispatches to the module registered for the project type and
 * falls back to `custom.ts` when the type is unknown — so a future enum
 * value the orchestrator doesn't recognize still produces a useful
 * estimate.
 */

import { PromptContext, PromptModule } from "./types";
import { imageEditFrame, projectFactsBlock } from "./shared";

import * as kitchen from "./kitchen";
import * as bathroom from "./bathroom";
import * as flooring from "./flooring";
import * as roofing from "./roofing";
import * as painting from "./painting";
import * as siding from "./siding";
import * as roomRemodel from "./room-remodel";
import * as exterior from "./exterior";
import * as landscaping from "./landscaping";
import * as lawnCare from "./lawn-care";
import * as service from "./service";
import * as customFallback from "./custom";

const REGISTRY: Record<string, PromptModule> = {
  KITCHEN: kitchen,
  BATHROOM: bathroom,
  FLOORING: flooring,
  ROOFING: roofing,
  PAINTING: painting,
  SIDING: siding,
  ROOM_REMODEL: roomRemodel,
  EXTERIOR: exterior,
  LANDSCAPING: landscaping,
  LAWN_CARE: lawnCare,
  // Home-service trades — all share the service-call prompt module, which
  // differentiates per trade internally.
  PLUMBING: service,
  ELECTRICAL: service,
  HVAC: service,
  APPLIANCE_REPAIR: service,
  HANDYMAN: service,
  PEST_CONTROL: service,
  HOUSE_CLEANING: service,
  JUNK_REMOVAL: service,
  PRESSURE_WASHING: service,
  GUTTER_SERVICES: service,
  FENCING: service,
  GARAGE_DOOR: service,
  WINDOW_CLEANING: service,
  CUSTOM: customFallback,
};

function modFor(projectType: string): PromptModule {
  return REGISTRY[projectType] ?? customFallback;
}

export function getImagePrompt(ctx: PromptContext): string {
  return modFor(ctx.projectType).imagePrompt(ctx);
}

/**
 * Edit-mode image prompt. Produced by composing the camera-locked
 * `imageEditFrame` (always first, so it takes precedence over any other
 * directive) with the project facts. We deliberately do NOT splice in
 * the per-type imagePrompt here — those modules carry their own framing
 * language ("16:9 from the curb at golden hour") which used to override
 * the soft "keep angle" hint and produce reframed afters that no longer
 * matched the source. The contractor's user prompt is appended by the
 * orchestrator with the full editing directive.
 */
export function getImageEditPrompt(ctx: PromptContext): string {
  return `${imageEditFrame(ctx)}\n\n${projectFactsBlock(ctx)}`;
}

export function getMaterialPrompt(ctx: PromptContext): string {
  return modFor(ctx.projectType).materialPrompt(ctx);
}

export function getLaborPrompt(ctx: PromptContext): string {
  return modFor(ctx.projectType).laborPrompt(ctx);
}

export type { PromptContext, PromptModule } from "./types";
