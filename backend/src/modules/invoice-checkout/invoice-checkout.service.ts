import { randomBytes } from 'node:crypto';
import { InvoiceCheckoutAttempt, Prisma } from '@prisma/client';
import Stripe from 'stripe';
import { prisma } from '../../config/database';
import { env } from '../../config/env';
import { AppError, AuthorizationError, ConflictError, NotFoundError, ValidationError } from '../../lib/errors';
import { ACTIVE_CHECKOUT_STATES, checkoutConfigured, invoiceCheckoutInfo } from './invoice-checkout.policy';
import { configuredGateway, GatewayRefund, GatewaySession, InvoicePaymentGateway } from './stripe-gateway';

const SUPPORTED_CURRENCIES = new Set(['USD', 'CAD', 'EUR', 'GBP', 'AUD', 'NZD', 'MXN']);
const MINIMUM_MINOR: Record<string, number> = { USD: 50, CAD: 50, EUR: 50, GBP: 30, AUD: 50, NZD: 50, MXN: 1000 };
export async function requirePaymentAdministrator(companyId: string, userId: string) {
  const user = await prisma.user.findFirst({ where: { id: userId, companyId, isActive: true }, select: { role: true } });
  if (!user || !['OWNER', 'ADMIN'].includes(user.role)) throw new AuthorizationError('Only a company owner or administrator can manage online payment setup.');
}
async function lockInvoice(tx: Prisma.TransactionClient, id: string, companyId: string) {
  const rows = await tx.$queryRaw<Array<{ id: string }>>`SELECT id FROM "Invoice" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE`;
  if (!rows.length) throw new NotFoundError('Invoice', id);
  return tx.invoice.findUniqueOrThrow({ where: { id } });
}
function minorAmount(amount: Prisma.Decimal) {
  const minor = amount.times(100);
  if (minor.lte(0) || !minor.isInteger() || minor.gt(Number.MAX_SAFE_INTEGER)) throw new ValidationError('This payment amount is outside the supported range.');
  return Number(minor);
}
function validateSession(attempt: InvoiceCheckoutAttempt, session: GatewaySession, accountId: string, liveMode: boolean) {
  if (accountId !== attempt.accountId || session.liveMode !== liveMode || session.attemptId !== attempt.id || session.invoiceId !== attempt.invoiceId
    || (attempt.sessionId && attempt.sessionId !== session.id) || session.amount !== minorAmount(attempt.amount)
    || session.currency?.toUpperCase() !== attempt.currencyCode.toUpperCase()
    || (attempt.paymentIntentId && session.paymentIntentId && attempt.paymentIntentId !== session.paymentIntentId)) {
    throw new ConflictError('The payment session does not match the saved invoice, amount, currency or merchant.');
  }
}

export async function merchantStatus(companyId: string, userId: string, gateway?: InvoicePaymentGateway) {
  await requirePaymentAdministrator(companyId, userId);
  const merchant = await prisma.stripeMerchant.findUnique({ where: { companyId } });
  if (!gateway && !checkoutConfigured()) return { configured: false, connected: !!merchant?.accountId, ready: false, country: merchant?.country ?? null, mode: null, dashboard_url: null };
  gateway ??= configuredGateway();
  return { configured: true, connected: !!merchant?.accountId,
    country: merchant?.country ?? null,
    ready: !!merchant?.accountId && await gateway.merchantReady(merchant.accountId),
    mode: gateway.liveMode ? 'live' : 'sandbox', dashboard_url: merchant?.accountId ? 'https://dashboard.stripe.com/' : null };
}

