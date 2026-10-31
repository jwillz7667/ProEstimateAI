import { generateKeyPairSync, randomUUID } from 'node:crypto';
import type { Request, Response as ExpressResponse } from 'express';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { prisma } from '../../src/config/database';
import { env } from '../../src/config/env';
import * as appleApi from '../../src/lib/apple-server-api';
import {
  AppleJWSVerificationError,
  AppleNotificationType,
  type AppleTransactionInfo,
  verifyAndDecodeNotification,
  verifyAppleJWS,
} from '../../src/lib/apple-storekit';
import { createPurchaseAttempt, handleAppStoreWebhook, restorePurchases, syncTransaction } from '../../src/modules/commerce/commerce.service';
import { handleAppStoreNotification } from '../../src/modules/commerce/commerce-webhook.controller';
import {
  buildAppleTransactionInfo, buildDecodedNotification, createUserWithFreeEntitlement,
  resetCommerceTables, seedPlansAndProducts, STORE_PRODUCT_IDS,
} from './helpers';

vi.mock('../../src/lib/apple-storekit', async (importOriginal) => ({
  ...await importOriginal<typeof import('../../src/lib/apple-storekit')>(),
  verifyAppleJWS: vi.fn(),
  verifyAndDecodeNotification: vi.fn(),
}));
vi.mock('../../src/lib/apple-server-api', async (importOriginal) => ({
  ...await importOriginal<typeof import('../../src/lib/apple-server-api')>(),
  isAppStoreServerApiConfigured: vi.fn(() => false),
}));

const signedPayloads = new Map<string, AppleTransactionInfo>();
const verifyMock = vi.mocked(verifyAppleJWS);
let freePlanId: string;

function signed(payload: AppleTransactionInfo): string {
  const key = randomUUID();
  signedPayloads.set(key, payload);
  return key;
}

function receipt(overrides: Partial<AppleTransactionInfo> = {}): AppleTransactionInfo {
  return buildAppleTransactionInfo({ signedDate: Date.now(), ...overrides });
}

async function restore(userId: string, companyId: string, payload: AppleTransactionInfo) {
  return restorePurchases(userId, companyId, [{
    store_product_id: payload.productId,
    transaction_id: payload.transactionId,
    original_transaction_id: payload.originalTransactionId,
    app_account_token: payload.appAccountToken,
    environment: 'untrusted-client-environment',
    signed_transaction: signed(payload),
  }]);
}

