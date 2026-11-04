import { Prisma } from "@prisma/client";
import { z } from "zod";
import { env } from "../../config/env";
import { AuthorizationError, NotFoundError } from "../../lib/errors";
import { hasEffectiveProAccess } from "../../lib/entitlement-access";
import { readProposalSnapshot } from "../proposals/proposal-document-snapshot";
import { lockProposalRecipient, proposalRecipientMatches } from "../proposals/proposal-recipient";
import { lockChangeOrderProposal } from "../change-orders/change-order-proposal";

export type FollowUpKind = "proposal" | "invoice";
export interface FollowUpTarget {
  companyId: string; projectId: string; kind: FollowUpKind; id: string;
  eligible: boolean; reason: string; sentAt: Date | null; dueAt: Date | null;
  email: string | null; companyName: string; replyTo: string | null;
  title: string; url: string; amountDue: string | null;
}

export async function assertFollowUpManager(tx: Prisma.TransactionClient, companyId: string, userId: string) {
  const user = await tx.user.findFirst({ where: { id: userId, companyId, isActive: true }, select: { role: true } });
  if (!user || !["OWNER", "ADMIN"].includes(user.role)) throw new AuthorizationError("Only an owner or administrator can change automatic reminders.");
}

export async function assertFollowUpAccess(tx: Prisma.TransactionClient, companyId: string, userId: string | null, manager = false) {
  const user = userId ? await tx.user.findFirst({
    where: { id: userId, companyId, isActive: true }, include: { entitlement: { include: { plan: true } } },
  }) : null;
  if (!user || !user.entitlement || user.entitlement.companyId !== companyId || !hasEffectiveProAccess(user.entitlement)) throw new AuthorizationError("An active Pro account is required to send follow-ups.");
  if (user.role === "VIEWER") throw new AuthorizationError("View-only accounts cannot send follow-ups.");
  if (manager && !["OWNER", "ADMIN"].includes(user.role)) throw new AuthorizationError("Only an owner or administrator can change automatic reminders.");
  const features = user.entitlement.plan.featuresJson as Record<string, unknown>;
  if (features.CAN_SHARE_APPROVAL_LINK !== true && features.CAN_CREATE_INVOICE !== true) throw new AuthorizationError("Follow-ups are not available for this plan.");
}

function validEmail(value: string | null): string | null {
  return value && z.email().safeParse(value.trim()).success ? value.trim().toLowerCase() : null;
}

/** Lock the business document before queue rows, matching its mutation paths. */
export async function loadFollowUpTarget(tx: Prisma.TransactionClient, kind: FollowUpKind, id: string, companyId: string, now = new Date()): Promise<FollowUpTarget> {
  if (kind === "proposal") {
    const found = await tx.proposal.findFirst({ where: { id, companyId }, select: { estimateId: true } });
    if (!found) throw new NotFoundError("Proposal", id);
    await lockChangeOrderProposal(tx, id, companyId);
    const estimate = await tx.estimate.findUniqueOrThrow({ where: { id: found.estimateId }, select: { revisesEstimateId: true } });
    const ids = [found.estimateId, ...(estimate.revisesEstimateId ? [estimate.revisesEstimateId] : [])];
    await tx.$queryRaw(Prisma.sql`SELECT id FROM "Estimate" WHERE id IN (${Prisma.join(ids)}) ORDER BY id FOR UPDATE`);
    await tx.$queryRaw`SELECT id FROM "Proposal" WHERE id = ${id} FOR UPDATE`;
    const recipientProject = await tx.proposal.findUniqueOrThrow({ where: { id }, select: { projectId: true } });
    await lockProposalRecipient(tx, recipientProject.projectId, companyId);
    const proposal = await tx.proposal.findFirst({ where: { id, companyId }, include: { project: { include: { client: true } }, company: true } });
    if (!proposal) throw new NotFoundError("Proposal", id);
    const snapshot = proposal.sentSnapshot ? readProposalSnapshot(proposal.sentSnapshot) : null;
    const recipientMatches = proposalRecipientMatches(proposal);
    const eligible = Boolean(recipientMatches && snapshot && proposal.shareToken && proposal.sentAt && ["SENT", "VIEWED"].includes(proposal.status) && !proposal.respondedAt && !proposal.changesRequestedAt && (!proposal.expiresAt || proposal.expiresAt > now));
    return {
      companyId, projectId: proposal.projectId, kind, id, eligible,
      reason: recipientMatches ? "This proposal has not been sent, has a response or change request, or has expired." : "The original recipient is unknown or has changed. Create and send a reviewed revision before emailing again.",
      sentAt: proposal.sentAt, dueAt: null, email: validEmail(proposal.sentRecipientEmail),
      companyName: snapshot?.content.company.name ?? proposal.company.name, replyTo: validEmail(proposal.company.email),
      title: snapshot?.content.project.title ?? proposal.project.title,
      url: `${env.PUBLIC_PROPOSAL_BASE_URL.replace(/\/$/, "")}/${encodeURIComponent(proposal.shareToken ?? "")}`,
      amountDue: null,
    };
  }
  const rows = await tx.$queryRaw<Array<{ id: string }>>`SELECT id FROM "Invoice" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE`;
  if (!rows.length) throw new NotFoundError("Invoice", id);
  const invoice = await tx.invoice.findFirstOrThrow({ where: { id, companyId }, include: { company: true, client: true, project: true } });
  return {
    companyId, projectId: invoice.projectId, kind, id,
    eligible: Boolean(invoice.sentAt && !["DRAFT", "PAID", "VOID"].includes(invoice.status) && invoice.amountDue.greaterThan(0)),
    reason: "This invoice has not been sent, has no outstanding balance or is void.",
    sentAt: invoice.sentAt, dueAt: invoice.dueDate, email: validEmail(invoice.client.email),
    companyName: invoice.company.name, replyTo: validEmail(invoice.company.email),
    title: `${invoice.invoiceNumber} · ${invoice.project.title}`,
    url: `${env.PUBLIC_WEB_BASE_URL.replace(/\/$/, "")}/invoice/${encodeURIComponent(invoice.shareToken)}`,
    amountDue: invoice.amountDue.toFixed(2),
  };
}