export async function startMerchantOnboarding(companyId: string, userId: string, country: string, gateway = configuredGateway()) {
  await requirePaymentAdministrator(companyId, userId);
  const merchant = await prisma.$transaction(async tx => {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`SELECT id FROM "Company" WHERE id = ${companyId} FOR UPDATE`;
    if (!rows.length) throw new NotFoundError('Company', companyId);
    const existing = await tx.stripeMerchant.findUnique({ where: { companyId } });
    if (existing) {
      if (existing.country !== country.toUpperCase()) throw new ConflictError('The merchant country is already set. Continue setup with the original country.');
      return existing;
    }
    const company = await tx.company.findUniqueOrThrow({ where: { id: companyId } });
    return tx.stripeMerchant.create({ data: { companyId, country: country.toUpperCase(), displayName: company.name, contactEmail: company.email, createdAt: new Date() } });
  });
  let accountId = merchant.accountId;
  if (!accountId) {
    accountId = await gateway.createMerchant(merchant);
    await prisma.stripeMerchant.update({ where: { companyId }, data: { accountId } });
  }
  const base = env.PUBLIC_WEB_BASE_URL.replace(/\/$/, '');
  const url = await gateway.onboardingLink(accountId, `${base}/payments/setup?status=returned`, `${base}/payments/setup?status=expired`);
  return { url };
}

/** Reserve only server-priced amounts. The partial unique index is a second
 * line of defense behind the Invoice lock against parallel customer taps.
 */
async function reserveCheckout(token: string, scope: 'next_installment' | 'balance') {
  const found = await prisma.invoice.findUnique({ where: { shareToken: token }, select: { id: true, companyId: true } });
  if (!found) throw new NotFoundError('Invoice');
  return prisma.$transaction(async tx => {
    const invoice = await lockInvoice(tx, found.id, found.companyId);
    if (invoice.status === 'DRAFT' || invoice.status === 'VOID' || invoice.amountDue.lte(0)) throw new ConflictError('This invoice has no available online payment.');
    if (invoice.paymentReviewRequired) throw new ConflictError('The contractor must review a refunded or disputed payment before collecting online again.');
    const active = await tx.invoiceCheckoutAttempt.findFirst({ where: { invoiceId: invoice.id, state: { in: ACTIVE_CHECKOUT_STATES } } });
    if (active) return { attempt: active, invoice };
    const merchant = await tx.stripeMerchant.findUnique({ where: { companyId: invoice.companyId } });
    if (!merchant?.accountId) throw new ConflictError('The contractor has not finished online payment setup.');
    const currencyCode = (invoice.currencyCode || 'USD').toUpperCase();
    if (!SUPPORTED_CURRENCIES.has(currencyCode)) throw new ValidationError('Online checkout is not supported for this invoice currency. Contact the contractor for payment instructions.');
    let amount = invoice.amountDue;
    if (scope === 'next_installment') {
      const installments = await tx.invoiceInstallment.findMany({ where: { invoiceId: invoice.id }, orderBy: { sortOrder: 'asc' } });
      let allocated = invoice.amountPaid;
      for (const installment of installments) {
        const paid = Prisma.Decimal.min(installment.amount, Prisma.Decimal.max(0, allocated));
        allocated = allocated.minus(paid);
        const due = installment.amount.minus(paid);
        if (due.gt(0)) { amount = Prisma.Decimal.min(due, invoice.amountDue); break; }
      }
    }
    const minor = minorAmount(amount);
    if (minor < MINIMUM_MINOR[currencyCode] || minor > 99_999_999)
      throw new ValidationError('This scheduled amount is outside the supported online payment range. Contact the contractor for payment instructions or a different payment schedule.');
    const letters = Array.from(randomBytes(8), byte => String.fromCharCode(97 + byte % 26)).join('');
    const attempt = await tx.invoiceCheckoutAttempt.create({ data: { invoiceId: invoice.id, companyId: invoice.companyId, accountId: merchant.accountId, createdAt: new Date(),
      amount, currencyCode, paymentScope: scope, integrationIdentifier: `proestimate_invoice_${letters}` } });
    return { attempt, invoice };
  });
}

/** This records session lifecycle only. Even a fresh paid status does NOT
 * create a receipt here; only verified webhook processing settles money.
 */
