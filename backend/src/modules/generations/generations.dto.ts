import { AIGeneration } from '@prisma/client';

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

export function toGenerationDto(generation: AIGeneration): GenerationDto {
  return {
    id: generation.id,
    project_id: generation.projectId,
    prompt: generation.prompt,
    status: generation.status.toLowerCase(),
    preview_url: generation.previewUrl,
    thumbnail_url: generation.thumbnailUrl,
    generation_duration_ms: generation.generationDurationMs,
    error_message: generation.errorMessage,
    created_at: generation.createdAt.toISOString(),
  };
}
