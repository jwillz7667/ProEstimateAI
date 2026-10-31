import { Prisma } from "@prisma/client";
import { prisma } from "../config/database";
import { logger } from "../config/logger";
import { failGenerationAndRefund, hasTextOnlyGenerationIntent } from './generation-usage';

/**
 * Mark any AIGeneration that's been stuck in `QUEUED` / `PROCESSING`
 * for longer than `thresholdMs` as `FAILED` so clients polling the
 * record receive a definite terminal answer instead of polling
 * forever.
 *
 * Why this exists. `processGeneration` in
 * `modules/generations/generations.service.ts` is fire-and-forget —
 * it executes on the same Node process that handled the request and
 * has no durable queue behind it. When Railway redeploys (or the
 * container OOM-kills, or the process crashes), every PROCESSING
 * record on that container is orphaned: server-side work has stopped
 * but the row still says "PROCESSING". The iOS client polls these
 * for a generous window and then gives up silently, but the row
 * stays inconsistent forever.
 *
 * Running this on boot — before we start accepting traffic — gives
 * us a clean slate: every truly stuck record gets a deterministic
 * FAILED status with a user-readable error, and the next client
 * touch (poll, list, detail load) reconciles the UI to a clean
 * "generation failed, please retry" state.
 *
 * The threshold is generous (default 10 min) so we don't accidentally
 * fail a legitimately long-running generation on a different
 * container that hasn't crashed. Google GenAI is tried first, followed by
 * up to two PiAPI tasks with two-minute polling limits. Ten minutes leaves
 * additional headroom for provider latency and image downloads.
 */
export async function markStuckGenerationsFailed(
  thresholdMs: number = 10 * 60 * 1000,
  dryRun: boolean = false,
): Promise<number> {
  const cutoff = new Date(Date.now() - thresholdMs);
  const where: Prisma.AIGenerationWhereInput = {
    status: { in: ["QUEUED", "PROCESSING"] },
    createdAt: { lt: cutoff },
  };

  try {
    if (dryRun) {
      const count = await prisma.aIGeneration.count({ where });
      if (count > 0) {
        logger.warn(
          { count, thresholdMs, dryRun: true },
          "[dry-run] would mark stuck AI generations as FAILED",
        );
      }
      return count;
    }

    const candidates = await prisma.aIGeneration.findMany({ where, select: { id: true } });
    let changed = 0;
    for (const candidate of candidates) {
      try {
        if (await failGenerationAndRefund(candidate.id,
          'Generation was interrupted before it could finish. Please try again.', { staleBefore: cutoff })) changed++;
      } catch (err) {
        logger.error({ err, generationId: candidate.id }, 'Stuck generation refund failed; leaving it for retry');
      }
    }

    if (changed > 0) {
      logger.warn(
        { count: changed, thresholdMs },
        "marked stuck AI generations as FAILED",
      );
    }

    return changed;
  } catch (err) {
    // Don't let a cleanup failure block boot — the server can still
    // accept traffic; the next sweep on next deploy will pick up
    // anything that didn't get patched here.
    logger.error(
      { err },
      "generation-cleanup sweep failed; continuing startup without it",
    );
    return 0;
  }
}

/**
 * Mark generations that report `COMPLETED` but carry no image bytes as
 * `FAILED`, so the iOS client stops treating them as ready and 404-ing on
 * the preview endpoint.
 *
 * Why this exists. A handful of production rows predate the DTO/preview
 * fixes: `status = COMPLETED` while `imageData IS NULL`. The client polls
 * them, sees "completed", then requests `GET /v1/generations/:id/preview`
 * which has nothing to serve. They never self-heal because the generation
 * pipeline already considers them done. Flipping them to FAILED reconciles
 * the UI to a retryable state.
 *
 * The threshold (default 1 hour) protects an in-flight generation that has
 * legitimately flipped to COMPLETED a split second before its bytes were
 * written in the same transaction window — only rows old enough that no
 * write is still racing are eligible.
 *
 * ⚠️ Cross-cutting with REC8 (object storage). Once image bytes can live in
 * Cloudflare R2 instead of Postgres, `imageData IS NULL` will be the NORMAL
 * state for healthy generations. When `imageStorageKey` is introduced this
 * predicate MUST become `imageData IS NULL AND imageStorageKey IS NULL`,
 * otherwise it would fail generations whose bytes are safely in object
 * storage. Do not ship R2 without updating this filter.
 */
export async function markImagelessCompletedGenerationsFailed(
  thresholdMs: number = 60 * 60 * 1000,
  dryRun: boolean = false,
): Promise<number> {
  const cutoff = new Date(Date.now() - thresholdMs);
  const where: Prisma.AIGenerationWhereInput = {
    status: "COMPLETED",
    imageData: null,
    createdAt: { lt: cutoff },
  };

  try {
    const candidates = await prisma.aIGeneration.findMany({ where, select: { id: true, projectId: true } });
    const imageCandidates: Array<{ id: string }> = [];
    for (const candidate of candidates) {
      if (!await hasTextOnlyGenerationIntent(prisma, candidate.id, candidate.projectId)) imageCandidates.push(candidate);
    }
    if (dryRun) {
      const count = imageCandidates.length;
      if (count > 0) {
        logger.warn(
          { count, thresholdMs, dryRun: true },
          "[dry-run] would mark imageless COMPLETED generations as FAILED",
        );
      }
      return count;
    }

    let changed = 0;
    for (const candidate of imageCandidates) {
      try {
        if (await failGenerationAndRefund(candidate.id,
          'Preview image was not saved. Please generate again.', { staleBefore: cutoff, allowImagelessCompleted: true })) changed++;
      } catch (err) {
        logger.error({ err, generationId: candidate.id }, 'Imageless generation refund failed; leaving it for retry');
      }
    }

    if (changed > 0) {
      logger.warn(
        { count: changed, thresholdMs },
        "marked imageless COMPLETED AI generations as FAILED",
      );
    }

    return changed;
  } catch (err) {
    logger.error(
      { err },
      "imageless-generation sweep failed; continuing without it",
    );
    return 0;
  }
}