async function observeSession(attempt: InvoiceCheckoutAttempt, session: GatewaySession, gateway: InvoicePaymentGateway) {
  validateSession(attempt, session, attempt.accountId, gateway.liveMode);
  return prisma.$transaction(async tx => {
    await lockInvoice(tx, attempt.invoiceId, attempt.companyId);
    const current = await tx.invoiceCheckoutAttempt.findUniqueOrThrow({ where: { id: attempt.id } });
    validateSession(current, session, current.accountId, gateway.liveMode);
    if (!ACTIVE_CHECKOUT_STATES.includes(current.state)) return current;
    let state = session.paymentStatus === 'paid' ? 'PROCESSING' : session.status === 'expired' ? 'EXPIRED'
      : session.status === 'open' ? 'OPEN' : session.paymentIntentStatus === 'canceled' || session.paymentIntentStatus === 'requires_payment_method' ? 'FAILED' : 'PROCESSING';
    if (session.paymentIntentStatus === 'succeeded' && session.paymentStatus !== 'paid') state = 'PROCESSING';
    return tx.invoiceCheckoutAttempt.update({ where: { id: current.id }, data: {
      state, sessionId: session.id, paymentIntentId: session.paymentIntentId ?? current.paymentIntentId,
      checkoutUrl: session.url,
    } });
  });
}

export async function createCheckout(token: string, scope: 'next_installment' | 'balance' = 'next_installment', gateway = configuredGateway()) {
  const preflight = await prisma.invoice.findUnique({ where: { shareToken: token }, select: { companyId: true } });
  if (!preflight) throw new NotFoundError('Invoice');
  const merchant = await prisma.stripeMerchant.findUnique({ where: { companyId: preflight.companyId } });
  if (!merchant?.accountId || !(await gateway.merchantReady(merchant.accountId)))
    throw new ConflictError('The contractor must finish online payment setup before accepting payment.');
  const { attempt, invoice } = await reserveCheckout(token, scope);
  // Capability status is retrieved on every attempt, never trusted from a
  // previous onboarding redirect or a cached v1 charges_enabled flag.
  if (!(await gateway.merchantReady(attempt.accountId))) throw new ConflictError('The contractor’s payment account needs attention before it can accept payment.');
  let session: GatewaySession | null;
  if (attempt.sessionId) session = await gateway.retrieveSession(attempt.sessionId, attempt.accountId);
  else if (Date.now() - attempt.createdAt.getTime() < 50 * 60_000) session = await gateway.createSession(attempt, invoice.invoiceNumber, token);
  else {
    session = await gateway.findSession(attempt);
    if (!session) {
      await prisma.$transaction(async tx => {
        await lockInvoice(tx, attempt.invoiceId, attempt.companyId);
        await tx.invoiceCheckoutAttempt.updateMany({ where: { id: attempt.id, state: 'PREPARING', sessionId: null }, data: { state: 'FAILED' } });
      });
      throw new ConflictError('The previous checkout did not complete. Refresh this invoice to start again.');
    }
  }
  const observed = await observeSession(attempt, session, gateway);
  const url = observed.state === 'OPEN' ? observed.checkoutUrl : null;
  return { url, state: observed.state.toLowerCase(), amount: Number(observed.amount), currency_code: observed.currencyCode };
}

export async function cancelCheckout(invoiceId: string, companyId: string, userId: string, gateway = configuredGateway()) {
  await requirePaymentAdministrator(companyId, userId);
  if (!(await prisma.invoice.findFirst({ where: { id: invoiceId, companyId }, select: { id: true } }))) throw new NotFoundError('Invoice', invoiceId);
  const attempt = await prisma.invoiceCheckoutAttempt.findFirst({ where: { invoiceId, companyId, state: { in: ACTIVE_CHECKOUT_STATES } } });
  if (!attempt) return;
  let session = attempt.sessionId ? await gateway.retrieveSession(attempt.sessionId, attempt.accountId) : await gateway.findSession(attempt);
  if (!session) {
    // An in-flight request can commit after an early list response. Wait out
    // the provider request/checkout lifetime before releasing an unknown write.
    if (Date.now() - attempt.createdAt.getTime() < 65 * 60_000) throw new ConflictError('Checkout is still being prepared. Retry reconciliation shortly before recording another payment.');
    await prisma.$transaction(async tx => {
      await lockInvoice(tx, invoiceId, companyId);
      await tx.invoiceCheckoutAttempt.updateMany({ where: { id: attempt.id, state: 'PREPARING', sessionId: null }, data: { state: 'CANCELED' } });
    });
    return;
  }
  validateSession(attempt, session, attempt.accountId, gateway.liveMode);
  if (session.status === 'open') {
    try { session = await gateway.expireSession(session.id, attempt.accountId); }
    catch { session = await gateway.retrieveSession(session.id, attempt.accountId); }
  }
  const result = await observeSession(attempt, session, gateway);
  if (ACTIVE_CHECKOUT_STATES.includes(result.state)) throw new ConflictError('A payment is processing or awaiting verified confirmation. It cannot be replaced or manually recorded yet.');
}

