import { Prisma } from "@prisma/client";

/** Financial operations take a shared gate before contract/invoice locks.
 * Erasure takes it exclusively so no new checkout can slip between the final
 * active-attempt check and deletion of its reconciliation records.
 */
export async function lockCompanyPaymentAccess(tx: Prisma.TransactionClient, companyId: string) {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock_shared(hashtextextended(${`company-payment-erasure:${companyId}`}, 0))`;
}

export async function lockCompanyPaymentErasure(tx: Prisma.TransactionClient, companyId: string) {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`company-payment-erasure:${companyId}`}, 0))`;
}
