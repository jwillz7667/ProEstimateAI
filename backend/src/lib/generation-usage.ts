import { Prisma } from '@prisma/client';
import { prisma } from '../config/database';
import { invalidateCache, CacheKeys } from '../config/redis';
import { ConflictError } from './errors';
import { STARTER_CREDITS_SOURCE } from './limits';
import type { UsageReservation } from '../modules/commerce/entitlement-gate';

function objectMetadata(metadata: Prisma.JsonValue): Prisma.JsonObject {
  if (metadata && typeof metadata === 'object' && !Array.isArray(metadata)) return metadata;
  return metadata === null ? {} : { previous_metadata: metadata };
}

/** Called in the transaction that reserves capacity and inserts the generation. */
export async function linkGenerationReservation(
  transaction: Prisma.TransactionClient,
  reservation: UsageReservation | undefined,
  generationId: string,
  projectId: string,
  companyId: string,
  previewRequired: boolean,
): Promise<void> {
  if (!reservation) return;
  const event = await transaction.usageEvent.findUnique({ where: { id: reservation.eventId } });
  if (!event || event.userId !== reservation.userId || event.companyId !== companyId ||
    event.metricCode !== 'AI_GENERATION' || event.quantity !== 1) {
    throw new ConflictError('Generation usage reservation is unavailable');
  }
  const metadata = objectMetadata(event.metadata);
  if (metadata.generation_reservation !== undefined) {
    throw new ConflictError('Generation usage reservation is already linked');
  }
  await transaction.usageEvent.update({
    where: { id: event.id },
    data: { metadata: {
      ...metadata,
      generation_reservation: {
        version: 1, event_id: event.id, generation_id: generationId,
        project_id: projectId, user_id: event.userId, preview_required: previewRequired,
      },
    } },
  });
}

export async function hasTextOnlyGenerationIntent(
  transaction: Prisma.TransactionClient,
  generationId: string,
  projectId: string,
): Promise<boolean> {
  return Boolean(await transaction.activityLogEntry.findFirst({
    where: {
      projectId, action: 'GENERATION_STARTED',
      AND: [
        { metadataJson: { path: ['generation_id'], equals: generationId } },
        { metadataJson: { path: ['preview_required'], equals: false } },
      ],
    },
    select: { id: true },
  }));
}

interface FailureOptions {
  staleBefore?: Date;
  allowImagelessCompleted?: boolean;
}

/**
 * Failure and its exact refund commit together. Locking the generation also
 * arbitrates against a late provider completion. Legacy unlinked rows receive
 * a failure status only; user/time proximity is never used to infer credits.
 */
export async function failGenerationAndRefund(
  generationId: string,
  message: string,
  options: FailureOptions = {},
): Promise<boolean> {
  const result = await prisma.$transaction(async (transaction) => {
    await transaction.$queryRaw`SELECT id FROM "AIGeneration" WHERE id = ${generationId} FOR UPDATE`;
    const generation = await transaction.aIGeneration.findUnique({
      where: { id: generationId },
      select: { id: true, projectId: true, status: true, imageData: true, createdAt: true,
        project: { select: { companyId: true } } },
    });
    if (!generation || generation.imageData ||
      (options.staleBefore && generation.createdAt >= options.staleBefore)) return { changed: false };
    if (generation.status === 'COMPLETED' &&
      (!options.allowImagelessCompleted || await hasTextOnlyGenerationIntent(transaction, generationId, generation.projectId))) {
      return { changed: false };
    }

    const changed = generation.status !== 'FAILED';
    if (changed) await transaction.aIGeneration.update({
      where: { id: generationId }, data: { status: 'FAILED', errorMessage: message },
    });
    const events = await transaction.usageEvent.findMany({
      where: {
        metricCode: 'AI_GENERATION', companyId: generation.project.companyId,
        metadata: { path: ['generation_reservation', 'generation_id'], equals: generationId },
      },
    });
    const linked = events.filter((event) => {
      const metadata = objectMetadata(event.metadata);
      const link = metadata.generation_reservation;
      return link && typeof link === 'object' && !Array.isArray(link) &&
        link.version === 1 && link.event_id === event.id && link.user_id === event.userId &&
        link.project_id === generation.projectId;
    });
    if (linked.length > 1) throw new ConflictError('Generation has ambiguous usage reservations');
    const event = linked[0];
    if (!event || event.quantity === 0) return { changed };
    if (event.quantity !== 1) throw new ConflictError('Generation usage reservation has an invalid quantity');
    const metadata = objectMetadata(event.metadata);
    const refunded = await transaction.usageEvent.updateMany({
      where: { id: event.id, quantity: 1 },
      data: { quantity: 0, metadata: {
        ...metadata, generation_refund: { at: new Date().toISOString(), reason: message },
      } },
    });
    if (refunded.count === 1 && metadata.source === STARTER_CREDITS_SOURCE) {
      if (typeof metadata.bucket_id !== 'string') throw new ConflictError('Generation starter bucket linkage is missing');
      const bucket = await transaction.usageBucket.updateMany({
        where: { id: metadata.bucket_id, userId: event.userId, companyId: event.companyId,
          metricCode: 'AI_GENERATION', source: STARTER_CREDITS_SOURCE, consumedQuantity: { gt: 0 } },
        data: { consumedQuantity: { decrement: 1 } },
      });
      if (bucket.count !== 1) throw new ConflictError('Generation starter bucket could not be refunded');
    }
    return { changed, userId: refunded.count === 1 ? event.userId : undefined };
  });
  if (result.userId) await invalidateCache(CacheKeys.entitlement(result.userId));
  return result.changed;
}
