import Stripe from 'stripe';
import { InvoiceCheckoutAttempt, StripeMerchant } from '@prisma/client';
import { env } from '../../config/env';
import { AppError, ConflictError } from '../../lib/errors';
import { checkoutConfigured, stripeCredentialsConfigured } from './invoice-checkout.policy';
import { MerchantCountryRejectedError } from './merchant-country';

export interface GatewaySession {
  id: string; url: string | null; amount: number | null; currency: string | null;
  status: string | null; paymentStatus: string; paymentIntentId: string | null; paymentIntentStatus: string | null;
  liveMode: boolean; attemptId: string | null; invoiceId: string | null;
}
export interface GatewayRefund {
  id: string; amount: number; currency: string; status: string | null; paymentIntentId: string | null;
}
export interface InvoicePaymentGateway {
  liveMode: boolean;
  createMerchant(merchant: StripeMerchant, verifyLease?: () => Promise<void>): Promise<string>;
  merchantReady(accountId: string): Promise<boolean>;
  onboardingLink(accountId: string, returnUrl: string, refreshUrl: string): Promise<string>;
  createSession(attempt: InvoiceCheckoutAttempt, invoiceNumber: string, token: string): Promise<GatewaySession>;
  retrieveSession(id: string, accountId: string): Promise<GatewaySession>;
  expireSession(id: string, accountId: string): Promise<GatewaySession>;
  findSession(attempt: InvoiceCheckoutAttempt): Promise<GatewaySession | null>;
  sessionForPaymentIntent(id: string, accountId: string): Promise<GatewaySession | null>;
  retrieveRefund(id: string, accountId: string): Promise<GatewayRefund>;
  refundsForCharge(id: string, accountId: string): Promise<GatewayRefund[]>;
  verifyEvent(body: Buffer, signature: string): Stripe.Event;
}

export type MerchantPaymentGateway = Pick<InvoicePaymentGateway, 'liveMode' | 'createMerchant' | 'merchantReady' | 'onboardingLink'>;

/**
 * These documented HTTP 400 account-create errors reject the country before
 * an account exists. A capability's unsupported_country status is NOT an
 * error: Stripe may have created the account and must retain its identity.
 * https://docs.stripe.com/api/v2/core/accounts/create
 * https://docs.stripe.com/error-codes#country_code_invalid
 */
export function isDefinitiveMerchantCountryRejection(error: unknown): boolean {
  return error instanceof Stripe.errors.StripeInvalidRequestError
    && error.statusCode === 400
    && error.rawType === 'invalid_request_error'
    && ['country_code_invalid', 'cross_border_connected_account_creation_not_allowed', 'capability_not_available_in_country'].includes(error.code ?? '');
}

const objectId = (value: string | { id: string } | null | undefined) => typeof value === 'string' ? value : value?.id ?? null;
function sessionValue(s: Stripe.Checkout.Session): GatewaySession {
  return { id: s.id, url: s.url, amount: s.amount_total, currency: s.currency, status: s.status,
    paymentStatus: s.payment_status, paymentIntentId: objectId(s.payment_intent),
    paymentIntentStatus: typeof s.payment_intent === 'object' ? s.payment_intent?.status ?? null : null,
    liveMode: s.livemode, attemptId: s.metadata?.checkout_attempt_id ?? null, invoiceId: s.metadata?.invoice_id ?? null };
}
const refundValue = (r: Stripe.Refund): GatewayRefund => ({ id: r.id, amount: r.amount, currency: r.currency,
  status: r.status, paymentIntentId: objectId(r.payment_intent) });

function merchantPagePath(path: string | null): string {
  // The SDK's public rawRequest retains its own Stripe host, auth/version and
  // retry policy. Only follow relative URLs for this exact listing endpoint.
  if (typeof path !== 'string' || !(path === '/v2/core/accounts' || path.startsWith('/v2/core/accounts?')) || path.includes('#') || path.includes('\\')) {
    throw new ConflictError('Stripe returned an unexpected reconciliation page. Contact support before retrying payment setup.');
  }
  return path;
}

type MerchantAccountPage = { data: Array<{ id: string; livemode: boolean; metadata?: Record<string, unknown> | null }>; next_page_url: string | null };
function merchantAccountPage(value: unknown): MerchantAccountPage {
  const page = value as MerchantAccountPage | null;
  if (!page || !Array.isArray(page.data) || !(page.next_page_url === null || typeof page.next_page_url === 'string')
    || page.data.some(account => !account || typeof account.id !== 'string' || typeof account.livemode !== 'boolean')) {
    throw new ConflictError('Stripe returned an incomplete reconciliation page. Contact support before retrying payment setup.');
  }
  return page;
}

