import { randomUUID } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import Stripe from 'stripe';
import { InvoiceCheckoutAttempt, StripeMerchant } from '@prisma/client';
import { prisma } from '../../src/config/database';
import * as checkout from '../../src/modules/invoice-checkout/invoice-checkout.service';
import * as finance from '../../src/modules/invoice-finance/invoice-finance.service';
import * as invoices from '../../src/modules/invoices/invoices.service';
import * as lines from '../../src/modules/invoice-line-items/invoice-line-items.service';
import * as projects from '../../src/modules/projects/projects.service';
import * as users from '../../src/modules/users/users.service';
import { lockCompanyPaymentErasure } from '../../src/modules/invoice-checkout/payment-erasure-lock';
import { env } from '../../src/config/env';
import { checkoutConfigured, stripeCredentialsConfigured } from '../../src/modules/invoice-checkout/invoice-checkout.policy';
import { GatewayRefund, GatewaySession, InvoicePaymentGateway, StripeInvoiceGateway } from '../../src/modules/invoice-checkout/stripe-gateway';

async function fixture() {
  const company = await prisma.company.create({ data: { name: 'Contractor payments' } });
  const user = await prisma.user.create({ data: { companyId: company.id, fullName: 'Owner', email: `${randomUUID()}@example.test` } });
  const client = await prisma.client.create({ data: { companyId: company.id, name: 'Client' } });
  const project = await prisma.project.create({ data: { companyId: company.id, clientId: client.id, title: 'Kitchen' } });
  const invoice = await prisma.invoice.create({ data: { companyId: company.id, projectId: project.id, clientId: client.id,
    invoiceNumber: 'PAY-1', status: 'SENT', subtotal: 100, totalAmount: 100, amountDue: 100 } });
  await prisma.stripeMerchant.create({ data: { companyId: company.id, accountId: `acct_${randomUUID()}`, country: 'US', displayName: company.name } });
  return { company, user, invoice, project, client };
}

class FakeGateway implements InvoicePaymentGateway {
  liveMode = false;
  ready = true;
  failAfterCreation = 0;
  sessions = new Map<string, GatewaySession>();
  attempts = new Map<string, string>();
  refunds = new Map<string, GatewayRefund>();
  createdAmounts: number[] = [];
  event: Stripe.Event | null = null;
  async createMerchant(_m: StripeMerchant) { return 'acct_new'; }
  async merchantReady(_id: string) { return this.ready; }
  async onboardingLink(_id: string, _return: string, _refresh: string) { return 'https://connect.stripe.com/setup/example'; }
  async createSession(attempt: InvoiceCheckoutAttempt) {
    const prior = this.attempts.get(attempt.id);
    if (prior) return { ...this.sessions.get(prior)! };
    const id = `cs_${randomUUID()}`;
    const session: GatewaySession = { id, url: 'https://checkout.stripe.com/c/pay/example', amount: Number(attempt.amount.times(100)),
      currency: attempt.currencyCode.toLowerCase(), status: 'open', paymentStatus: 'unpaid', paymentIntentId: null, paymentIntentStatus: null,
      liveMode: false, attemptId: attempt.id, invoiceId: attempt.invoiceId };
    this.sessions.set(id, session); this.attempts.set(attempt.id, id); this.createdAmounts.push(session.amount!);
    if (this.failAfterCreation-- > 0) throw new Error('Lost provider response');
    return { ...session };
  }
  async retrieveSession(id: string, _account: string) { const s = this.sessions.get(id); if (!s) throw new Error('No session'); return { ...s }; }
  async expireSession(id: string, account: string) { this.sessions.get(id)!.status = 'expired'; return this.retrieveSession(id, account); }
  async findSession(attempt: InvoiceCheckoutAttempt) { const id = this.attempts.get(attempt.id); return id ? this.retrieveSession(id, attempt.accountId) : null; }
  async sessionForPaymentIntent(id: string, account: string) { const s = [...this.sessions.values()].find(s => s.paymentIntentId === id); return s ? this.retrieveSession(s.id, account) : null; }
  async retrieveRefund(id: string, _account: string) { return this.refunds.get(id)!; }
  async refundsForCharge(_id: string, _account: string) { return [...this.refunds.values()]; }
  verifyEvent(_body: Buffer, signature: string) { if (signature !== 'valid' || !this.event) throw new Error('Signature'); return this.event; }
  paid(id: string) { const s = this.sessions.get(id)!; Object.assign(s, { status: 'complete', paymentStatus: 'paid', paymentIntentStatus: 'succeeded', paymentIntentId: s.paymentIntentId ?? `pi_${id}` }); }
  setEvent(type: Stripe.Event.Type, objectId: string, account: string, eventId = `evt_${randomUUID()}`) {
    this.event = { id: eventId, object: 'event', type, account, livemode: false, created: Math.floor(Date.now() / 1000),
      data: { object: { id: objectId, payment_status: this.sessions.get(objectId)?.paymentStatus, status: this.refunds.get(objectId)?.status } } } as unknown as Stripe.Event;
  }
}