/** The only path that writes Stripe payment receipts. Caller has verified the
 * webhook signature and fetched the session afresh from the correct account.
 */
async function settleVerifiedSession(session: GatewaySession, accountId: string, eventId: string, gateway: InvoicePaymentGateway, paymentDate: Date | null = null) {
  if (!session.attemptId) return;
  const found = await prisma.invoiceCheckoutAttempt.findUnique({ where: { id: session.attemptId } });
  if (!found) return;
  const merchant = await prisma.stripeMerchant.findUnique({ where: { companyId: found.companyId }, select: { accountId: true } });
  if (merchant?.accountId !== accountId) throw new ConflictError('The invoice merchant no longer matches its connected payment account.');
  validateSession(found, session, accountId, gateway.liveMode);
  await prisma.$transaction(async tx => {
    const invoice = await lockInvoice(tx, found.invoiceId, found.companyId);
    const attempt = await tx.invoiceCheckoutAttempt.findUniqueOrThrow({ where: { id: found.id } });
    validateSession(attempt, session, accountId, gateway.liveMode);
    if (await tx.stripePaymentEvent.findUnique({ where: { id: eventId } })) return;
    const paid = session.paymentStatus === 'paid' && session.paymentIntentStatus === 'succeeded' && !!session.paymentIntentId;
    if (paid) {
      const providerId = `stripe:${session.paymentIntentId}`;
      const receipt = await tx.invoicePayment.findUnique({ where: { providerPaymentId: providerId } });
      if (receipt && (receipt.invoiceId !== invoice.id || !receipt.amount.equals(attempt.amount))) throw new ConflictError('This Stripe receipt is already associated with different invoice details.');
      if (!receipt) {
        await tx.invoicePayment.create({ data: { invoiceId: invoice.id, companyId: invoice.companyId, requestId: providerId,
          providerPaymentId: providerId, amount: attempt.amount, method: 'STRIPE', recordedAt: paymentDate } });
        const amountPaid = invoice.amountPaid.plus(attempt.amount), amountDue = Prisma.Decimal.max(0, invoice.totalAmount.minus(amountPaid));
        await tx.invoice.update({ where: { id: invoice.id }, data: { amountPaid, amountDue,
          status: invoice.status === 'VOID' ? 'VOID' : amountDue.isZero() ? 'PAID' : 'PARTIALLY_PAID',
          paidAt: amountDue.isZero() ? paymentDate : null,
          paymentReviewRequired: invoice.paymentReviewRequired || amountPaid.gt(invoice.totalAmount) || invoice.status === 'VOID' } });
      } else if (!receipt.recordedAt && paymentDate) {
        // A refund may have arrived first. Fill the previously unknown original
        // date only when its actual signed payment-confirmation event arrives.
        await tx.invoicePayment.update({ where: { id: receipt.id }, data: { recordedAt: paymentDate } });
        if (invoice.status === 'PAID' && !invoice.paidAt) await tx.invoice.update({ where: { id: invoice.id }, data: { paidAt: paymentDate } });
      }
      await tx.invoiceCheckoutAttempt.update({ where: { id: attempt.id }, data: { state: attempt.refundedAmount.gt(0) ? 'REFUNDED' : 'PAID',
        sessionId: session.id, paymentIntentId: session.paymentIntentId, checkoutUrl: null } });
    } else if (ACTIVE_CHECKOUT_STATES.includes(attempt.state)) {
      const state = session.status === 'open' ? 'OPEN' : session.status === 'expired' && session.paymentIntentStatus !== 'succeeded' ? 'EXPIRED'
        : session.paymentIntentStatus === 'canceled' || session.paymentIntentStatus === 'requires_payment_method' ? 'FAILED' : 'PROCESSING';
      await tx.invoiceCheckoutAttempt.update({ where: { id: attempt.id }, data: { state, sessionId: session.id,
        paymentIntentId: session.paymentIntentId ?? attempt.paymentIntentId, checkoutUrl: state === 'OPEN' ? session.url : null } });
    }
    await tx.stripePaymentEvent.create({ data: { id: eventId, accountId, companyId: invoice.companyId } });
  });
}

