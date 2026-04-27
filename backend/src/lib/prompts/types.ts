/**
 * Shared types for the per-ProjectType prompt library.
 *
 * Each project type contributes a module conforming to {@link PromptModule}.
 * The {@link PromptContext} bundles every fact the prompt builders may need
 * — including new measurement fields populated by the maps integration —
 * so individual modules don't have to plumb arguments through the
 * orchestrator one by one.
 */

export type QualityTier = "STANDARD" | "PREMIUM" | "LUXURY";

export type RecurrenceFrequency =
  | "WEEKLY"
  | "BIWEEKLY"
  | "MONTHLY"
  | "QUARTERLY"
  | "SEASONAL";

export interface MaterialHint {
  name: string;
  category?: string | null;
  quantity?: number | null;
  unit?: string | null;
}

export interface PromptContext {
  /**
   * String form of the Prisma `ProjectType` enum (e.g. "KITCHEN", "LAWN_CARE").
   */
  projectType: string;

  qualityTier: QualityTier;
  squareFootage: number | null;
  dimensions: string | null;
  projectTitle: string;
  projectDescription: string | null;

  /**
   * Property-level measurements. Populated by maps integration when present.
   * Prompts prefer these over freeform `dimensions` because they're
   * trustworthy to estimate against.
   */
  lawnAreaSqFt?: number | null;
  roofAreaSqFt?: number | null;

  /**
   * ZIP / postal code for the property. When known, prompts inject it into
   * supplier search queries so the iOS client can deep-link to a localized
   * Home Depot / Lowe's / SiteOne result page that reflects the user's tax
   * and inventory.
   */
  zip?: string | null;

  /**
   * Recurrence metadata, used primarily by LAWN_CARE which is sold as a
   * service contract rather than a one-shot job. Prompts that consume these
   * produce per-visit material/labor lists with separate seasonal
   * line items.
   */
  isRecurring?: boolean;
  recurrenceFrequency?: RecurrenceFrequency | null;
  visitsPerMonth?: number | null;
  contractMonths?: number | null;

  /**
   * Optional user-supplied material hints from the project creation wizard.
   * The AI is told to honor these names verbatim and infer realistic
   * quantities/prices around them.
   */
  materials?: MaterialHint[];
}

export interface PromptModule {
  /** System prompt for the image generation model (Gemini / Nano-Banana). */
  imagePrompt(ctx: PromptContext): string;
  /** System prompt for the material/cost estimation model (DeepSeek). */
  materialPrompt(ctx: PromptContext): string;
  /** System prompt for the labor estimation model (DeepSeek). */
  laborPrompt(ctx: PromptContext): string;
}
