export interface GenerationDto {
  id: string;
  project_id: string;
  prompt: string;
  status: string;
  preview_url: string | null;
  thumbnail_url: string | null;
  generation_duration_ms: number | null;
  error_message: string | null;
  created_at: string;
}

/**
 * The slice of an AIGeneration row the DTO actually reads. Declaring it
 * structurally (rather than the full Prisma `AIGeneration`) lets callers
 * pass a narrowed `select` that omits the multi-MB `imageData` blob —
 * status polling and list endpoints have no business loading it.
 */
export interface GenerationDtoSource {
  id: string;
  projectId: string;
  prompt: string;
  status: string;
  previewUrl: string | null;
  thumbnailUrl: string | null;
  imageMimeType: string | null;
  generationDurationMs: number | null;
  errorMessage: string | null;
  createdAt: Date;
}

export function toGenerationDto(generation: GenerationDtoSource): GenerationDto {
  // Only expose preview URLs when the image bytes actually exist. A
  // generation can be COMPLETED yet have no servable image (legacy rows, a
  // storage write that never landed) — surfacing its preview_url makes the
  // client poll a permanently-404ing endpoint on every dashboard load.
  // imageMimeType is written atomically with imageData at completion, so
  // it's the cheap source of truth for "is the image servable" without
  // pulling the blob itself.
  const hasImage = generation.imageMimeType != null;
  return {
    id: generation.id,
    project_id: generation.projectId,
    prompt: generation.prompt,
    status: generation.status.toLowerCase(),
    preview_url: hasImage ? generation.previewUrl : null,
    thumbnail_url: hasImage ? generation.thumbnailUrl : null,
    generation_duration_ms: generation.generationDurationMs,
    error_message: generation.errorMessage,
    created_at: generation.createdAt.toISOString(),
  };
}
