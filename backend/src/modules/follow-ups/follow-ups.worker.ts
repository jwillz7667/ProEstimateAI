import { randomUUID } from "node:crypto";
import { Prisma, type FollowUpMessage } from "@prisma/client";
import { prisma } from "../../config/database";
import { logger } from "../../config/logger";
import { assertFollowUpAccess, loadFollowUpTarget, type FollowUpKind, type FollowUpTarget } from "./follow-ups.target";
import { buildFollowUpEmail, FollowUpDeliveryError, isFollowUpDeliveryConfigured, sendFollowUpEmail, type FollowUpEmailPayload } from "./follow-ups.email";

const MAX_ATTEMPTS = 6;
const RETRY_WINDOW_MS = 22 * 3_600_000; // Remains inside Resend's 24-hour idempotency window.
const LEASE_MS = 60_000;
const DAY_MS = 86_400_000;

type Sender = (payload: FollowUpEmailPayload, idempotencyKey: string) => Promise<string>;

// Prisma's DateTime columns are UTC timestamp-without-time-zone. Raw SQL Date
// binds are timestamptz, so convert explicitly instead of depending on the
// database session's TimeZone (which can be America/Chicago, not UTC).
const utcTimestamp = (date: Date) => Prisma.sql`(${date}::timestamptz AT TIME ZONE 'UTC')`;

export async function enqueueDueReminders(now = new Date(), companyLimit = 50) {
  if (!isFollowUpDeliveryConfigured()) return 0;
  const settings = await prisma.followUpSettings.findMany({
    where: { enabled: true, enabledAt: { not: null } },
    orderBy: [{ lastCheckedAt: { sort: "asc", nulls: "first" } }, { companyId: "asc" }], take: companyLimit,
  });
  let queued = 0;
  for (const config of settings) {
    await prisma.$transaction(async (tx) => {
      try { await assertFollowUpAccess(tx, config.companyId, config.updatedByUserId, true); }
      catch { await tx.followUpSettings.update({ where: { companyId: config.companyId }, data: { lastCheckedAt: now } }); return; }
      const quotes = await tx.$queryRaw<Array<{ id: string; projectId: string }>>`
        SELECT p.id, p."projectId" FROM "Proposal" p
        WHERE p."companyId" = ${config.companyId} AND p.status IN ('SENT','VIEWED')
          AND p."sentAt" >= ${utcTimestamp(config.enabledAt!)} AND p."sentAt" <= ${utcTimestamp(new Date(now.getTime() - config.quoteDays * DAY_MS))}
          AND p."respondedAt" IS NULL AND p."changesRequestedAt" IS NULL
          AND (p."expiresAt" IS NULL OR p."expiresAt" > ${utcTimestamp(now)})
          AND NOT EXISTS (SELECT 1 FROM "FollowUpMessage" m WHERE m."companyId" = p."companyId" AND m."entityKind" = 'proposal' AND m."entityId" = p.id AND m.source = 'AUTOMATIC')
          AND NOT EXISTS (SELECT 1 FROM "FollowUpSuppression" s WHERE s."companyId" = p."companyId" AND s."entityKind" = 'proposal' AND s."entityId" = p.id)
        ORDER BY p."sentAt", p.id LIMIT 25
      `;
      const bills = await tx.$queryRaw<Array<{ id: string; projectId: string }>>`
        SELECT i.id, i."projectId" FROM "Invoice" i
        WHERE i."companyId" = ${config.companyId} AND i.status NOT IN ('DRAFT','PAID','VOID') AND i."amountDue" > 0
          AND i."sentAt" >= ${utcTimestamp(config.enabledAt!)} AND i."dueDate" <= ${utcTimestamp(new Date(now.getTime() - config.invoiceDays * DAY_MS))}
          AND NOT EXISTS (SELECT 1 FROM "FollowUpMessage" m WHERE m."companyId" = i."companyId" AND m."entityKind" = 'invoice' AND m."entityId" = i.id AND m.source = 'AUTOMATIC')
          AND NOT EXISTS (SELECT 1 FROM "FollowUpSuppression" s WHERE s."companyId" = i."companyId" AND s."entityKind" = 'invoice' AND s."entityId" = i.id)
        ORDER BY i."dueDate", i.id LIMIT 25
      `;
      for (const [kind, records] of [["proposal", quotes], ["invoice", bills]] as const) {
        for (const record of records) {
          const result = await tx.followUpMessage.createMany({ data: [{
            companyId: config.companyId, projectId: record.projectId, entityKind: kind, entityId: record.id,
            source: "AUTOMATIC", dedupeKey: `auto:${config.companyId}:${kind}:${record.id}`, createdByUserId: config.updatedByUserId,
          }], skipDuplicates: true });
          queued += result.count;
        }
      }
      await tx.followUpSettings.update({ where: { companyId: config.companyId }, data: { lastCheckedAt: now } });
    });
  }
  return queued;
}

