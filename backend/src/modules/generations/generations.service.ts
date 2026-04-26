import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { NotFoundError } from '../../lib/errors';
import { generatePreviewImage, getSystemPrompt, ImageGenContext, MaterialSpec, ReferencePhoto } from '../../lib/image-gen';
import { generateMaterialSuggestions, generateLaborEstimates, MaterialGenContext } from '../../lib/material-gen';
import { recordUsage } from '../../lib/usage-limits';
import { gateAIAction } from '../commerce/entitlement-gate';
import { env } from '../../config/env';
import { CreateGenerationInput } from './generations.validators';
import * as estimatesService from '../estimates/estimates.service';
import * as estimateLineItemsService from '../estimate-line-items/estimate-line-items.service';
import { CreateEstimateLineItemInput } from '../estimate-line-items/estimate-line-items.validators';

/**
 * Verifies that a project exists and belongs to the given company.
 * Returns the full project for context building.
 */
async function verifyProjectOwnership(projectId: string, companyId: string) {
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
  });

  if (!project) {
    throw new NotFoundError('Project', projectId);
  }

  return project;
}

/**
 * Build image generation context from the project data.
 */
function buildImageContext(project: {
  projectType: string;
  qualityTier: string;
  title: string;
  description: string | null;
  squareFootage: unknown;
  dimensions: string | null;
}): ImageGenContext {
  return {
    projectType: project.projectType,
    qualityTier: project.qualityTier,
    projectTitle: project.title,
    projectDescription: project.description ?? undefined,
    squareFootage: project.squareFootage ? String(project.squareFootage) : undefined,
    dimensions: project.dimensions ?? undefined,
  };
}

/**
 * Convert input materials array to MaterialSpec for prompt injection.
 */
function toMaterialSpecs(materials?: Array<{ name: string; category?: string; quantity?: number; unit?: string }>): MaterialSpec[] | undefined {
  if (!materials || materials.length === 0) return undefined;
  return materials.map((m) => ({
    name: m.name,
    category: m.category,
    quantity: m.quantity,
    unit: m.unit,
  }));
}

/**
 * Fire-and-forget: call Nano Banana 2 and update the generation record.
 * Runs outside the request transaction so the API responds immediately
 * while the image generates in the background.
 */
async function processGeneration(generationId: string, prompt: string, context: ImageGenContext, projectId: string, companyId: string, userId: string) {
  try {
    // Mark as PROCESSING
    await prisma.aIGeneration.update({
      where: { id: generationId },
      data: { status: 'PROCESSING' },
    });

    // Check that at least one image generation provider is configured
    if (!env.PIAPI_API_KEY && !env.GOOGLE_AI_API_KEY) {
      logger.warn({ generationId }, 'No image generation provider configured — marking generation as failed');
      await prisma.aIGeneration.update({
        where: { id: generationId },
        data: {
          status: 'FAILED',
          errorMessage: 'Image generation service is not configured. Contact support.',
        },
      });
      return;
    }

    // Fetch the project's uploaded reference photo (most recent ORIGINAL asset with stored image data)
    let referencePhoto: ReferencePhoto | undefined;
    let referenceAssetUrl: string | undefined;
    const originalAsset = await prisma.asset.findFirst({
      where: { projectId, assetType: 'ORIGINAL', imageData: { not: null } },
      orderBy: { createdAt: 'desc' },
      select: { id: true, imageData: true, imageMimeType: true },
    });

    if (originalAsset?.imageData && originalAsset?.imageMimeType) {
      referencePhoto = {
        base64Data: originalAsset.imageData,
        mimeType: originalAsset.imageMimeType,
      };
      // Public URL for PiAPI (which requires image URLs, not base64)
      referenceAssetUrl = `${env.API_BASE_URL}/v1/assets/${originalAsset.id}/image`;
      logger.info({ generationId, projectId, assetId: originalAsset.id }, 'Found reference photo for generation');
    } else {
      logger.info({ generationId, projectId }, 'No reference photo found — generating without input image');
    }

    // Call image generation with provider fallback (PiAPI primary → Google GenAI fallback)
    const result = await generatePreviewImage(prompt, context, referencePhoto, referenceAssetUrl);

    if (!result) {
      await prisma.aIGeneration.update({
        where: { id: generationId },
        data: {
          status: 'FAILED',
          errorMessage: 'Image generation returned no result. Please try again.',
        },
      });
      return;
    }

    // Store the image data and mark as COMPLETED
    const previewUrl = `${env.API_BASE_URL}/v1/generations/${generationId}/preview`;
    const thumbnailUrl = previewUrl;

    await prisma.aIGeneration.update({
      where: { id: generationId },
      data: {
        status: 'COMPLETED',
        imageData: result.base64Data,
        imageMimeType: result.mimeType,
        previewUrl,
        thumbnailUrl,
        generationDurationMs: result.durationMs,
      },
    });

    logger.info(
      { generationId, durationMs: result.durationMs },
      'Generation completed successfully'
    );

    // Auto-generate material suggestions and create estimate in the background
    generateAndStoreMaterials(generationId, projectId, companyId, userId, prompt, context).catch((err) => {
      logger.error({ err, generationId }, 'Material suggestion generation failed (non-critical)');
    });
  } catch (err) {
    logger.error({ err, generationId }, 'Generation processing failed');
    try {
      await prisma.aIGeneration.update({
        where: { id: generationId },
        data: {
          status: 'FAILED',
          errorMessage: 'An unexpected error occurred during image generation.',
        },
      });
    } catch (updateErr) {
      logger.error({ updateErr, generationId }, 'Failed to update generation status to FAILED');
    }
  }
}