async function settleVerifiedRefund(refund: GatewayRefund, accountId: string, eventId: string, gateway: InvoicePaymentGateway, refundDate: Date | null = null) {
  if (refund.status !== 'succeeded' || !refund.paymentIntentId) return;
  const session = await gateway.sessionForPaymentIntent(refund.paymentIntentId, accountId);
  if (!session?.attemptId) return;
  // A refund can precede the checkout completion event in delivery order.
  await settleVerifiedSession(session, accountId, `${eventId}:payment`, gateway);
  const found = await prisma.invoiceCheckoutAttempt.findUnique({ where: { id: session.attemptId } });
  if (!found) return;
  validateSession(found, session, accountId, gateway.liveMode);
  if (!Number.isSafeInteger(refund.amount) || refund.amount <= 0 || refund.currency.toUpperCase() !== found.currencyCode || refund.paymentIntentId !== session.paymentIntentId)
    throw new ConflictError('The refund does not match the original invoice payment.');
  const amount = new Prisma.Decimal(refund.amount).div(100);
  await prisma.$transaction(async tx => {
    const invoice = await lockInvoice(tx, found.invoiceId, found.companyId);
    const attempt = await tx.invoiceCheckoutAttempt.findUniqueOrThrow({ where: { id: found.id } });
    const providerId = `stripe-refund:${refund.id}`;
    const existingRefund = await tx.invoicePayment.findUnique({ where: { providerPaymentId: providerId } });
    if (existingRefund) {
      if (!existingRefund.recordedAt && refundDate) await tx.invoicePayment.update({ where: { id: existingRefund.id }, data: { recordedAt: refundDate } });
      return;
    }
    const original = await tx.invoicePayment.findUnique({ where: { providerPaymentId: `stripe:${refund.paymentIntentId}` } });
    if (!original || original.invoiceId !== invoice.id) throw new ConflictError('The original Stripe receipt must be confirmed before recording its refund.');
    if (attempt.refundedAmount.plus(amount).gt(attempt.amount)) throw new ConflictError('The refund exceeds the confirmed original payment.');
    await tx.invoicePayment.create({ data: { invoiceId: invoice.id, companyId: invoice.companyId, requestId: providerId,
      providerPaymentId: providerId, amount: amount.negated(), method: 'STRIPE_REFUND', recordedAt: refundDate } });
    const amountPaid = invoice.amountPaid.minus(amount);
    if (amountPaid.lt(0)) throw new ConflictError('Recorded payment corrections conflict with this refund. Review the invoice in Stripe.');
    const amountDue = Prisma.Decimal.max(0, invoice.totalAmount.minus(amountPaid));
    await tx.invoice.update({ where: { id: invoice.id }, data: { amountPaid, amountDue: invoice.status === 'VOID' ? 0 : amountDue,
      status: invoice.status === 'VOID' ? 'VOID' : amountPaid.gt(0) ? 'PARTIALLY_PAID' : 'SENT', paidAt: null, paymentReviewRequired: true } });
    await tx.invoiceCheckoutAttempt.update({ where: { id: attempt.id }, data: { refundedAmount: attempt.refundedAmount.plus(amount), state: 'REFUNDED' } });
    await tx.stripePaymentEvent.upsert({ where: { id: `${eventId}:refund:${refund.id}` }, create: { id: `${eventId}:refund:${refund.id}`, accountId, companyId: invoice.companyId }, update: {} });
  });
}