async function addContractCredit(t: Awaited<ReturnType<typeof fixture>>, amount = 20) {
  const root = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateNumber: 'ROOT', totalAmount: 100 } });
  await prisma.invoice.update({ where: { id: t.invoice.id }, data: { estimateId: root.id } });
  const revised = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id,
    estimateNumber: 'REDUCED', revisesEstimateId: root.id, status: 'APPROVED', totalAmount: 100 - amount } });
  const proposal = await prisma.proposal.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateId: revised.id, status: 'APPROVED' } });
  const order = await prisma.changeOrder.create({ data: { companyId: t.company.id, projectId: t.project.id,
    rootEstimateId: root.id, baseEstimateId: root.id, estimateId: revised.id, proposalId: proposal.id,
    requestId: randomUUID(), title: 'Approved reduction', reason: 'Reduced scope', baseSnapshot: {},
    createdByUserId: t.user.id, status: 'APPLIED', rootInvoiceId: t.invoice.id } });
  return prisma.creditNote.create({ data: { companyId: t.company.id, projectId: t.project.id,
    rootEstimateId: root.id, sourceChangeOrderId: order.id, creditNumber: 'CR-1', amount,
    subtotalDelta: -amount, taxDelta: 0, discountDelta: 0, reason: 'Reduced scope' } });
}

