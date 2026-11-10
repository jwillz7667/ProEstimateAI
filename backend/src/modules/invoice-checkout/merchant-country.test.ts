import { describe, expect, it, vi } from 'vitest';
import Stripe from 'stripe';
import { StripeMerchant } from '@prisma/client';
import { MerchantCountryRejectedError, normalizedMerchantCountry, requireSupportedMerchantCountry, SUPPORTED_MERCHANT_COUNTRIES } from './merchant-country';
import { isDefinitiveMerchantCountryRejection, StripeInvoiceGateway } from './stripe-gateway';

vi.mock('../../config/env', () => ({ env: { NODE_ENV: 'test', STRIPE_PAYMENTS_ENABLED: false } }));

function countryError(code: string, statusCode = 400, type = 'invalid_request_error') {
  return new Stripe.errors.StripeInvalidRequestError({ type: type as 'invalid_request_error', code, statusCode });
}

describe('merchant country boundary and provider rejection', () => {
  it('offers the published native availability candidates without accepting preview or payout-only regions', () => {
    expect(SUPPORTED_MERCHANT_COUNTRIES).toHaveLength(44);
    expect(new Set(SUPPORTED_MERCHANT_COUNTRIES).size).toBe(44);
    for (const country of ['DE', 'FR', 'JP', 'AE', 'US']) expect(() => requireSupportedMerchantCountry(country)).not.toThrow();
    for (const country of ['AQ', 'ZZ', 'IN', 'ID', 'GH']) expect(() => requireSupportedMerchantCountry(country)).toThrow();
    expect(normalizedMerchantCountry('de')).toBe('DE');
    expect(() => normalizedMerchantCountry('usa')).toThrow();
  });

  it('classifies only explicit documented country rejection of a create request', () => {
    for (const code of ['country_code_invalid', 'cross_border_connected_account_creation_not_allowed', 'capability_not_available_in_country']) {
      expect(isDefinitiveMerchantCountryRejection(countryError(code))).toBe(true);
    }
    for (const code of ['unsupported_country', 'country_unsupported', 'invalid_fields', 'entity_type_not_supported_in_country', 'capability_not_available_in_platform_country', 'idempotency_key_in_use']) {
      expect(isDefinitiveMerchantCountryRejection(countryError(code))).toBe(false);
    }
    expect(isDefinitiveMerchantCountryRejection(countryError('country_code_invalid', 409))).toBe(false);
    expect(isDefinitiveMerchantCountryRejection(countryError('country_code_invalid', 500))).toBe(false);
    expect(isDefinitiveMerchantCountryRejection(countryError('country_code_invalid', 400, 'idempotency_error'))).toBe(false);
    expect(isDefinitiveMerchantCountryRejection(new Stripe.errors.StripeConnectionError({ message: 'Timeout' }))).toBe(false);
    expect(isDefinitiveMerchantCountryRejection({ type: 'StripeInvalidRequestError', rawType: 'invalid_request_error', statusCode: 400, code: 'country_code_invalid' })).toBe(false);
  });

  it('wraps a create rejection but preserves an account returned with unsupported capability status', async () => {
    const gateway = new StripeInvoiceGateway('rk_test_local_fixture_only', 'whsec_local_fixture_only');
    const client = (gateway as unknown as { client: Stripe }).client;
    const create = vi.spyOn(client.v2.core.accounts, 'create');
    const merchant = { companyId: 'company', requestId: 'request', country: 'US', displayName: 'Contractor', contactEmail: null, createdAt: new Date() } as StripeMerchant;
    create.mockRejectedValueOnce(countryError('capability_not_available_in_country'));
    await expect(gateway.createMerchant(merchant)).rejects.toBeInstanceOf(MerchantCountryRejectedError);
    create.mockResolvedValueOnce({ id: 'acct_retained', livemode: false, configuration: { merchant: { capabilities: { card_payments: { status: 'unsupported', status_details: [{ code: 'unsupported_country' }] } } } } } as never);
    await expect(gateway.createMerchant(merchant)).resolves.toBe('acct_retained');
    expect(create).toHaveBeenCalledTimes(2);
    expect(create.mock.calls[0][1]?.idempotencyKey).toBe(create.mock.calls[1][1]?.idempotencyKey);
  });

  it('checks the active claim immediately before a create and does not write after its loss', async () => {
    const gateway = new StripeInvoiceGateway('rk_test_local_fixture_only', 'whsec_local_fixture_only');
    const client = (gateway as unknown as { client: Stripe }).client;
    const create = vi.spyOn(client.v2.core.accounts, 'create');
    const merchant = { companyId: 'company', requestId: 'request', country: 'US', displayName: 'Contractor', contactEmail: null, createdAt: new Date() } as StripeMerchant;
    await expect(gateway.createMerchant(merchant, async () => { throw new Error('Lease lost'); })).rejects.toThrow('Lease lost');
    expect(create).not.toHaveBeenCalled();
  });

  it('renews before every explicit page, including empty intermediate pages, and before create', async () => {
    const gateway = new StripeInvoiceGateway('rk_test_local_fixture_only', 'whsec_local_fixture_only');
    const client = (gateway as unknown as { client: Stripe }).client;
    const events: string[] = [];
    vi.spyOn(client.v2.core.accounts, 'list').mockImplementationOnce(() => {
      events.push('page1');
      return Promise.resolve({ data: [], next_page_url: '/v2/core/accounts?page=second' }) as never;
    });
    const pages = vi.spyOn(client, 'rawRequest')
      .mockImplementationOnce(async () => { events.push('page2'); return { data: [], next_page_url: '/v2/core/accounts?page=third' }; })
      .mockImplementationOnce(async () => { events.push('page3'); return { data: [{ id: 'acct_other', livemode: false, metadata: {} }], next_page_url: null }; });
    vi.spyOn(client.v2.core.accounts, 'create').mockImplementationOnce(() => {
      events.push('create'); return Promise.resolve({ id: 'acct_new', livemode: false }) as never;
    });
    const merchant = { companyId: 'company', requestId: 'request', country: 'US', displayName: 'Contractor', contactEmail: null, createdAt: new Date(Date.now() - 24 * 60 * 60_000) } as StripeMerchant;
    await expect(gateway.createMerchant(merchant, async () => { events.push('renew'); })).resolves.toBe('acct_new');
    expect(events).toEqual(['renew', 'page1', 'renew', 'page2', 'renew', 'page3', 'renew', 'create']);
    expect(pages.mock.calls).toEqual([['GET', '/v2/core/accounts?page=second'], ['GET', '/v2/core/accounts?page=third']]);
  });

  it('reconciles an existing same-mode account after partial pages instead of creating a duplicate', async () => {
    const gateway = new StripeInvoiceGateway('rk_test_local_fixture_only', 'whsec_local_fixture_only');
    const client = (gateway as unknown as { client: Stripe }).client;
    vi.spyOn(client.v2.core.accounts, 'list').mockResolvedValueOnce({ data: [{ id: 'acct_other', livemode: false }], next_page_url: '/v2/core/accounts?page=second' } as never);
    vi.spyOn(client, 'rawRequest').mockResolvedValueOnce({ data: [{ id: 'acct_original', livemode: false, metadata: { proestimate_company_id: 'company' } }], next_page_url: null });
    const create = vi.spyOn(client.v2.core.accounts, 'create');
    const merchant = { companyId: 'company', requestId: 'request', country: 'US', displayName: 'Contractor', createdAt: new Date(0) } as StripeMerchant;
    await expect(gateway.createMerchant(merchant, async () => {})).resolves.toBe('acct_original');
    expect(create).not.toHaveBeenCalled();
  });

  it.each(['https://other.example/v2/core/accounts', '//other.example/v2/core/accounts', '/v2/core/accounts/other?page=next', '/v2/core/accounts?page=next#fragment'])('rejects an unexpected pagination target %s', async next => {
    const gateway = new StripeInvoiceGateway('rk_test_local_fixture_only', 'whsec_local_fixture_only');
    const client = (gateway as unknown as { client: Stripe }).client;
    vi.spyOn(client.v2.core.accounts, 'list').mockResolvedValueOnce({ data: [], next_page_url: next } as never);
    const raw = vi.spyOn(client, 'rawRequest'), create = vi.spyOn(client.v2.core.accounts, 'create');
    const merchant = { companyId: 'company', requestId: 'request', country: 'US', displayName: 'Contractor', createdAt: new Date(0) } as StripeMerchant;
    await expect(gateway.createMerchant(merchant)).rejects.toThrow('unexpected reconciliation page');
    expect(raw).not.toHaveBeenCalled(); expect(create).not.toHaveBeenCalled();
  });

  it('rejects cyclic pagination before creating an account from an incomplete scan', async () => {
    const gateway = new StripeInvoiceGateway('rk_test_local_fixture_only', 'whsec_local_fixture_only');
    const client = (gateway as unknown as { client: Stripe }).client;
    vi.spyOn(client.v2.core.accounts, 'list').mockResolvedValueOnce({ data: [], next_page_url: '/v2/core/accounts?page=repeat' } as never);
    const raw = vi.spyOn(client, 'rawRequest').mockResolvedValue({ data: [], next_page_url: '/v2/core/accounts?page=repeat' });
    const create = vi.spyOn(client.v2.core.accounts, 'create');
    const merchant = { companyId: 'company', requestId: 'request', country: 'US', displayName: 'Contractor', createdAt: new Date(0) } as StripeMerchant;
    await expect(gateway.createMerchant(merchant)).rejects.toThrow('repeated a page');
    expect(raw).toHaveBeenCalledTimes(1); expect(create).not.toHaveBeenCalled();
  });
});