/**
 * After image generation completes, call Gemini text model to generate
 * material suggestions and labor estimates, then store them in the DB.
 * Finally, auto-creates an estimate with the generated materials as line items.
 */
async function generateAndStoreMaterials(
  generationId: string,
  projectId: string,
  companyId: string,
  userId: string,
  prompt: string,
  context: ImageGenContext
) {
  const matContext: MaterialGenContext = {
    projectType: context.projectType,
    qualityTier: context.qualityTier,
    squareFootage: context.squareFootage,
    dimensions: context.dimensions,
    projectTitle: context.projectTitle,
    projectDescription: context.projectDescription,
  };

  // Generate materials and labor in parallel
  const [materials, laborEstimates] = await Promise.all([
    generateMaterialSuggestions(prompt, matContext),
    generateLaborEstimates(matContext),
  ]);

  if (materials.length === 0 && laborEstimates.length === 0) {
    logger.warn({ generationId }, 'No materials or labor estimates generated');
    return;
  }

  // Store material suggestions
  const materialRecords = materials.map((m) => ({
    generationId,
    projectId,
    name: m.name,
    category: m.category,
    estimatedCost: m.estimatedCost,
    unit: m.unit,
    quantity: m.quantity,
    supplierName: m.supplierName ?? null,
    isSelected: true, // Default all to selected
    sortOrder: m.sortOrder,
  }));

  // Store labor as material suggestions with category "Labor"
  const laborRecords = laborEstimates.map((l, i) => ({
    generationId,
    projectId,
    name: l.taskName,
    category: `Labor - ${l.category}`,
    estimatedCost: l.ratePerHour,
    unit: 'hour',
    quantity: l.hoursEstimate,
    supplierName: null,
    isSelected: true,
    sortOrder: materials.length + i,
  }));

  const allRecords = [...materialRecords, ...laborRecords];

  await prisma.materialSuggestion.createMany({ data: allRecords });

  logger.info(
    { generationId, materialCount: materialRecords.length, laborCount: laborRecords.length },
    'Material suggestions and labor estimates stored'
  );

  // Fetch the IDs of the just-created material suggestions (materials only, not labor records)
  // for linking to estimate line items via sourceMaterialSuggestionId
  const storedMaterials = await prisma.materialSuggestion.findMany({
    where: { generationId, projectId },
    select: { id: true },
    orderBy: { sortOrder: 'asc' },
  });

  // Auto-create estimate with materials as line items
  try {
    await autoCreateEstimate(
      projectId,
      companyId,
      userId,
      storedMaterials.map((m) => m.id),
      context.projectType
    );
  } catch (err) {
    logger.error({ err, generationId, projectId }, 'Auto-estimate creation failed (non-critical)');
  }
}

/**
 * Default labor hours and hourly rates by project type, used for auto-estimate creation.
 */
