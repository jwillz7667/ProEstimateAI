import { prisma } from '../../config/database';
import { NotFoundError, PaywallError } from '../../lib/errors';
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
 */
export async function create(
  projectId: string,
  companyId: string,
  userId: string,
  data: CreateGenerationInput
) {
  await verifyProjectOwnership(projectId, companyId);

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

  return generation;
}
