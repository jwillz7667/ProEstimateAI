import { Prisma } from '@prisma/client';
import { prisma } from '../../config/database';
import { env } from '../../config/env';
import { ConflictError } from '../../lib/errors';

export const ACTIVE_CHECKOUT_STATES = ['PREPARING', 'OPEN', 'PROCESSING'];
export const stripeCredentialsConfigured = () => !!env.STRIPE_API_KEY && !!env.STRIPE_WEBHOOK_SECRET
  && /^[rs]k_(test|live)_/.test(env.STRIPE_API_KEY)
  // Sandbox receipts belong in an isolated development database, never in
  // real customer invoices merely because a test key was deployed by mistake.
  && (env.NODE_ENV !== 'production' || /^[rs]k_live_/.test(env.STRIPE_API_KEY));
export const checkoutConfigured = () => env.STRIPE_PAYMENTS_ENABLED && stripeCredentialsConfigured();

/** Call while holding the Invoice row lock before any balance/status change. */
export async function assertNoActiveCheckout(tx: Prisma.TransactionClient, invoiceId: string) {
  const active = await tx.invoiceCheckoutAttempt.findFirst({ where: { invoiceId, state: { in: ACTIVE_CHECKOUT_STATES } }, select: { id: true } });
  if (active) throw new ConflictError('An online payment is open or processing. Cancel or reconcile checkout before changing this invoice or recording another payment.');
}

export async function invoiceCheckoutInfo(invoiceId: string, companyId: string) {
  const [invoice, merchant, active] = await Promise.all([
    prisma.invoice.findFirst({ where: { id: invoiceId, companyId }, select: { status: true, amountDue: true, paymentReviewRequired: true } }),
    prisma.stripeMerchant.findUnique({ where: { companyId }, select: { accountId: true } }),
    prisma.invoiceCheckoutAttempt.findFirst({ where: { invoiceId, companyId, state: { in: ACTIVE_CHECKOUT_STATES } }, orderBy: { createdAt: 'desc' } }),
  ]);
  return {
    configured: checkoutConfigured(), account_connected: !!merchant?.accountId,
    active_attempt: active ? { id: active.id, state: active.state.toLowerCase(), amount: Number(active.amount), currency_code: active.currencyCode,
      created_at: active.createdAt.toISOString() } : null,
    requires_refund_review: invoice?.paymentReviewRequired ?? false,
    can_record_manual_payment: !!invoice && invoice.status !== 'DRAFT' && invoice.status !== 'VOID' && invoice.amountDue.gt(0) && !invoice.paymentReviewRequired && !active,
  };
}