const DEFAULT_LABOR_BY_PROJECT_TYPE: Record<string, { hours: number; rate: number }> = {
  KITCHEN:      { hours: 32, rate: 50 },
  BATHROOM:     { hours: 20, rate: 45 },
  FLOORING:     { hours: 12, rate: 40 },
  ROOFING:      { hours: 20, rate: 45 },
  PAINTING:     { hours: 10, rate: 35 },
  SIDING:       { hours: 18, rate: 42 },
  ROOM_REMODEL: { hours: 24, rate: 45 },
  EXTERIOR:     { hours: 16, rate: 40 },
  CUSTOM:       { hours: 18, rate: 42 },
};

/**
 * After materials are generated and stored, automatically create (or update) an estimate
 * with all MaterialSuggestion records as line items plus a default labor line item.
 *
 * If an estimate already exists for this project, its line items are deleted and repopulated
 * so that re-generation updates the estimate rather than creating duplicates.
 */
async function autoCreateEstimate(
  projectId: string,
  companyId: string,
  userId: string,
  materialSuggestionIds: string[],
  projectType: string
) {
  // Fetch the stored material suggestions
  const materials = await prisma.materialSuggestion.findMany({
    where: { id: { in: materialSuggestionIds } },
    orderBy: { sortOrder: 'asc' },
  });

  if (materials.length === 0) {
    logger.warn({ projectId }, 'No materials to create auto-estimate from');
    return;
  }

  // Check if an estimate already exists for this project
  const existingEstimates = await prisma.estimate.findMany({
    where: { projectId, companyId },
    orderBy: { createdAt: 'asc' },
    take: 1,
  });

  let estimateId: string;

  if (existingEstimates.length > 0) {
    // Repopulate: delete existing line items, keep the estimate shell
    estimateId = existingEstimates[0].id;
    await prisma.estimateLineItem.deleteMany({ where: { estimateId } });
    logger.info({ estimateId, projectId }, 'Cleared existing estimate line items for repopulation');
  } else {
    // Create a new estimate via the estimates service
    const estimate = await estimatesService.create(companyId, userId, {
      project_id: projectId,
      title: 'AI-Generated Estimate',
    });
    estimateId = estimate.id;
    logger.info({ estimateId, projectId }, 'Created new auto-estimate');
  }

  // Convert MaterialSuggestions to line items. Gemini labor estimates are
  // stored in the same MaterialSuggestion table with a "Labor - <trade>"
  // category prefix, so we detect those and route them into the 'labor'
  // line-item category (previously they were all routed to 'materials',
  // which inflated the Materials subtotal and caused double-counting when
  // combined with the default-labor line item below).
  let hasGeneratedLabor = false;
  const lineItems: CreateEstimateLineItemInput[] = materials.map((m, index) => {
    const isLabor = typeof m.category === 'string'
      && m.category.trim().toLowerCase().startsWith('labor');
    if (isLabor) {
      hasGeneratedLabor = true;
      return {
        category: 'labor' as const,
        name: m.name,
        quantity: Number(m.quantity),
        unit: m.unit || 'hour',
        unit_cost: Number(m.estimatedCost),
        markup_percent: 0,
        tax_rate: 0,
        sort_order: index,
        source_material_suggestion_id: m.id,
      };
    }
    return {
      category: 'materials' as const,
      name: m.name,
      quantity: Number(m.quantity),
      unit: m.unit,
      unit_cost: Number(m.estimatedCost),
      markup_percent: 0,
      tax_rate: 0.0825,
      sort_order: index,
      source_material_suggestion_id: m.id,
    };
  });

  // Only add a default flat labor line if Gemini did not already provide
  // labor estimates — otherwise the estimate double-counts labor.
  if (!hasGeneratedLabor) {
    const labor = DEFAULT_LABOR_BY_PROJECT_TYPE[projectType] ?? DEFAULT_LABOR_BY_PROJECT_TYPE.CUSTOM;
    lineItems.push({
      category: 'labor' as const,
      name: `${projectType.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase())} Labor`,
      quantity: labor.hours,
      unit: 'hour',
      unit_cost: labor.rate,
      markup_percent: 0,
      tax_rate: 0,
      sort_order: materials.length,
    });
  }

  // Batch create all line items and recalculate totals once
  await estimateLineItemsService.createBatch(estimateId, companyId, lineItems);

  // Update project status to ESTIMATE_CREATED if still in an earlier state
  const project = await prisma.project.findUnique({ where: { id: projectId }, select: { status: true } });
  if (project && ['DRAFT', 'PHOTOS_UPLOADED', 'GENERATING', 'GENERATION_COMPLETE'].includes(project.status)) {
    await prisma.project.update({
      where: { id: projectId },
      data: { status: 'ESTIMATE_CREATED' },
    });
  }

  logger.info(
    { estimateId, projectId, materialCount: materials.length, laborIncluded: true },
    'Auto-estimate created with line items'
  );
}

