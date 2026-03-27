import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { NotFoundError, PaywallError } from '../../lib/errors';
import { generatePreviewImage, getSystemPrompt, ImageGenContext, MaterialSpec } from '../../lib/image-gen';
import { env } from '../../config/env';
import { CreateGenerationInput } from './generations.validators';

/**
 * PaywallDecision payload returned when a free user exhausts AI generation credits.
 */
const GENERATION_LIMIT_PAYWALL = {
  placement: 'GENERATION_LIMIT_HIT',
  trigger_reason: 'Free AI generation credits exhausted',
  blocking: true,
  headline: "You've Used All Free Previews",
  subheadline: 'Upgrade to Pro for unlimited AI-powered remodel previews',
  primary_cta_title: 'Start Free Trial',
  secondary_cta_title: 'View Plans',
  show_continue_free: false,
  show_restore_purchases: true,
  recommended_product_id: 'proestimate.pro.monthly',
  available_products: null, // iOS loads from StoreKit
};

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
async function processGeneration(generationId: string, prompt: string, context: ImageGenContext) {
  try {
    // Mark as PROCESSING
    await prisma.aIGeneration.update({
      where: { id: generationId },
      data: { status: 'PROCESSING' },
    });

    // Check if API key is configured
    if (!env.GOOGLE_AI_API_KEY) {
      logger.warn({ generationId }, 'GOOGLE_AI_API_KEY not configured — marking generation as failed');
      await prisma.aIGeneration.update({
        where: { id: generationId },
        data: {
          status: 'FAILED',
          errorMessage: 'Image generation service is not configured. Contact support.',
        },
      });
      return;
    }

    // Call Nano Banana 2
    const result = await generatePreviewImage(prompt, context);

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
 * Entitlement check flow:
 * 1. Find the user's entitlement and associated plan
 * 2. If plan feature CAN_GENERATE_PREVIEW is true (Pro user) -> proceed
 * 3. If plan feature CAN_GENERATE_PREVIEW is "CREDIT_GATED" -> check UsageBucket
 *    - If remaining > 0 -> atomically consume a credit, create UsageEvent, proceed
 *    - If remaining <= 0 -> throw PaywallError
 * 4. Create the generation with status QUEUED
 * 5. Log activity: GENERATION_STARTED
 * 6. Fire-and-forget: call Nano Banana 2 to generate the image asynchronously
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

  // ── Entitlement check ──────────────────────────────────────────────
  const entitlement = await prisma.userEntitlement.findUnique({
    where: { userId },
    include: { plan: true },
  });

  if (!entitlement) {
    throw new PaywallError(
      'No entitlement found. Please set up your account.',
      GENERATION_LIMIT_PAYWALL
    );
  }

  const features = entitlement.plan.featuresJson as Record<string, unknown>;
  const canGenerate = features.CAN_GENERATE_PREVIEW;

  if (canGenerate !== true) {
    if (canGenerate === 'CREDIT_GATED') {
      // Atomically check and consume a credit inside a transaction
      const generation = await prisma.$transaction(async (tx) => {
        const bucket = await tx.usageBucket.findUnique({
          where: {
            userId_metricCode: {
              userId,
              metricCode: 'AI_GENERATION',
            },
          },
        });

        if (!bucket) {
          throw new PaywallError(
            'No usage bucket found for AI generations.',
            GENERATION_LIMIT_PAYWALL
          );
        }

        const remaining = bucket.includedQuantity - bucket.consumedQuantity;

        if (remaining <= 0) {
          throw new PaywallError(
            'Free AI generation credits exhausted.',
            GENERATION_LIMIT_PAYWALL
          );
        }

        // Atomically increment consumedQuantity
        await tx.usageBucket.update({
          where: { id: bucket.id },
          data: { consumedQuantity: { increment: 1 } },
        });

        // Record the usage event
        await tx.usageEvent.create({
          data: {
            userId,
            companyId,
            metricCode: 'AI_GENERATION',
            quantity: 1,
            metadata: {
              projectId,
              prompt: data.prompt.substring(0, 200),
            },
          },
        });

        // Create the generation with QUEUED status
        const gen = await tx.aIGeneration.create({
          data: {
            projectId,
            prompt: data.prompt,
            systemPrompt,
            status: 'QUEUED',
          },
        });

        // Log activity
        await tx.activityLogEntry.create({
          data: {
            projectId,
            userId,
            action: 'GENERATION_STARTED',
            description: `AI generation started: ${data.prompt.substring(0, 100)}`,
          },
        });

        return gen;
      });

      // Fire-and-forget: process the generation asynchronously
      processGeneration(generation.id, data.prompt, imageContext).catch(() => {});

      return generation;
    }

    // Feature is neither true nor CREDIT_GATED -- block access
    throw new PaywallError(
      'AI generation is not available on your current plan.',
      GENERATION_LIMIT_PAYWALL
    );
  }

  // ── Pro user: unlimited generations ────────────────────────────────
  const generation = await prisma.$transaction(async (tx) => {
    const gen = await tx.aIGeneration.create({
      data: {
        projectId,
        prompt: data.prompt,
        systemPrompt,
        status: 'QUEUED',
      },
    });

    // Log activity
    await tx.activityLogEntry.create({
      data: {
        projectId,
        userId,
        action: 'GENERATION_STARTED',
        description: `AI generation started: ${data.prompt.substring(0, 100)}`,
      },
    });

    return gen;
  });

  // Fire-and-forget: process the generation asynchronously
  processGeneration(generation.id, data.prompt, imageContext).catch(() => {});

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
