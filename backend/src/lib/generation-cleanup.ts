import { prisma } from "../config/database";
import { logger } from "../config/logger";

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
 * container that hasn't crashed. Real PiAPI runs complete in 60–130s;
 * Google GenAI fallback adds another 30s. 10 minutes is well past
 * the 99th percentile.
 */
export async function markStuckGenerationsFailed(
  thresholdMs: number = 10 * 60 * 1000,
): Promise<number> {
  const cutoff = new Date(Date.now() - thresholdMs);

  try {
    const result = await prisma.aIGeneration.updateMany({
      where: {
        status: { in: ["QUEUED", "PROCESSING"] },
        createdAt: { lt: cutoff },
      },
      data: {
        status: "FAILED",
        errorMessage:
          "Generation was interrupted before it could finish. Please try again.",
      },
    });

    if (result.count > 0) {
      logger.warn(
        { count: result.count, thresholdMs },
        "marked stuck AI generations as FAILED on startup",
      );
    }

    return result.count;
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