async function claim(now: Date) {
  return prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "FollowUpMessage"
      WHERE (status = 'QUEUED' AND "runAt" <= ${utcTimestamp(now)}) OR (status = 'SENDING' AND "claimedUntil" <= ${utcTimestamp(now)})
      ORDER BY "runAt", id FOR UPDATE SKIP LOCKED LIMIT 1
    `;
    if (!rows.length) return null;
    return tx.followUpMessage.update({ where: { id: rows[0].id }, data: {
      status: "SENDING", attempts: { increment: 1 }, attemptToken: randomUUID(), claimedUntil: new Date(now.getTime() + LEASE_MS),
    } });
  });
}

async function stopReason(tx: Prisma.TransactionClient, message: FollowUpMessage, target: FollowUpTarget, now: Date) {
  if (!target.eligible) return target.reason;
  if (!target.email) return "The client no longer has a valid email address.";
  if (message.recipientEmail && message.recipientEmail !== target.email) return "The document's recipient changed after this message was prepared.";
  try { await assertFollowUpAccess(tx, message.companyId, message.createdByUserId); }
  catch { return "The account no longer has permission to send follow-ups."; }
  if (await tx.followUpSuppression.findUnique({ where: { companyId_entityKind_entityId: { companyId: message.companyId, entityKind: message.entityKind, entityId: message.entityId } } })) return "The recipient stopped reminders for this document.";
  if (message.source === "AUTOMATIC") {
    const config = await tx.followUpSettings.findUnique({ where: { companyId: message.companyId } });
    if (!config?.enabled || !config.enabledAt || !target.sentAt || target.sentAt < config.enabledAt) return "Automatic reminders are off or this document predates the current opt-in.";
    const basis = target.kind === "proposal" ? target.sentAt : target.dueAt;
    const days = target.kind === "proposal" ? config.quoteDays : config.invoiceDays;
    if (!basis || basis.getTime() + days * DAY_MS > now.getTime()) return "The document is no longer due for an automatic reminder.";
  }
  return null;
}

async function ownMessage(tx: Prisma.TransactionClient, job: FollowUpMessage) {
  const rows = await tx.$queryRaw<Array<{ id: string }>>`SELECT id FROM "FollowUpMessage" WHERE id = ${job.id} AND "attemptToken" = ${job.attemptToken} AND status = 'SENDING' FOR UPDATE`;
  return rows.length ? tx.followUpMessage.findUniqueOrThrow({ where: { id: job.id } }) : null;
}

async function cancel(tx: Prisma.TransactionClient, id: string, reason: string) {
  await tx.followUpMessage.update({ where: { id }, data: { status: "CANCELLED", lastError: reason, claimedUntil: null, attemptToken: null } });
}

/** A stable payload is committed before contacting the provider, surviving a lost response. */
async function prepare(job: FollowUpMessage, now: Date) {
  return prisma.$transaction(async (tx) => {
    const target = await loadFollowUpTarget(tx, job.entityKind as FollowUpKind, job.entityId, job.companyId, now);
    const current = await ownMessage(tx, job);
    if (!current) return false;
    const stopped = await stopReason(tx, current, target, now);
    if (stopped) { await cancel(tx, current.id, stopped); return false; }
    if (current.attempts > MAX_ATTEMPTS || (current.firstAttemptAt && now.getTime() - current.firstAttemptAt.getTime() >= RETRY_WINDOW_MS)) {
      await tx.followUpMessage.update({ where: { id: current.id }, data: { status: "FAILED", lastError: "The delivery retry window ended. Check the document history before sending another follow-up.", claimedUntil: null, attemptToken: null } });
      return false;
    }
    if (!current.payloadJson) {
      const payload = buildFollowUpEmail(target, current.unsubscribeToken);
      await tx.followUpMessage.update({ where: { id: current.id }, data: {
        payloadJson: payload as unknown as Prisma.InputJsonValue, recipientEmail: target.email, firstAttemptAt: now,
      } });
    }
    return true;
  });
}

async function deliver(job: FollowUpMessage, sender: Sender, now: Date) {
  // The business-document lock serializes the final eligibility check and send
  // against approvals/payments. A response committed first always stops delivery.
  await prisma.$transaction(async (tx) => {
    const target = await loadFollowUpTarget(tx, job.entityKind as FollowUpKind, job.entityId, job.companyId, now);
    const current = await ownMessage(tx, job);
    if (!current) return;
    const stopped = await stopReason(tx, current, target, now);
    if (stopped) { await cancel(tx, current.id, stopped); return; }
    try {
      const providerId = await sender(current.payloadJson as unknown as FollowUpEmailPayload, `follow-up/${current.id}`);
      await tx.followUpMessage.update({ where: { id: current.id }, data: {
        status: "SENT", providerMessageId: providerId, acceptedAt: new Date(), lastError: null, claimedUntil: null, attemptToken: null,
      } });
    } catch (error) {
      const retryable = !(error instanceof FollowUpDeliveryError) || error.retryable;
      const retry = retryable && current.attempts < MAX_ATTEMPTS && current.firstAttemptAt && now.getTime() - current.firstAttemptAt.getTime() < RETRY_WINDOW_MS;
      const delay = Math.min(60_000 * 2 ** (current.attempts - 1), 30 * 60_000);
      await tx.followUpMessage.update({ where: { id: current.id }, data: {
        status: retry ? "QUEUED" : "FAILED", runAt: new Date(now.getTime() + delay), claimedUntil: null, attemptToken: null,
        lastError: error instanceof FollowUpDeliveryError ? error.message : "The email provider response could not be confirmed.",
      } });
    }
  }, { timeout: 20_000, maxWait: 5_000 });
}

export async function processFollowUpQueue(options: { now?: Date; limit?: number; send?: Sender } = {}) {
  const now = options.now ?? new Date();
  const limit = Math.min(Math.max(options.limit ?? 20, 1), 100);
  let processed = 0;
  for (; processed < limit; processed++) {
    const job = await claim(now);
    if (!job) break;
    if (job.attempts > MAX_ATTEMPTS || (job.firstAttemptAt && now.getTime() - job.firstAttemptAt.getTime() >= RETRY_WINDOW_MS)) {
      await prisma.followUpMessage.updateMany({ where: { id: job.id, attemptToken: job.attemptToken }, data: { status: "FAILED", lastError: "The safe delivery retry limit ended. Check the history before sending another follow-up.", claimedUntil: null, attemptToken: null } });
      continue;
    }
    try { if (await prepare(job, now)) await deliver(job, options.send ?? sendFollowUpEmail, now); }
    catch (error) {
      // A deleted document cannot receive follow-ups. Other database errors
      // retain the lease; a later worker retries with the same provider key.
      if (error && typeof error === "object" && "statusCode" in error && error.statusCode === 404) {
        await prisma.followUpMessage.updateMany({ where: { id: job.id, attemptToken: job.attemptToken }, data: { status: "CANCELLED", lastError: "The document is no longer available.", claimedUntil: null, attemptToken: null } });
      } else { logger.error({ followUpId: job.id }, "Follow-up queue processing failed; lease retained for safe retry"); }
    }
  }
  return processed;
}

export function startFollowUpWorker() {
  let active: Promise<unknown> | null = null;
  const tick = () => {
    if (active || !isFollowUpDeliveryConfigured()) return;
    active = (async () => { await enqueueDueReminders(); await processFollowUpQueue(); })()
      .catch(() => logger.error("Follow-up worker failed"))
      .finally(() => { active = null; });
  };
  const interval = setInterval(tick, 60_000);
  interval.unref();
  // No immediate send on deployment; only future ticks with explicit opt-in
  // or a manual request can put an eligible message through the queue.
  return { stop() { clearInterval(interval); }, async drain() { await active; } };
}
