import { Prisma } from "@prisma/client";
import { ConflictError, NotFoundError } from "../../lib/errors";

interface RecipientProject {
  clientId: string | null;
  client: { id: string; name: string; email: string | null } | null;
}

export function currentProposalRecipient(project: RecipientProject) {
  return {
    clientId: project.clientId,
    name: project.client?.name ?? null,
    email: project.client?.email?.trim() || null,
  };
}

export function proposalRecipientMatches(proposal: {
  sentRecipientClientId: string | null; sentRecipientEmail: string | null;
  project: RecipientProject;
}) {
  const current = currentProposalRecipient(proposal.project);
  return Boolean(proposal.sentRecipientClientId && proposal.sentRecipientClientId === current.clientId && proposal.sentRecipientEmail === current.email);
}

/** After document locks, freeze the mutable recipient association/contact.
 * NO KEY UPDATE permits FK KEY SHARE when Project updates its clientId, so a
 * project reassignment cannot deadlock against our Client → Project ordering.
 */
export async function lockProposalRecipient(tx: Prisma.TransactionClient, projectId: string, companyId: string) {
  const before = await tx.project.findFirst({ where: { id: projectId, companyId }, select: { clientId: true } });
  if (!before) throw new NotFoundError("Project", projectId);
  if (before.clientId) await tx.$queryRaw`SELECT id FROM "Client" WHERE id = ${before.clientId} FOR NO KEY UPDATE`;
  await tx.$queryRaw`SELECT id FROM "Project" WHERE id = ${projectId} AND "companyId" = ${companyId} FOR NO KEY UPDATE`;
  const after = await tx.project.findFirst({ where: { id: projectId, companyId }, select: { clientId: true } });
  if (!after) throw new NotFoundError("Project", projectId);
  if (after.clientId !== before.clientId) throw new ConflictError("The proposal recipient changed. Refresh and review the destination before sending.");
}