beforeEach(async () => {
  await resetCommerceTables();
  const seeded = await seedPlansAndProducts();
  freePlanId = seeded.free.id;
  signedPayloads.clear();
  verifyMock.mockReset();
  verifyMock.mockImplementation(async (jws) => {
    const payload = signedPayloads.get(jws);
    if (!payload) throw new AppleJWSVerificationError('Unknown fixture');
    return payload;
  });
  vi.mocked(appleApi.isAppStoreServerApiConfigured).mockReturnValue(false);
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('Apple subscription reconciliation regressions', () => {
  it('uses signed monthly dates and does not grant an introductory trial to an ineligible buyer', async () => {
    const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
    const attempt = await createPurchaseAttempt(user.id, company.id, STORE_PRODUCT_IDS.proMonthly);
    const expiresDate = Date.now() + 123_456;
    const payload = receipt({ appAccountToken: attempt.app_account_token, expiresDate });
    const snapshot = await syncTransaction(user.id, company.id, {
      ...attempt,
      // Foundation UUID.uuidString uses upper case even though the backend
      // mints lower-case UUID text. The wire representations are equivalent.
      app_account_token: attempt.app_account_token.toUpperCase(),
      store_product_id: payload.productId,
      transaction_id: payload.transactionId,
      original_transaction_id: payload.originalTransactionId,
      environment: 'untrusted-client-environment',
      signed_transaction: signed(payload),
    });
    expect(snapshot.subscription_state).toBe('PRO_ACTIVE');
    expect(snapshot.trial_ends_at).toBeNull();
    expect(snapshot.renewal_date).toBe(new Date(expiresDate).toISOString());
    expect(snapshot.ends_at).toBe(new Date(expiresDate).toISOString());
    expect(snapshot.environment).toBe('Sandbox');
  });

  it('preserves Apple-signed trial expiry during a restore and never extends an expired receipt', async () => {
    const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
    const expiresDate = Date.now() + 60_000;
    const payload = receipt({ offerType: 1, offerDiscountType: 'FREE_TRIAL', expiresDate });
    const trial = await restore(user.id, company.id, payload);
    expect(trial.subscription_state).toBe('TRIAL_ACTIVE');
    expect(trial.trial_ends_at).toBe(new Date(expiresDate).toISOString());

    const expiredOwner = await createUserWithFreeEntitlement({ freePlanId });
    const expired = receipt({
      purchaseDate: Date.now() - 10_000,
      expiresDate: Date.now() - 1,
    });
    const snapshot = await restore(expiredOwner.user.id, expiredOwner.company.id, expired);
    expect(snapshot.subscription_state).toBe('EXPIRED');
    expect(snapshot.renewal_date).toBe(new Date(expired.expiresDate!).toISOString());
    expect(await prisma.usageBucket.findMany({
      where: { userId: expiredOwner.user.id, source: 'PRO_SUBSCRIPTION' },
    })).toEqual(expect.arrayContaining([expect.objectContaining({ includedQuantity: 0 })]));
  });

  it('keeps a refunded transaction revoked when its old pre-refund JWS is replayed', async () => {
    const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
    const payload = receipt();
    await restore(user.id, company.id, payload);
    const refund = buildDecodedNotification({
      notificationType: AppleNotificationType.REFUND,
      transactionInfo: { ...payload, revocationDate: Date.now() },
    });
    refund.payload.signedDate = payload.signedDate! + 100;
    await handleAppStoreWebhook(refund);
    const oldRenewal = buildDecodedNotification({
      notificationType: AppleNotificationType.DID_RENEW,
      transactionInfo: payload,
    });
    oldRenewal.payload.signedDate = payload.signedDate! + 1;
    await handleAppStoreWebhook(oldRenewal);
    const replay = await restore(user.id, company.id, payload);
    expect(replay.subscription_state).toBe('REVOKED');
    expect(replay.feature_flags.CAN_CREATE_INVOICE).toBe(false);
  });

  it('allows exactly one account to claim the same unbound subscription concurrently', async () => {
    const first = await createUserWithFreeEntitlement({ freePlanId });
    const second = await createUserWithFreeEntitlement({ freePlanId });
    const payload = receipt({ appAccountToken: randomUUID() });
    const claims = await Promise.allSettled([
      restore(first.user.id, first.company.id, payload),
      restore(second.user.id, second.company.id, payload),
    ]);
    expect(claims.filter((claim) => claim.status === 'fulfilled')).toHaveLength(1);
    const rejected = claims.find((claim) => claim.status === 'rejected');
    expect(rejected).toMatchObject({ status: 'rejected', reason: { code: 'SUBSCRIPTION_BOUND_TO_OTHER_USER' } });
    expect(await prisma.userEntitlement.count({
      where: { originalTransactionId: payload.originalTransactionId, status: 'PRO_ACTIVE' },
    })).toBe(1);
  });

  it('restores a migrated unknown signed account token once and preserves ownership after expiry', async () => {
    const owner = await createUserWithFreeEntitlement({ freePlanId });
    const other = await createUserWithFreeEntitlement({ freePlanId });
    const historicalToken = randomUUID();
    const payload = receipt({ appAccountToken: historicalToken });
    expect(await prisma.purchaseAttempt.findUnique({ where: { appAccountToken: historicalToken } })).toBeNull();
    const restored = await restore(owner.user.id, owner.company.id, payload);
    expect(restored.subscription_state).toBe('PRO_ACTIVE');
    expect(restored.feature_flags.CAN_GENERATE_PREVIEW).toBe(true);
    expect((await restore(owner.user.id, owner.company.id, payload)).subscription_state).toBe('PRO_ACTIVE');
    await prisma.userEntitlement.update({ where: { userId: owner.user.id }, data: { status: 'EXPIRED', endsAt: new Date(Date.now() - 1) } });
    await expect(restore(other.user.id, other.company.id, payload)).rejects.toMatchObject({ code: 'SUBSCRIPTION_BOUND_TO_OTHER_USER' });
    expect((await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: owner.user.id } })).originalTransactionId).toBe(payload.originalTransactionId);
    expect((await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: other.user.id } })).status).toBe('FREE');
  });

  it.each(['Production', 'Sandbox'])('accepts %s only after the Apple signature boundary verifies it', async (environment) => {
    const owner = await createUserWithFreeEntitlement({ freePlanId });
    const snapshot = await restore(owner.user.id, owner.company.id, receipt({ environment }));
    expect(snapshot.environment).toBe(environment);
    expect(snapshot.subscription_state).toBe('PRO_ACTIVE');
  });

  it('rejects local Xcode environment data even if a verification boundary is stubbed', async () => {
    const owner = await createUserWithFreeEntitlement({ freePlanId });
    await expect(restore(owner.user.id, owner.company.id, receipt({ environment: 'Xcode' }))).rejects.toMatchObject({ statusCode: 400 });
    expect((await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: owner.user.id } })).status).toBe('FREE');
  });

  it('reserves an unbound receipt for the known signed-token purchaser before initial sync', async () => {
    const buyer = await createUserWithFreeEntitlement({ freePlanId });
    const other = await createUserWithFreeEntitlement({ freePlanId });
    const attempt = await createPurchaseAttempt(buyer.user.id, buyer.company.id, STORE_PRODUCT_IDS.proMonthly);
    const payload = receipt({ appAccountToken: attempt.app_account_token.toUpperCase() });
    await expect(restore(other.user.id, other.company.id, payload)).rejects.toMatchObject({ code: 'ACCOUNT_MISMATCH' });
    expect(await prisma.userEntitlement.count({ where: { originalTransactionId: payload.originalTransactionId } })).toBe(0);
    expect((await restore(buyer.user.id, buyer.company.id, payload)).subscription_state).toBe('PRO_ACTIVE');
  });

  it('reconciles renewals using an already completed purchase attempt and rejects unrelated attempt IDs', async () => {
    const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
    const attempt = await createPurchaseAttempt(user.id, company.id, STORE_PRODUCT_IDS.proMonthly);
    const initial = receipt({ appAccountToken: attempt.app_account_token });
    const sync = (payload: AppleTransactionInfo, attemptId = attempt.purchase_attempt_id) => syncTransaction(user.id, company.id, {
      ...attempt,
      purchase_attempt_id: attemptId,
      store_product_id: payload.productId,
      transaction_id: payload.transactionId,
      original_transaction_id: payload.originalTransactionId,
      environment: payload.environment,
      signed_transaction: signed(payload),
    });
    await expect(sync(initial, 'unrelated-id')).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
    await sync(initial);
    const renewal = receipt({
      appAccountToken: attempt.app_account_token,
      originalTransactionId: initial.originalTransactionId,
      productId: STORE_PRODUCT_IDS.proAnnual,
      purchaseDate: initial.purchaseDate + 1000,
      signedDate: initial.signedDate! + 1000,
      expiresDate: Date.now() + 365 * 86_400_000,
    });
    const snapshot = await sync(renewal);
    expect(snapshot.current_plan_code).toBe('PRO_ANNUAL');
    expect(snapshot.latest_transaction_id).toBe(renewal.transactionId);
    expect(snapshot.renewal_date).toBe(new Date(renewal.expiresDate!).toISOString());
  });

  it('updates the catalog plan on renewal and ignores a delayed prior-period expiration/refund', async () => {
    const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
    const initial = receipt({ purchaseDate: Date.now() - 10_000, signedDate: Date.now() - 9_000 });
    await restore(user.id, company.id, initial);
    const renewal = receipt({ originalTransactionId: initial.originalTransactionId, productId: STORE_PRODUCT_IDS.proAnnual });
    const renewed = buildDecodedNotification({ notificationType: AppleNotificationType.DID_RENEW, transactionInfo: renewal });
    renewed.payload.signedDate = renewal.signedDate! + 1;
    await handleAppStoreWebhook(renewed);
    for (const notificationType of [AppleNotificationType.EXPIRED, AppleNotificationType.REFUND]) {
      const delayed = buildDecodedNotification({ notificationType, transactionInfo: initial });
      delayed.payload.signedDate = renewal.signedDate! + 100;
      await handleAppStoreWebhook(delayed);
    }
    const entitlement = await prisma.userEntitlement.findUniqueOrThrow({
      where: { userId: user.id }, include: { plan: true },
    });
    expect(entitlement.status).toBe('PRO_ACTIVE');
    expect(entitlement.plan.code).toBe('PRO_ANNUAL');
    expect(entitlement.storeProductId).toBe(STORE_PRODUCT_IDS.proAnnual);
    expect(entitlement.latestTransactionId).toBe(renewal.transactionId);
  });

  it('restores access and usage after a refund reversal and applies signed renewal extensions', async () => {
    const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
    const payload = receipt();
    await restore(user.id, company.id, payload);
    const refund = buildDecodedNotification({ notificationType: AppleNotificationType.REFUND, transactionInfo: payload });
    refund.payload.signedDate = payload.signedDate! + 1;
    await handleAppStoreWebhook(refund);
    const reversed = buildDecodedNotification({ notificationType: AppleNotificationType.REFUND_REVERSED, transactionInfo: payload });
    reversed.payload.signedDate = payload.signedDate! + 2;
    await handleAppStoreWebhook(reversed);
    const extended = { ...payload, expiresDate: payload.expiresDate! + 86_400_000 };
    const notification = buildDecodedNotification({ notificationType: AppleNotificationType.RENEWAL_EXTENDED, transactionInfo: extended });
    notification.payload.signedDate = payload.signedDate! + 3;
    await handleAppStoreWebhook(notification);
    const entitlement = await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: user.id } });
    expect(entitlement.status).toBe('PRO_ACTIVE');
    expect(entitlement.renewalDate?.getTime()).toBe(extended.expiresDate);
    const buckets = await prisma.usageBucket.findMany({ where: { userId: user.id, source: 'PRO_SUBSCRIPTION' } });
    expect(buckets).toHaveLength(2);
    expect(buckets.every((bucket) => bucket.includedQuantity === 999999)).toBe(true);
  });

  it('keeps retired Premium restorable while rejecting a new purchase attempt', async () => {
    const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
    const plan = await prisma.plan.create({ data: {
      code: 'PREMIUM_MONTHLY', displayName: 'Legacy Premium', description: 'Restore only',
      featuresJson: {}, isActive: false,
    } });
    await prisma.subscriptionProduct.create({ data: {
      planId: plan.id, storeProductId: 'proestimate.premium.monthly', displayName: 'Legacy Premium',
      description: 'Restore only', priceDisplay: '$49.99/mo', billingPeriodLabel: 'month',
    } });
    await expect(createPurchaseAttempt(user.id, company.id, 'proestimate.premium.monthly')).rejects.toMatchObject({ code: 'NOT_FOUND' });
    const restored = await restore(user.id, company.id, receipt({ productId: 'proestimate.premium.monthly' }));
    expect(restored.current_plan_code).toBe('PREMIUM_MONTHLY');
    expect(restored.subscription_state).toBe('PRO_ACTIVE');
  });

  it('asks Apple to retry transient processing failures instead of acknowledging lost notifications', async () => {
    const decoded = buildDecodedNotification({ notificationType: AppleNotificationType.DID_RENEW, transactionInfo: receipt() });
    vi.mocked(verifyAndDecodeNotification).mockResolvedValueOnce(decoded);
    vi.spyOn(prisma, '$transaction').mockRejectedValueOnce(new Error('temporary database outage'));
    const response = { status: vi.fn(), json: vi.fn() };
    response.status.mockReturnValue(response);
    await handleAppStoreNotification({ body: { signedPayload: 'fixture' } } as Request, response as unknown as ExpressResponse);
    expect(response.status).toHaveBeenCalledWith(503);
  });

  it('follows history pagination and returns the current revocation snapshot', async () => {
    const originalCredentials = {
      APP_STORE_ISSUER_ID: env.APP_STORE_ISSUER_ID,
      APP_STORE_API_KEY_ID: env.APP_STORE_API_KEY_ID,
      APP_STORE_API_PRIVATE_KEY: env.APP_STORE_API_PRIVATE_KEY,
    };
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    Object.assign(env, {
      APP_STORE_ISSUER_ID: 'test-issuer', APP_STORE_API_KEY_ID: 'test-key',
      APP_STORE_API_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    });
    const payload = receipt({ revocationDate: Date.now() });
    const firstPage = { revision: 'page-2', hasMore: true, signedTransactions: [signed(receipt())] };
    const secondPage = { revision: 'done', hasMore: false, signedTransactions: [signed(payload)] };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify(firstPage)))
      .mockResolvedValueOnce(new Response(JSON.stringify(secondPage)));
    vi.stubGlobal('fetch', fetchMock);
    try {
      const result = await appleApi.assertTransactionInHistory({
        originalTransactionId: payload.originalTransactionId, transactionId: payload.transactionId,
      });
      expect(result.revocationDate).toBe(payload.revocationDate);
      expect(fetchMock).toHaveBeenCalledTimes(2);
      expect(fetchMock.mock.calls[1][0].searchParams.get('revision')).toBe('page-2');
    } finally {
      Object.assign(env, originalCredentials);
    }
  });
});