describe('optional contractor invoice checkout', () => {
  beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company", "StripePaymentEvent" RESTART IDENTITY CASCADE'); });
  it('reserves one server-priced deposit despite parallel taps and retries a lost provider response safely', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    await prisma.invoiceInstallment.createMany({ data: [{ invoiceId: t.invoice.id, title: 'Deposit', amount: 30, sortOrder: 0 }, { invoiceId: t.invoice.id, title: 'Completion', amount: 70, sortOrder: 1 }] });
    gateway.failAfterCreation = 1;
    await expect(checkout.createCheckout(t.invoice.shareToken, 'next_installment', gateway)).rejects.toThrow('Lost provider');
    const [one, two] = await Promise.all([checkout.createCheckout(t.invoice.shareToken, 'next_installment', gateway), checkout.createCheckout(t.invoice.shareToken, 'next_installment', gateway)]);
    expect(one.url).toBe(two.url); expect(one.amount).toBe(30); expect(gateway.createdAmounts).toEqual([3000]);
    expect(await prisma.invoiceCheckoutAttempt.count()).toBe(1); expect(await prisma.invoicePayment.count()).toBe(0);
  });
  it('does not reserve an unusable checkout when the merchant is not ready', async () => {
    const t = await fixture(), gateway = new FakeGateway(); gateway.ready = false;
    await expect(checkout.createCheckout(t.invoice.shareToken, 'balance', gateway)).rejects.toMatchObject({ statusCode: 409 });
    expect(await prisma.invoiceCheckoutAttempt.count()).toBe(0);
  });
  it('never marks paid from the browser checkout response, then settles a signed verified completion once', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow(); gateway.paid(attempt.sessionId!);
    expect((await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway)).state).toBe('processing');
    expect((await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } })).amountPaid.toString()).toBe('0');
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId);
    const confirmationDate = new Date(gateway.event!.created * 1000);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    gateway.setEvent('checkout.session.async_payment_succeeded', attempt.sessionId!, attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    const invoice = await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } });
    expect(invoice.amountPaid.toString()).toBe('100'); expect(invoice.amountDue.toString()).toBe('0'); expect(invoice.status).toBe('PAID');
    expect(await prisma.invoicePayment.count()).toBe(1);
    expect((await prisma.invoicePayment.findFirstOrThrow()).recordedAt).toEqual(confirmationDate);
  });
  it('holds asynchronous payments until verified success and does not expire a paid payment from an out-of-order event', async () => {
    const t = await fixture(), gateway = new FakeGateway(); await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow();
    Object.assign(gateway.sessions.get(attempt.sessionId!)!, { status: 'complete', paymentIntentId: 'pi_delayed', paymentIntentStatus: 'processing' });
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    expect((await prisma.invoiceCheckoutAttempt.findUniqueOrThrow({ where: { id: attempt.id } })).state).toBe('PROCESSING');
    expect(await prisma.invoicePayment.count()).toBe(0);
    await expect(checkout.cancelCheckout(t.invoice.id, t.company.id, t.user.id, gateway)).rejects.toMatchObject({ statusCode: 409 });
    gateway.paid(attempt.sessionId!);
    gateway.setEvent('checkout.session.async_payment_succeeded', attempt.sessionId!, attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    gateway.setEvent('checkout.session.expired', attempt.sessionId!, attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    expect((await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } })).status).toBe('PAID');
    expect(await prisma.invoicePayment.count()).toBe(1);
  });
  it('rejects tampered amounts, wrong mode, wrong merchant and bad signatures without creating receipts', async () => {
    const t = await fixture(), gateway = new FakeGateway(); await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow(); gateway.paid(attempt.sessionId!);
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId);
    await expect(checkout.receiveStripeWebhook(Buffer.from('{}'), 'invalid', gateway)).rejects.toMatchObject({ statusCode: 400 });
    gateway.sessions.get(attempt.sessionId!)!.amount = 1;
    await expect(checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway)).rejects.toMatchObject({ statusCode: 409 });
    gateway.sessions.get(attempt.sessionId!)!.amount = 10000; gateway.sessions.get(attempt.sessionId!)!.liveMode = true;
    await expect(checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway)).rejects.toMatchObject({ statusCode: 409 });
    gateway.sessions.get(attempt.sessionId!)!.liveMode = false;
    const other = await fixture(); const otherMerchant = await prisma.stripeMerchant.findUniqueOrThrow({ where: { companyId: other.company.id } });
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, otherMerchant.accountId!);
    await expect(checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway)).rejects.toMatchObject({ statusCode: 409 });
    expect(await prisma.invoicePayment.count()).toBe(0);
  });
  it('blocks manual changes during checkout, permits exact prior manual receipt replay, and releases only after provider expiry', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    const receipt = { request_id: randomUUID(), amount: 10, method: 'cash' as const };
    await finance.recordPayment(t.invoice.id, t.company.id, t.user.id, receipt);
    await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    await finance.recordPayment(t.invoice.id, t.company.id, t.user.id, receipt);
    await expect(finance.recordPayment(t.invoice.id, t.company.id, t.user.id, { ...receipt, request_id: randomUUID() })).rejects.toMatchObject({ statusCode: 409 });
    await expect(invoices.update(t.invoice.id, t.company.id, { status: 'void' })).rejects.toMatchObject({ statusCode: 409 });
    await checkout.cancelCheckout(t.invoice.id, t.company.id, t.user.id, gateway);
    await finance.recordPayment(t.invoice.id, t.company.id, t.user.id, { ...receipt, request_id: randomUUID() });
    expect((await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } })).amountPaid.toString()).toBe('20');
  });
  it('records an out-of-order successful refund as a negative receipt and requires an owner review before collection', async () => {
    const t = await fixture(), gateway = new FakeGateway(); await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow(); gateway.paid(attempt.sessionId!);
    const session = gateway.sessions.get(attempt.sessionId!)!;
    gateway.refunds.set('re_partial', { id: 're_partial', amount: 2500, currency: 'usd', status: 'succeeded', paymentIntentId: session.paymentIntentId });
    gateway.setEvent('refund.created', 're_partial', attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    let invoice = await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } });
    expect(invoice.amountPaid.toString()).toBe('75'); expect(invoice.amountDue.toString()).toBe('25'); expect(invoice.paymentReviewRequired).toBe(true);
    expect((await prisma.invoicePayment.findMany({ orderBy: { createdAt: 'asc' } })).map(p => p.amount.toString())).toEqual(['100', '-25']);
    const originalReceipt = await prisma.invoicePayment.findFirstOrThrow({ where: { method: 'STRIPE' } });
    expect(originalReceipt.recordedAt).toBeNull();
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId);
    gateway.event!.created -= 86_400;
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    expect((await prisma.invoicePayment.findUniqueOrThrow({ where: { id: originalReceipt.id } })).recordedAt).toEqual(new Date(gateway.event!.created * 1000));
    expect((await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } })).amountPaid.toString()).toBe('75');
    await expect(checkout.createCheckout(t.invoice.shareToken, 'balance', gateway)).rejects.toMatchObject({ statusCode: 409 });
    const estimator = await prisma.user.create({ data: { companyId: t.company.id, fullName: 'Estimator', email: `${randomUUID()}@example.test`, role: 'ESTIMATOR' } });
    await expect(checkout.acknowledgeRefundReview(t.invoice.id, t.company.id, estimator.id, 75, 25)).rejects.toMatchObject({ statusCode: 403 });
    await expect(checkout.acknowledgeRefundReview(t.invoice.id, t.company.id, t.user.id, 100, 0)).rejects.toMatchObject({ statusCode: 409 });
    await checkout.acknowledgeRefundReview(t.invoice.id, t.company.id, t.user.id, 75, 25);
    invoice = await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } }); expect(invoice.paymentReviewRequired).toBe(false);
    await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway); expect(gateway.createdAmounts).toEqual([10000, 2500]);
  });
  it('does not turn pending or failed refunds into paid-balance corrections', async () => {
    const t = await fixture(), gateway = new FakeGateway(); await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow(); gateway.paid(attempt.sessionId!);
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId); await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    gateway.refunds.set('re_pending', { id: 're_pending', amount: 10000, currency: 'usd', status: 'pending', paymentIntentId: gateway.sessions.get(attempt.sessionId!)!.paymentIntentId });
    gateway.setEvent('refund.created', 're_pending', attempt.accountId); await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    expect((await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } })).status).toBe('PAID'); expect(await prisma.invoicePayment.count()).toBe(1);
  });
  it('keeps sent financial headers and lines immutable and only deletes drafts without receipt history', async () => {
    const t = await fixture();
    const item = await prisma.invoiceLineItem.create({ data: { invoiceId: t.invoice.id, name: 'Saved work', quantity: 1, unit: 'lot', unitCost: 100, lineTotal: 100 } });
    for (const change of [{ discount_amount: 10 }, { currency_code: 'CAD' }, { status: 'draft' as const }, { notes: 'Different terms' }])
      await expect(invoices.update(t.invoice.id, t.company.id, change)).rejects.toMatchObject({ statusCode: 409 });
    await expect(lines.update(item.id, t.company.id, { unit_cost: 1 })).rejects.toMatchObject({ statusCode: 409 });
    await expect(lines.remove(item.id, t.company.id)).rejects.toMatchObject({ statusCode: 409 });
    await expect(invoices.remove(t.invoice.id, t.company.id)).rejects.toMatchObject({ statusCode: 409 });
    await prisma.invoice.update({ where: { id: t.invoice.id }, data: { status: 'DRAFT' } });
    await invoices.remove(t.invoice.id, t.company.id); expect(await prisma.invoice.count()).toBe(0);
  });
  it('returns one invoice for parallel conversion retries and blocks full billing of already invoiced revisions', async () => {
    const t = await fixture();
    const plan = await prisma.plan.upsert({ where: { code: 'PRO_MONTHLY' }, create: { code: 'PRO_MONTHLY', displayName: 'Test Pro', description: 'Fixture', featuresJson: { CAN_CREATE_INVOICE: true } }, update: {} });
    await prisma.userEntitlement.create({ data: { userId: t.user.id, companyId: t.company.id, planId: plan.id,
      status: 'PRO_ACTIVE', source: 'ADMIN_OVERRIDE', renewalDate: new Date(Date.now() + 86_400_000) } });
    const source = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateNumber: 'CONVERT-1', status: 'APPROVED', subtotalMaterials: 20, totalAmount: 20 } });
    await prisma.estimateLineItem.create({ data: { estimateId: source.id, name: 'Work', quantity: 1, unit: 'lot', unitCost: 20, lineTotal: 20 } });
    const [one, two] = await Promise.all([invoices.createFromEstimate(t.company.id, t.user.id, source.id, {}), invoices.createFromEstimate(t.company.id, t.user.id, source.id, {})]);
    expect(one.id).toBe(two.id); expect(await prisma.invoice.count({ where: { estimateId: source.id } })).toBe(1);
    const revised = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateNumber: 'CONVERT-2', status: 'APPROVED', revisesEstimateId: source.id, version: 2, totalAmount: 40 } });
    await expect(invoices.createFromEstimate(t.company.id, t.user.id, revised.id, {})).rejects.toMatchObject({ statusCode: 409 });
    const independent = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateNumber: 'INDEPENDENT', status: 'APPROVED', totalAmount: 5 } });
    expect((await invoices.createFromEstimate(t.company.id, t.user.id, independent.id, {})).estimateId).toBe(independent.id);
  });
  it('blocks an obsolete parent from full billing after its newer version was invoiced first', async () => {
    const t = await fixture();
    const plan = await prisma.plan.upsert({ where: { code: 'PRO_MONTHLY' }, create: { code: 'PRO_MONTHLY', displayName: 'Test Pro', description: 'Fixture', featuresJson: { CAN_CREATE_INVOICE: true } }, update: {} });
    await prisma.userEntitlement.create({ data: { userId: t.user.id, companyId: t.company.id, planId: plan.id, status: 'PRO_ACTIVE', source: 'ADMIN_OVERRIDE', renewalDate: new Date(Date.now() + 86_400_000) } });
    const parent = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateNumber: 'PARENT', status: 'APPROVED' } });
    const child = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateNumber: 'CHILD', status: 'APPROVED', revisesEstimateId: parent.id } });
    const grandchild = await prisma.estimate.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateNumber: 'GRANDCHILD', status: 'APPROVED', revisesEstimateId: child.id } });
    await invoices.createFromEstimate(t.company.id, t.user.id, grandchild.id, {});
    await expect(invoices.createFromEstimate(t.company.id, t.user.id, parent.id, {})).rejects.toMatchObject({ statusCode: 409 });
    await expect(invoices.createFromEstimate(t.company.id, t.user.id, child.id, {})).rejects.toMatchObject({ statusCode: 409 });
  });
  it('verifies a real SDK webhook signature and rejects body tampering without making a network request', () => {
    const secret = 'whsec_local_signature_fixture_only';
    const body = JSON.stringify({ id: 'evt_fixture', object: 'event', type: 'checkout.session.completed', data: { object: {} } });
    const client = new Stripe('rk_test_local_fixture_only');
    const signature = client.webhooks.generateTestHeaderString({ payload: body, secret });
    const gateway = new StripeInvoiceGateway('rk_test_local_fixture_only', secret);
    expect(gateway.verifyEvent(Buffer.from(body), signature).id).toBe('evt_fixture');
    expect(() => gateway.verifyEvent(Buffer.from(body + ' '), signature)).toThrow();
  });

  it('expires an open checkout before project or sole-member account erasure', async () => {
    for (const eraseAccount of [false, true]) {
      const t = await fixture(), gateway = new FakeGateway();
      await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
      const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow({ where: { invoiceId: t.invoice.id } });
      if (eraseAccount) await users.deleteMe(t.user.id, gateway);
      else await projects.remove(t.project.id, t.company.id, gateway);
      expect(gateway.sessions.get(attempt.sessionId!)!.status).toBe('expired');
      expect(await prisma.invoiceCheckoutAttempt.count({ where: { id: attempt.id } })).toBe(0);
      expect(await prisma.project.findUnique({ where: { id: t.project.id } })).toBeNull();
    }
  });

  it('retains project, account and payment reconciliation rows while a write is unknown or processing', async () => {
    for (const state of ['PREPARING', 'PROCESSING']) {
      const t = await fixture(), gateway = new FakeGateway();
      if (state === 'PREPARING') gateway.failAfterCreation = 1;
      try { await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway); } catch {}
      const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow({ where: { invoiceId: t.invoice.id } });
      await prisma.invoiceCheckoutAttempt.update({ where: { id: attempt.id }, data: { state } });
      await expect(projects.remove(t.project.id, t.company.id, gateway)).rejects.toMatchObject({ statusCode: 409 });
      await expect(users.deleteMe(t.user.id, gateway)).rejects.toMatchObject({ statusCode: 409 });
      expect(await prisma.user.findUnique({ where: { id: t.user.id } })).not.toBeNull();
      expect(await prisma.invoiceCheckoutAttempt.findUnique({ where: { id: attempt.id } })).not.toBeNull();
    }
  });

  it('keeps reconciliation data if expiration cannot be confirmed or payment wins the deletion race', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow();
    gateway.expireSession = async () => { throw new Error('Unconfirmed cancellation'); };
    await expect(projects.remove(t.project.id, t.company.id, gateway)).rejects.toMatchObject({ statusCode: 409 });
    gateway.paid(attempt.sessionId!);
    await expect(projects.remove(t.project.id, t.company.id, gateway)).rejects.toMatchObject({ statusCode: 409 });
    expect(await prisma.invoicePayment.count()).toBe(0);
    expect(await prisma.invoice.findUnique({ where: { id: t.invoice.id } })).not.toBeNull();
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    expect(await prisma.invoicePayment.count()).toBe(1);
    await projects.remove(t.project.id, t.company.id, gateway);
    expect(await prisma.project.findUnique({ where: { id: t.project.id } })).toBeNull();
  });

  it('does not cancel shared-company payments when one member deletes only their account', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    await prisma.user.create({ data: { companyId: t.company.id, fullName: 'Remaining member', email: `${randomUUID()}@example.test` } });
    await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow();
    await users.deleteMe(t.user.id, gateway);
    expect(gateway.sessions.get(attempt.sessionId!)!.status).toBe('open');
    expect(await prisma.company.findUnique({ where: { id: t.company.id } })).not.toBeNull();
    expect(await prisma.invoiceCheckoutAttempt.findUnique({ where: { id: attempt.id } })).not.toBeNull();
  });

  it('serializes concurrent final-member deletions so a private orphaned tenancy is not left behind', async () => {
    const t = await fixture();
    const other = await prisma.user.create({ data: { companyId: t.company.id, fullName: 'Other member', email: `${randomUUID()}@example.test` } });
    await Promise.all([users.deleteMe(t.user.id), users.deleteMe(other.id)]);
    expect(await prisma.company.findUnique({ where: { id: t.company.id } })).toBeNull();
  });

  it('blocks a new checkout behind the final erasure gate instead of orphaning its provider session', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    let unlock!: () => void, locked!: () => void;
    const acquired = new Promise<void>(resolve => { locked = resolve; });
    const released = new Promise<void>(resolve => { unlock = resolve; });
    const erase = prisma.$transaction(async tx => {
      await lockCompanyPaymentErasure(tx, t.company.id); locked(); await released;
      await checkout.assertCheckoutErasureSafe(tx, t.company.id, t.project.id);
      await tx.invoice.delete({ where: { id: t.invoice.id } });
    });
    await acquired;
    const pending = checkout.createCheckout(t.invoice.shareToken, 'balance', gateway).then(() => 'created', () => 'rejected');
    await new Promise(resolve => setTimeout(resolve, 30));
    expect(gateway.createdAmounts).toEqual([]);
    unlock(); await erase;
    expect(await pending).toBe('rejected'); expect(await prisma.invoiceCheckoutAttempt.count()).toBe(0);
  });

  it('continues verified receipt reconciliation and cancellation while new collection is disabled', async () => {
    const previous = { enabled: env.STRIPE_PAYMENTS_ENABLED, key: env.STRIPE_API_KEY, secret: env.STRIPE_WEBHOOK_SECRET };
    try {
      env.STRIPE_PAYMENTS_ENABLED = false; env.STRIPE_API_KEY = 'rk_test_local_fixture_only'; env.STRIPE_WEBHOOK_SECRET = 'whsec_local_fixture_only';
      expect(checkoutConfigured()).toBe(false); expect(stripeCredentialsConfigured()).toBe(true);
      const t = await fixture(), gateway = new FakeGateway();
      await expect(checkout.createCheckout(t.invoice.shareToken, 'balance')).rejects.toMatchObject({ statusCode: 503 });
      await expect(checkout.receiveStripeWebhook(Buffer.from('{}'), 'invalid')).rejects.toMatchObject({ statusCode: 400 });
      await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
      const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow();
      await checkout.cancelCheckout(t.invoice.id, t.company.id, t.user.id, gateway);
      expect((await prisma.invoiceCheckoutAttempt.findUniqueOrThrow({ where: { id: attempt.id } })).state).toBe('EXPIRED');
    } finally { env.STRIPE_PAYMENTS_ENABLED = previous.enabled; env.STRIPE_API_KEY = previous.key; env.STRIPE_WEBHOOK_SECRET = previous.secret; }
  });

  it('applies an approved contract credit after a verified refund without inventing another cash receipt or charge', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow(); gateway.paid(attempt.sessionId!);
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    await addContractCredit(t, 20);
    gateway.refunds.set('re_credit', { id: 're_credit', amount: 2000, currency: 'usd', status: 'succeeded', paymentIntentId: gateway.sessions.get(attempt.sessionId!)!.paymentIntentId });
    gateway.setEvent('refund.created', 're_credit', attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    const result = await finance.getFinance(t.invoice.id, t.company.id);
    expect(result.invoice.amount_paid).toBe(80); expect(result.invoice.credit_amount).toBe(20); expect(result.invoice.amount_due).toBe(0);
    expect(result.payments.map(row => row.amount)).toEqual([100, -20]); expect(await prisma.creditAllocation.count()).toBe(1);
    expect(result.checkout.requires_refund_review).toBe(true); expect(result.checkout.can_record_manual_payment).toBe(false);
    await checkout.acknowledgeRefundReview(t.invoice.id, t.company.id, t.user.id, 80, 0);
    await expect(checkout.createCheckout(t.invoice.shareToken, 'balance', gateway)).rejects.toMatchObject({ statusCode: 409 });
    expect(gateway.createdAmounts).toEqual([10000]);
  });

  it('reconciles available credit before refusing an oversized manual receipt, then collects only the net balance', async () => {
    const t = await fixture(); await addContractCredit(t, 20);
    await expect(finance.recordPayment(t.invoice.id, t.company.id, t.user.id, { request_id: randomUUID(), amount: 100, method: 'cash' })).rejects.toMatchObject({ statusCode: 400 });
    expect((await finance.getFinance(t.invoice.id, t.company.id)).invoice.credit_amount).toBe(20);
    const result = await finance.recordPayment(t.invoice.id, t.company.id, t.user.id, { request_id: randomUUID(), amount: 80, method: 'cash' });
    expect(result.invoice.amount_paid).toBe(80); expect(result.invoice.amount_due).toBe(0); expect(result.payments.map(row => row.amount)).toEqual([80]);
  });

  it('keeps installment cash, credit and the next provider amount separate', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    await prisma.invoiceInstallment.createMany({ data: [{ invoiceId: t.invoice.id, title: 'Deposit', amount: 30, sortOrder: 0 }, { invoiceId: t.invoice.id, title: 'Completion', amount: 70, sortOrder: 1 }] });
    await addContractCredit(t, 20);
    const result = await finance.recordPayment(t.invoice.id, t.company.id, t.user.id, { request_id: randomUUID(), amount: 10, method: 'cash' });
    expect(result.installments.map(row => [row.paid_amount, row.credit_amount, row.amount_due])).toEqual([[10, 20, 0], [0, 0, 70]]);
    await checkout.createCheckout(t.invoice.shareToken, 'next_installment', gateway);
    expect(gateway.createdAmounts).toEqual([7000]);
  });

  it('settles a fully credited balance without creating a provider session or cash receipt', async () => {
    const t = await fixture(), gateway = new FakeGateway(); await addContractCredit(t, 100);
    expect((await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway)).state).toBe('settled');
    const result = await finance.getFinance(t.invoice.id, t.company.id);
    expect(result.invoice.amount_paid).toBe(0); expect(result.invoice.credit_amount).toBe(100); expect(result.invoice.amount_due).toBe(0);
    expect(gateway.createdAmounts).toEqual([]); expect(await prisma.invoicePayment.count()).toBe(0);
  });

  it('makes an older mark-paid request collect only the cash outstanding after contract credit', async () => {
    const t = await fixture(); await addContractCredit(t, 20);
    const result = await invoices.update(t.invoice.id, t.company.id, { status: 'paid', expected_amount_paid: 0 });
    expect(result.amountPaid.toString()).toBe('80'); expect(result.creditAmount.toString()).toBe('20'); expect(result.amountDue.toString()).toBe('0');
    expect((await prisma.invoicePayment.findMany()).map(row => row.amount.toString())).toEqual(['80']);
  });

  it('commits credit reconciliation but keeps the review hold until the owner sees the updated balance', async () => {
    const t = await fixture(); await addContractCredit(t, 20);
    await prisma.invoice.update({ where: { id: t.invoice.id }, data: { amountPaid: 80, amountDue: 20, paymentReviewRequired: true } });
    await expect(checkout.acknowledgeRefundReview(t.invoice.id, t.company.id, t.user.id, 80, 20)).rejects.toMatchObject({ statusCode: 409 });
    const result = await finance.getFinance(t.invoice.id, t.company.id);
    expect(result.invoice.amount_due).toBe(0); expect(result.invoice.credit_amount).toBe(20); expect(result.checkout.requires_refund_review).toBe(true);
    await checkout.acknowledgeRefundReview(t.invoice.id, t.company.id, t.user.id, 80, 0);
    expect((await finance.getFinance(t.invoice.id, t.company.id)).checkout.requires_refund_review).toBe(false);
  });

  it('rejects a manual correction to verified online cash so a later real refund cannot be counted twice', async () => {
    const t = await fixture(), gateway = new FakeGateway();
    await checkout.createCheckout(t.invoice.shareToken, 'balance', gateway);
    const attempt = await prisma.invoiceCheckoutAttempt.findFirstOrThrow(); gateway.paid(attempt.sessionId!);
    gateway.setEvent('checkout.session.completed', attempt.sessionId!, attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    await expect(invoices.update(t.invoice.id, t.company.id, { amount_paid: 80, expected_amount_paid: 100 })).rejects.toMatchObject({ statusCode: 409 });
    expect(await prisma.invoicePayment.count()).toBe(1);
    gateway.refunds.set('re_actual', { id: 're_actual', amount: 2000, currency: 'usd', status: 'succeeded', paymentIntentId: gateway.sessions.get(attempt.sessionId!)!.paymentIntentId });
    gateway.setEvent('refund.created', 're_actual', attempt.accountId);
    await checkout.receiveStripeWebhook(Buffer.from('{}'), 'valid', gateway);
    expect((await finance.getFinance(t.invoice.id, t.company.id)).invoice.amount_paid).toBe(80);
  });
});