export class StripeInvoiceGateway implements InvoicePaymentGateway {
  readonly liveMode: boolean;
  private readonly client: Stripe;
  constructor(private readonly key: string, private readonly signingSecret: string) {
    this.client = new Stripe(key, { maxNetworkRetries: 2, timeout: 20_000 });
    this.liveMode = key.includes('_live_');
  }
  async createMerchant(merchant: StripeMerchant, verifyLease?: () => Promise<void>) {
    if (Date.now() - merchant.createdAt.getTime() > 23 * 60 * 60_000) {
      let count = 0;
      let nextPage: string | null = null;
      let complete = false;
      const seen = new Set<string>();
      const deadline = Date.now() + 5 * 60_000;
      for (let pageIndex = 0; pageIndex < 200; pageIndex += 1) {
        if (Date.now() >= deadline) throw new ConflictError('Merchant reconciliation took too long. Contact support before retrying payment setup.');
        // Explicit pages are required: the SDK iterator can silently request
        // several empty/partial pages without yielding a single account.
        await verifyLease?.();
        const path = pageIndex === 0 ? '/v2/core/accounts?limit=100' : merchantPagePath(nextPage);
        if (seen.has(path)) throw new ConflictError('Stripe reconciliation repeated a page. Contact support before retrying payment setup.');
        seen.add(path);
        const page = merchantAccountPage(pageIndex === 0
          ? await this.client.v2.core.accounts.list({ limit: 100 })
          : await this.client.rawRequest('GET', path));
        for (const account of page.data) {
          if (++count > 10_000) throw new ConflictError('Merchant setup needs reconciliation in Stripe before another account can be created.');
          if (account.metadata?.proestimate_company_id === merchant.companyId && account.livemode === this.liveMode) return account.id;
        }
        nextPage = page.next_page_url;
        if (nextPage === null) { complete = true; break; }
      }
      if (!complete || Date.now() >= deadline) throw new ConflictError('Merchant setup needs reconciliation in Stripe before another account can be created.');
    }
    // Reconciliation can span multiple pages. An expired or superseded claim
    // must never start a new provider write after finishing those reads.
    await verifyLease?.();
    let result: Stripe.V2.Core.Account;
    try {
      result = await this.client.v2.core.accounts.create({
        display_name: merchant.displayName, ...(merchant.contactEmail ? { contact_email: merchant.contactEmail } : {}),
        dashboard: 'full', identity: { country: merchant.country.toLowerCase() },
        configuration: { merchant: { capabilities: { card_payments: { requested: true } } } },
        defaults: { responsibilities: { fees_collector: 'stripe', losses_collector: 'stripe' } },
        metadata: { proestimate_company_id: merchant.companyId }, include: ['configuration.merchant'],
      }, { idempotencyKey: `merchant-${merchant.requestId}` });
    } catch (error) {
      if (isDefinitiveMerchantCountryRejection(error)) throw new MerchantCountryRejectedError();
      throw error;
    }
    if (result.livemode !== this.liveMode) throw new ConflictError('The Stripe merchant belongs to a different payment environment.');
    return result.id;
  }
  async merchantReady(accountId: string) {
    const account = await this.client.v2.core.accounts.retrieve(accountId, { include: ['configuration.merchant'] });
    return account.livemode === this.liveMode && !account.closed && account.configuration?.merchant?.capabilities?.card_payments?.status === 'active';
  }
  async onboardingLink(accountId: string, returnUrl: string, refreshUrl: string) {
    const link = await this.client.v2.core.accountLinks.create({ account: accountId,
      use_case: { type: 'account_onboarding', account_onboarding: { return_url: returnUrl, refresh_url: refreshUrl } } });
    return link.url;
  }
  async createSession(attempt: InvoiceCheckoutAttempt, invoiceNumber: string, token: string) {
    const base = env.PUBLIC_WEB_BASE_URL.replace(/\/$/, '');
    const metadata = { invoice_id: attempt.invoiceId, checkout_attempt_id: attempt.id };
    const session = await this.client.checkout.sessions.create({
      mode: 'payment', client_reference_id: attempt.id, metadata,
      integration_identifier: attempt.integrationIdentifier,
      line_items: [{ quantity: 1, price_data: { currency: attempt.currencyCode.toLowerCase(),
        unit_amount: Number(attempt.amount.times(100)), product_data: { name: `Invoice ${invoiceNumber}${attempt.paymentScope === 'next_installment' ? ' — scheduled payment' : ''}` } } }],
      payment_intent_data: { metadata },
      success_url: `${base}/invoice/${encodeURIComponent(token)}?checkout=returned`,
      cancel_url: `${base}/invoice/${encodeURIComponent(token)}?checkout=cancelled`,
      expires_at: Math.floor(attempt.createdAt.getTime() / 1000) + 3600,
      expand: ['payment_intent'],
      // Invoice amounts already include agreed tax. No new tax, fees or client
      // supplied prices are introduced. Stripe chooses eligible payment methods.
    }, { stripeAccount: attempt.accountId, idempotencyKey: `invoice-checkout-${attempt.id}` });
    return sessionValue(session);
  }
  async retrieveSession(id: string, accountId: string) {
    return sessionValue(await this.client.checkout.sessions.retrieve(id, { expand: ['payment_intent'] }, { stripeAccount: accountId }));
  }
  async expireSession(id: string, accountId: string) {
    return sessionValue(await this.client.checkout.sessions.expire(id, { expand: ['payment_intent'] }, { stripeAccount: accountId }));
  }
  async findSession(attempt: InvoiceCheckoutAttempt) {
    // A committed Stripe response can be lost before its session ID is saved.
    // Complete the bounded search rather than reusing an expired idempotency key.
    let cursor: string | undefined;
    for (let page = 0; page < 100; page++) {
      const result = await this.client.checkout.sessions.list({ limit: 100, starting_after: cursor,
        created: { gte: Math.floor(attempt.createdAt.getTime() / 1000) - 60, lte: Math.floor(attempt.createdAt.getTime() / 1000) + 86_400 } }, { stripeAccount: attempt.accountId });
      const found = result.data.find(s => s.metadata?.checkout_attempt_id === attempt.id);
      if (found) return this.retrieveSession(found.id, attempt.accountId);
      if (!result.has_more) return null;
      cursor = result.data.at(-1)?.id;
      if (!cursor) break;
    }
    throw new ConflictError('Checkout needs reconciliation in Stripe before another payment can be started.');
  }
  async sessionForPaymentIntent(id: string, accountId: string) {
    const sessions = await this.client.checkout.sessions.list({ payment_intent: id, limit: 2 }, { stripeAccount: accountId });
    const matched = sessions.data.find(s => !!s.metadata?.checkout_attempt_id);
    return matched ? this.retrieveSession(matched.id, accountId) : null;
  }
  async retrieveRefund(id: string, accountId: string) {
    return refundValue(await this.client.refunds.retrieve(id, {}, { stripeAccount: accountId }));
  }
  async refundsForCharge(id: string, accountId: string) {
    const refunds: GatewayRefund[] = []; let cursor: string | undefined;
    for (let page = 0; page < 100; page++) {
      const result = await this.client.refunds.list({ charge: id, limit: 100, starting_after: cursor }, { stripeAccount: accountId });
      refunds.push(...result.data.map(refundValue));
      if (!result.has_more) return refunds;
      cursor = result.data.at(-1)?.id; if (!cursor) break;
    }
    throw new ConflictError('Refund history needs reconciliation in Stripe.');
  }
  verifyEvent(body: Buffer, signature: string) { return this.client.webhooks.constructEvent(body, signature, this.signingSecret); }
}

let gateway: InvoicePaymentGateway | undefined;
export function configuredGateway(): InvoicePaymentGateway {
  if (!checkoutConfigured()) throw new AppError(503, 'PAYMENTS_NOT_CONFIGURED', 'Online invoice payments are not configured.');
  return reconciliationGateway();
}

/** Disabling new collection must never disable receipts or cancellation for
 * sessions that were already created while payments were enabled.
 */
export function reconciliationGateway(): InvoicePaymentGateway {
  if (!stripeCredentialsConfigured()) throw new AppError(503, 'PAYMENT_RECONCILIATION_UNAVAILABLE', 'Existing online payments need their payment-service credentials restored before they can be reconciled.');
  return gateway ??= new StripeInvoiceGateway(env.STRIPE_API_KEY!, env.STRIPE_WEBHOOK_SECRET!);
}