export async function receiveStripeWebhook(body: Buffer, signature: string, gateway = configuredGateway()) {
  let event: Stripe.Event;
  try { event = gateway.verifyEvent(body, signature); }
  catch { throw new AppError(400, 'INVALID_WEBHOOK_SIGNATURE', 'The Stripe webhook signature could not be verified.'); }
  if (event.livemode !== gateway.liveMode) throw new ValidationError('The Stripe event belongs to a different payment environment.');
  const accountId = event.account;
  if (!accountId) return;
  const merchant = await prisma.stripeMerchant.findUnique({ where: { accountId } });
  if (!merchant) return;
  const object = event.data.object as unknown as { id: string; payment_intent?: string | { id: string }; payment_status?: string; status?: string };
  if (['checkout.session.completed', 'checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed', 'checkout.session.expired'].includes(event.type)) {
    const session = await gateway.retrieveSession(object.id, accountId);
    if ((event.type === 'checkout.session.async_payment_succeeded' || object.payment_status === 'paid')
      && (session.paymentStatus !== 'paid' || session.paymentIntentStatus !== 'succeeded')) {
      throw new AppError(503, 'PAYMENT_CONFIRMATION_PENDING', 'Payment confirmation is not available yet. Retry this webhook.');
    }
    const paymentDate = event.type === 'checkout.session.async_payment_succeeded'
      || (event.type === 'checkout.session.completed' && object.payment_status === 'paid') ? new Date(event.created * 1000) : null;
    await settleVerifiedSession(session, accountId, event.id, gateway, paymentDate);
  } else if (['refund.created', 'refund.updated', 'refund.failed'].includes(event.type)) {
    await settleVerifiedRefund(await gateway.retrieveRefund(object.id, accountId), accountId, event.id, gateway,
      object.status === 'succeeded' ? new Date(event.created * 1000) : null);
  } else if (event.type === 'charge.refunded') {
    for (const refund of await gateway.refundsForCharge(object.id, accountId)) await settleVerifiedRefund(refund, accountId, event.id, gateway);
  } else if (event.type === 'charge.dispute.created') {
    const intentId = typeof object.payment_intent === 'string' ? object.payment_intent : object.payment_intent?.id;
    if (!intentId) return;
    let attempt = await prisma.invoiceCheckoutAttempt.findUnique({ where: { paymentIntentId: intentId } });
    if (!attempt) {
      const session = await gateway.sessionForPaymentIntent(intentId, accountId);
      if (session?.attemptId) attempt = await prisma.invoiceCheckoutAttempt.findUnique({ where: { id: session.attemptId } });
    }
    if (attempt?.accountId === accountId) {
      await prisma.$transaction(async tx => {
        const invoice = await lockInvoice(tx, attempt!.invoiceId, attempt!.companyId);
        if (await tx.stripePaymentEvent.findUnique({ where: { id: event.id } })) return;
        await tx.invoice.update({ where: { id: invoice.id }, data: { paymentReviewRequired: true } });
        await tx.stripePaymentEvent.create({ data: { id: event.id, accountId, companyId: invoice.companyId } });
      });
    }
  }
}

export async function acknowledgeRefundReview(invoiceId: string, companyId: string, userId: string, expectedPaid: number, expectedDue: number) {
  await requirePaymentAdministrator(companyId, userId);
  await prisma.$transaction(async tx => {
    const invoice = await lockInvoice(tx, invoiceId, companyId);
    if (!invoice.amountPaid.equals(expectedPaid) || !invoice.amountDue.equals(expectedDue)) throw new ConflictError('Payment totals changed. Refresh before acknowledging this review.');
    await tx.invoice.update({ where: { id: invoice.id }, data: { paymentReviewRequired: false } });
    await tx.activityLogEntry.create({ data: { projectId: invoice.projectId, companyId, userId, entityType: 'Invoice', action: 'UPDATED',
      description: `Refund or payment dispute reviewed for invoice ${invoice.invoiceNumber}` } });
  });
}

export async function sharedCheckoutAvailability(invoiceId: string, companyId: string) {
  const info = await invoiceCheckoutInfo(invoiceId, companyId);
  return { available: info.configured && info.account_connected && !info.requires_refund_review,
    processing: info.active_attempt?.state === 'processing', requires_contractor_review: info.requires_refund_review,
    test_mode: !env.STRIPE_API_KEY?.includes('_live_') };
}
