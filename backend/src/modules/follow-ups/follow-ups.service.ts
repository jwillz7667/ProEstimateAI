import { randomUUID } from "node:crypto";
import { prisma } from "../../config/database";
import { ConflictError, NotFoundError } from "../../lib/errors";
import { isFollowUpDeliveryConfigured } from "./follow-ups.email";
import { assertFollowUpAccess, assertFollowUpManager, loadFollowUpTarget, type FollowUpKind } from "./follow-ups.target";

export async function getSettings(companyId: string, userId?: string) {
  const settings = await prisma.followUpSettings.findUnique({ where: { companyId } });
  const user = userId ? await prisma.user.findFirst({ where: { id: userId, companyId, isActive: true }, select: { role: true } }) : null;
  return {
    enabled: settings?.enabled ?? false, quote_days: settings?.quoteDays ?? 3, invoice_days: settings?.invoiceDays ?? 7,
    enabled_at: settings?.enabledAt?.toISOString() ?? null, delivery_available: isFollowUpDeliveryConfigured(),
    can_manage: Boolean(user && ["OWNER", "ADMIN"].includes(user.role)),
  };
}

export async function updateSettings(companyId: string, userId: string, input: { enabled: boolean; quote_days: number; invoice_days: number }) {
  if (input.enabled && !isFollowUpDeliveryConfigured()) throw new ConflictError("Email delivery is not configured. Reminders remain off.");
  await prisma.$transaction(async (tx) => {
    if (input.enabled) await assertFollowUpAccess(tx, companyId, userId, true);
    else await assertFollowUpManager(tx, companyId, userId);
    await tx.$queryRaw`SELECT id FROM "Company" WHERE id = ${companyId} FOR UPDATE`;
    const existing = await tx.followUpSettings.findUnique({ where: { companyId } });
    const enabledAt = input.enabled ? (existing?.enabled ? existing.enabledAt : new Date()) : existing?.enabledAt;
    await tx.followUpSettings.upsert({
      where: { companyId }, create: { companyId, enabled: input.enabled, quoteDays: input.quote_days, invoiceDays: input.invoice_days, enabledAt, updatedByUserId: userId },
      update: { enabled: input.enabled, quoteDays: input.quote_days, invoiceDays: input.invoice_days, enabledAt, updatedByUserId: userId },
    });
  });
  return getSettings(companyId, userId);
}

export async function listHistory(companyId: string, kind: FollowUpKind, id: string) {
  return prisma.$transaction(async (tx) => {
    const target = await loadFollowUpTarget(tx, kind, id, companyId);
    const messages = await tx.followUpMessage.findMany({ where: { companyId, entityKind: kind, entityId: id }, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: 50 });
    const suppressed = Boolean(await tx.followUpSuppression.findUnique({ where: { companyId_entityKind_entityId: { companyId, entityKind: kind, entityId: id } } }));
    const last = messages.filter((message) => message.acceptedAt).sort((a, b) => b.acceptedAt!.getTime() - a.acceptedAt!.getTime())[0];
    const pending = messages.some((message) => ["QUEUED", "SENDING"].includes(message.status));
    const recent = Boolean(last?.acceptedAt && last.acceptedAt.getTime() > Date.now() - 3_600_000);
    return {
      eligible: target.eligible && Boolean(target.email) && !suppressed && !pending && !recent,
      unavailable_reason: !target.eligible ? target.reason : suppressed ? "The recipient stopped reminders for this document." : !target.email ? "Add a valid client email before following up." : pending ? "A follow-up is already queued or sending." : recent ? "A follow-up was sent within the last hour." : null,
      delivery_available: isFollowUpDeliveryConfigured(), recipient_email: target.email, suppressed,
      last_contact_at: (last?.acceptedAt ?? target.sentAt)?.toISOString() ?? null,
      messages: messages.map(toHistoryDto),
    };
  });
}

export function toHistoryDto(message: { id: string; source: string; status: string; attempts: number; createdAt: Date; acceptedAt: Date | null; deliveredAt: Date | null; lastError: string | null }) {
  return { id: message.id, source: message.source.toLowerCase(), status: message.status.toLowerCase(), attempts: message.attempts, created_at: message.createdAt.toISOString(), accepted_at: message.acceptedAt?.toISOString() ?? null, delivered_at: message.deliveredAt?.toISOString() ?? null, error_message: message.lastError };
}

export async function enqueueManual(companyId: string, userId: string, kind: FollowUpKind, id: string, requestId: string) {
  if (!isFollowUpDeliveryConfigured()) throw new ConflictError("Email delivery is not configured. You can still copy and share the document link.");
  return prisma.$transaction(async (tx) => {
    const key = `manual:${companyId}:${requestId}`;
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${key}, 0))`;
    await assertFollowUpAccess(tx, companyId, userId);
    const target = await loadFollowUpTarget(tx, kind, id, companyId);
    const existing = await tx.followUpMessage.findUnique({ where: { dedupeKey: key } });
    if (existing) {
      if (existing.entityKind !== kind || existing.entityId !== id) throw new ConflictError("This follow-up request was already used for another document.");
      return toHistoryDto(existing);
    }
    if (!target.eligible) throw new ConflictError(target.reason);
    if (!target.email) throw new ConflictError("Add a valid client email before following up.");
    if (await tx.followUpSuppression.findUnique({ where: { companyId_entityKind_entityId: { companyId, entityKind: kind, entityId: id } } })) throw new ConflictError("The recipient stopped reminders for this document.");
    const recent = await tx.followUpMessage.findFirst({ where: {
      companyId, entityKind: kind, entityId: id,
      OR: [{ status: { in: ["QUEUED", "SENDING"] } }, { acceptedAt: { gt: new Date(Date.now() - 3_600_000) } }],
    } });
    if (recent) throw new ConflictError("A follow-up is already pending or was sent within the last hour.");
    const queued = await tx.followUpMessage.create({ data: {
      id: randomUUID(), companyId, projectId: target.projectId, entityKind: kind, entityId: id, source: "MANUAL", dedupeKey: key,
      createdByUserId: userId,
    } });
    return toHistoryDto(queued);
  });
}

export async function getPreference(token: string) {
  const message = await prisma.followUpMessage.findUnique({ where: { unsubscribeToken: token }, select: { companyId: true, entityKind: true, entityId: true } });
  if (!message) throw new NotFoundError("Reminder preferences");
  const suppressed = Boolean(await prisma.followUpSuppression.findUnique({ where: { companyId_entityKind_entityId: message } }));
  return { suppressed };
}

export async function unsubscribe(token: string) {
  return prisma.$transaction(async (tx) => {
    const message = await tx.followUpMessage.findUnique({ where: { unsubscribeToken: token } });
    if (!message) throw new NotFoundError("Reminder preferences");
    const { companyId, projectId, entityKind, entityId } = message;
    await tx.followUpSuppression.upsert({ where: { companyId_entityKind_entityId: { companyId, entityKind, entityId } },
      create: { companyId, projectId, entityKind, entityId }, update: {} });
    await tx.followUpMessage.updateMany({ where: { companyId, entityKind, entityId, status: "QUEUED" }, data: { status: "CANCELLED", lastError: "The recipient stopped reminders for this document." } });
    return { suppressed: true };
  });
}
