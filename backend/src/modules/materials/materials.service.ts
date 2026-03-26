import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';

/**
 * Verifies that a generation exists and its parent project belongs to the
 * given company. Returns the generation if valid.
 */
async function verifyGenerationOwnership(generationId: string, companyId: string) {
  const generation = await prisma.aIGeneration.findUnique({
    where: { id: generationId },
    include: { project: { select: { companyId: true } } },
  });

  if (!generation || generation.project.companyId !== companyId) {
    throw new NotFoundError('Generation', generationId);
  }

  return generation;
}

/**
 * List all material suggestions for a generation, ordered by sortOrder.
 * Verifies the generation's project belongs to the requesting company.
 */
export async function listByGeneration(generationId: string, companyId: string) {
  await verifyGenerationOwnership(generationId, companyId);

  const materials = await prisma.materialSuggestion.findMany({
    where: { generationId },
    orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
  });

  return materials;
}

/**
 * Update the selection state of a material suggestion.
 * Verifies the full ownership chain: material -> generation -> project -> company.
 */
export async function updateSelection(
  materialId: string,
  companyId: string,
  isSelected: boolean
) {
  // Load the material with the generation and project to verify ownership
  const material = await prisma.materialSuggestion.findUnique({
    where: { id: materialId },
    include: {
      generation: {
        include: {
          project: { select: { companyId: true } },
        },
      },
    },
  });

  if (!material || material.generation.project.companyId !== companyId) {
    throw new NotFoundError('Material', materialId);
  }

  const updated = await prisma.materialSuggestion.update({
    where: { id: materialId },
    data: { isSelected },
  });

  return updated;
}