/**
 * List all AI generations for a project, newest first.
 * Verifies the project belongs to the requesting company.
 */
export async function listByProject(projectId: string, companyId: string) {
  await verifyProjectOwnership(projectId, companyId);

  const generations = await prisma.aIGeneration.findMany({
    where: { projectId },
    orderBy: { createdAt: 'desc' },
  });

  return generations;
}

/**
 * Get a single AI generation by ID.
 * Verifies the generation's project belongs to the requesting company.
 */
export async function getById(generationId: string, companyId: string) {
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
 * Serve the generated image binary for a generation.
 * Returns { data: Buffer, mimeType: string } or null if not available.
 */
export async function getImageData(generationId: string, companyId: string) {
  const generation = await prisma.aIGeneration.findUnique({
    where: { id: generationId },
    include: { project: { select: { companyId: true } } },
  });

  if (!generation || generation.project.companyId !== companyId) {
    throw new NotFoundError('Generation', generationId);
  }

  if (!generation.imageData || !generation.imageMimeType) {
    return null;
  }

  return {
    data: Buffer.from(generation.imageData, 'base64'),
    mimeType: generation.imageMimeType,
  };
}

/**
 * Create a new AI generation for a project.
 *
 * Entitlement model (post-credit-removal):
 * - The shared `gateAIAction` enforces subscription state and rolling-window
 *   usage caps (daily/weekly/monthly) drawn from the user's plan.
 * - On block, gateAIAction throws PaywallError with the variant
 *   (TRIAL_OFFER / SUBSCRIBE_NO_TRIAL / USAGE_LIMIT_<window>) the iOS client
 *   should render.
 * - On allow, we create the generation, log activity, and record a UsageEvent
 *   so the rolling cap reflects this call.
 */
export async function create(
  projectId: string,
  companyId: string,
  userId: string,
  data: CreateGenerationInput
) {
  const project = await verifyProjectOwnership(projectId, companyId);
  const imageContext = buildImageContext(project);
  imageContext.materials = toMaterialSpecs(data.materials);
  const systemPrompt = getSystemPrompt(imageContext);

  // Throws PaywallError on block (admin, trial, or pro within caps → returns).
  await gateAIAction({ userId, companyId, metric: 'AI_GENERATION' });

  const generation = await prisma.$transaction(async (tx) => {
    const gen = await tx.aIGeneration.create({
      data: { projectId, prompt: data.prompt, systemPrompt, status: 'QUEUED' },
    });
    await tx.activityLogEntry.create({
      data: {
        projectId, userId,
        action: 'GENERATION_STARTED',
        description: `AI generation started: ${data.prompt.substring(0, 100)}`,
      },
    });
    return gen;
  });

  // Record usage AFTER successful creation so a failed write doesn't burn cap.
  await recordUsage(userId, companyId, 'AI_GENERATION', {
    projectId,
    generationId: generation.id,
    kind: 'image_preview',
  });

  // Fire-and-forget background image generation.
  processGeneration(generation.id, data.prompt, imageContext, projectId, companyId, userId).catch(() => {});

  return generation;
}

/**
 * Public (no-auth) image data retrieval by generation ID.
 * Used for serving images to AsyncImage / <img> without auth headers.
 * Security: generation IDs are CUIDs (unguessable).
 */
export async function getPublicImageData(generationId: string) {
  const generation = await prisma.aIGeneration.findUnique({
    where: { id: generationId },
    select: { imageData: true, imageMimeType: true },
  });

  if (!generation?.imageData || !generation?.imageMimeType) {
    return null;
  }

  return {
    data: Buffer.from(generation.imageData, 'base64'),
    mimeType: generation.imageMimeType,
  };
}
