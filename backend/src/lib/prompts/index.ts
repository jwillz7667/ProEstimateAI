/**
 * Per-ProjectType prompt library.
 *
 * Public surface:
 *   getImagePrompt(ctx)     → string
 *   getMaterialPrompt(ctx)  → string
 *   getLaborPrompt(ctx)     → string
 *
 * Each call dispatches to the module registered for the project type and
 * falls back to `custom.ts` when the type is unknown — so a future enum
 * value the orchestrator doesn't recognize still produces a useful
 * estimate.
 */

import { PromptContext, PromptModule } from "./types";

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
  CUSTOM: customFallback,
};

function modFor(projectType: string): PromptModule {
  return REGISTRY[projectType] ?? customFallback;
}

export function getImagePrompt(ctx: PromptContext): string {
  return modFor(ctx.projectType).imagePrompt(ctx);
}

export function getMaterialPrompt(ctx: PromptContext): string {
  return modFor(ctx.projectType).materialPrompt(ctx);
}

export function getLaborPrompt(ctx: PromptContext): string {
  return modFor(ctx.projectType).laborPrompt(ctx);
}

export type { PromptContext, PromptModule } from "./types";
