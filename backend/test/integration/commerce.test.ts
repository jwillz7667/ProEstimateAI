import { randomUUID } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { prisma } from "../../src/config/database";
import { CacheKeys, invalidateCache } from "../../src/config/redis";
import {
  createPurchaseAttempt,
  getProducts,
  syncTransaction,
  restorePurchases,
  handleAppStoreWebhook,
} from "../../src/modules/commerce/commerce.service";
import {
  AppleNotificationSubtype,
  AppleNotificationType,
  buildAppleTransactionInfo,
  buildDecodedNotification,
  createUserWithFreeEntitlement,
  resetCommerceTables,
  seedPlansAndProducts,
  STORE_PRODUCT_IDS,
} from "./helpers";

// All tests stub `verifyAppleJWS` because we don't have Apple's signing
// key. The DB transactions, identity gates, dedupe paths, and bucket
// math run against the real Prisma client.
vi.mock("../../src/lib/apple-storekit", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../src/lib/apple-storekit")>();
  return {
    ...actual,
    verifyAppleJWS: vi.fn(),
  };
});
import { verifyAppleJWS } from "../../src/lib/apple-storekit";

const verifyJWSMock = verifyAppleJWS as unknown as ReturnType<typeof vi.fn>;

describe("commerce service — integration", () => {
  let proMonthlyPlanId: string;
  let proAnnualPlanId: string;
  let freePlanId: string;

  beforeEach(async () => {
    await resetCommerceTables();
    const seeded = await seedPlansAndProducts();
    freePlanId = seeded.free.id;
    proMonthlyPlanId = seeded.proMonthly.id;
    proAnnualPlanId = seeded.proAnnual.id;
    verifyJWSMock.mockReset();
  });

  afterEach(() => {
    verifyJWSMock.mockReset();
  });

  // ─── createPurchaseAttempt ────────────────────────────

  describe("createPurchaseAttempt", () => {
    it("rolls stale PENDING attempts to ABANDONED before minting a new one", async () => {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });

      // Old attempt: 25h ago, still PENDING
      const oldAttempt = await prisma.purchaseAttempt.create({
        data: {
          userId: user.id,
          companyId: company.id,
          productId: (await prisma.subscriptionProduct.findFirstOrThrow({
            where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
          })).id,
          appAccountToken: randomUUID(),
          status: "PENDING",
          createdAt: new Date(Date.now() - 25 * 60 * 60 * 1000),
        },
      });

      // Recent attempt: 1h ago, still PENDING — should be left alone
      const recentAttempt = await prisma.purchaseAttempt.create({
        data: {
          userId: user.id,
          companyId: company.id,
          productId: (await prisma.subscriptionProduct.findFirstOrThrow({
            where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
          })).id,
          appAccountToken: randomUUID(),
          status: "PENDING",
          createdAt: new Date(Date.now() - 60 * 60 * 1000),
        },
      });

      await createPurchaseAttempt(
        user.id,
        company.id,
        STORE_PRODUCT_IDS.proMonthly,
        "PAYWALL",
      );

      const refreshedOld = await prisma.purchaseAttempt.findUniqueOrThrow({
        where: { id: oldAttempt.id },
      });
      const refreshedRecent = await prisma.purchaseAttempt.findUniqueOrThrow({
        where: { id: recentAttempt.id },
      });

      expect(refreshedOld.status).toBe("ABANDONED");
      expect(refreshedRecent.status).toBe("PENDING");
    });
  });

  // ─── getProducts ──────────────────────────────────────

  describe("getProducts", () => {
    it("excludes retired Premium products even when their rows still exist in the DB", async () => {
      // The standard fixture seeds only FREE/PRO. Inject a lingering
      // Premium plan + product to simulate a deployed DB that was seeded
      // before Premium was retired.
      const premiumMonthlyPlan = await prisma.plan.create({
        data: {
          code: "PREMIUM_MONTHLY",
          displayName: "Premium Monthly",
          description: "Legacy premium plan",
          featuresJson: {},
        },
      });
      await prisma.subscriptionProduct.create({
        data: {
          planId: premiumMonthlyPlan.id,
          storeProductId: "proestimate.premium.monthly",
          displayName: "Premium Monthly",
          description: "Legacy premium product",
          priceDisplay: "$49.99/mo",
          billingPeriodLabel: "month",
          hasIntroOffer: false,
          isFeatured: true,
          sortOrder: 3,
        },
      });

      // getProducts() caches under a fixed key; clear it so this test
      // reads fresh from the DB regardless of prior cases or CI Redis.
      await invalidateCache(CacheKeys.commerceProducts());

      const products = await getProducts();

      const planCodes = products.map((p) => p.plan_code);
      expect(planCodes).not.toContain("PREMIUM_MONTHLY");
      expect(planCodes).not.toContain("PREMIUM_ANNUAL");
      expect(planCodes.sort()).toEqual(["PRO_ANNUAL", "PRO_MONTHLY"]);
    });
  });

  // ─── syncTransaction ──────────────────────────────────

  describe("syncTransaction", () => {
    it("provisions PRO_ACTIVE entitlement and 999999 buckets on a clean monthly purchase", async () => {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });

      const annualProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proAnnual },
      });
      const attempt = await prisma.purchaseAttempt.create({
        data: {
          userId: user.id,
          companyId: company.id,
          productId: annualProduct.id,
          appAccountToken: randomUUID(),
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proAnnual,
        appAccountToken: attempt.appAccountToken,
      });
      verifyJWSMock.mockResolvedValueOnce(txn);

      const snapshot = await syncTransaction(user.id, company.id, {
        purchase_attempt_id: attempt.id,
        store_product_id: STORE_PRODUCT_IDS.proAnnual,
        transaction_id: txn.transactionId,
        original_transaction_id: txn.originalTransactionId,
        app_account_token: attempt.appAccountToken,
        environment: "Sandbox",
        signed_transaction: "stub-jws",
      });

      expect(snapshot.subscription_state).toBe("PRO_ACTIVE");
      expect(snapshot.current_plan_code).toBe("PRO_ANNUAL");
      expect(snapshot.feature_flags.CAN_CREATE_INVOICE).toBe(true);

      const buckets = await prisma.usageBucket.findMany({
        where: { userId: user.id, source: "PRO_SUBSCRIPTION" },
      });
      expect(buckets).toHaveLength(2);
      expect(buckets.every((b) => b.includedQuantity === 999999)).toBe(true);

      const refreshedAttempt = await prisma.purchaseAttempt.findUniqueOrThrow({
        where: { id: attempt.id },
      });
      expect(refreshedAttempt.status).toBe("COMPLETED");
      expect(refreshedAttempt.transactionId).toBe(txn.transactionId);
    });

    it("starts a 7-day trial when the product has an intro offer", async () => {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });

      const monthlyProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
      });
      const attempt = await prisma.purchaseAttempt.create({
        data: {
          userId: user.id,
          companyId: company.id,
          productId: monthlyProduct.id,
          appAccountToken: randomUUID(),
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proMonthly,
        appAccountToken: attempt.appAccountToken,
      });
      verifyJWSMock.mockResolvedValueOnce(txn);

      const snapshot = await syncTransaction(user.id, company.id, {
        purchase_attempt_id: attempt.id,
        store_product_id: STORE_PRODUCT_IDS.proMonthly,
        transaction_id: txn.transactionId,
        original_transaction_id: txn.originalTransactionId,
        app_account_token: attempt.appAccountToken,
        environment: "Sandbox",
        signed_transaction: "stub-jws",
      });

      expect(snapshot.subscription_state).toBe("TRIAL_ACTIVE");
      expect(snapshot.trial_ends_at).not.toBeNull();
    });

    it("rejects with ACCOUNT_MISMATCH when the attempt belongs to a different user", async () => {
      const owner = await createUserWithFreeEntitlement({ freePlanId });
      const stranger = await createUserWithFreeEntitlement({
        freePlanId,
        email: `stranger-${randomUUID()}@example.com`,
      });

      const monthlyProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
      });
      const attempt = await prisma.purchaseAttempt.create({
        data: {
          userId: owner.user.id,
          companyId: owner.company.id,
          productId: monthlyProduct.id,
          appAccountToken: randomUUID(),
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proMonthly,
        appAccountToken: attempt.appAccountToken,
      });
      verifyJWSMock.mockResolvedValueOnce(txn);

      await expect(
        syncTransaction(stranger.user.id, stranger.company.id, {
          purchase_attempt_id: attempt.id,
          store_product_id: STORE_PRODUCT_IDS.proMonthly,
          transaction_id: txn.transactionId,
          original_transaction_id: txn.originalTransactionId,
          app_account_token: attempt.appAccountToken,
          environment: "Sandbox",
          signed_transaction: "stub-jws",
        }),
      ).rejects.toThrowError(/different Apple ID/i);
    });

    it("rejects with SUBSCRIPTION_BOUND_TO_OTHER_USER when an active entitlement already owns the originalTransactionId", async () => {
      const original = await createUserWithFreeEntitlement({ freePlanId });
      const claimer = await createUserWithFreeEntitlement({
        freePlanId,
        email: `claimer-${randomUUID()}@example.com`,
      });

      const sharedOriginalTxnId = `otxn_${randomUUID()}`;

      // The original owner already holds an active subscription bound
      // to this originalTransactionId.
      await prisma.userEntitlement.update({
        where: { userId: original.user.id },
        data: {
          status: "PRO_ACTIVE",
          planId: proMonthlyPlanId,
          originalTransactionId: sharedOriginalTxnId,
        },
      });

      const monthlyProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
      });
      const claimerAttempt = await prisma.purchaseAttempt.create({
        data: {
          userId: claimer.user.id,
          companyId: claimer.company.id,
          productId: monthlyProduct.id,
          appAccountToken: randomUUID(),
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proMonthly,
        originalTransactionId: sharedOriginalTxnId,
        appAccountToken: claimerAttempt.appAccountToken,
      });
      verifyJWSMock.mockResolvedValueOnce(txn);

      await expect(
        syncTransaction(claimer.user.id, claimer.company.id, {
          purchase_attempt_id: claimerAttempt.id,
          store_product_id: STORE_PRODUCT_IDS.proMonthly,
          transaction_id: txn.transactionId,
          original_transaction_id: sharedOriginalTxnId,
          app_account_token: claimerAttempt.appAccountToken,
          environment: "Sandbox",
          signed_transaction: "stub-jws",
        }),
      ).rejects.toThrowError(/already linked/i);

      // Original owner's entitlement is untouched
      const originalEntitlement = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: original.user.id },
      });
      expect(originalEntitlement.status).toBe("PRO_ACTIVE");
    });

    it("releases the originalTransactionId from a terminal prior owner before claiming", async () => {
      const previous = await createUserWithFreeEntitlement({ freePlanId });
      const newOwner = await createUserWithFreeEntitlement({
        freePlanId,
        email: `new-${randomUUID()}@example.com`,
      });

      const sharedOriginalTxnId = `otxn_${randomUUID()}`;

      // Previous owner is EXPIRED, so the originalTransactionId is up
      // for grabs but the row still has a stale FK on it.
      await prisma.userEntitlement.update({
        where: { userId: previous.user.id },
        data: {
          status: "EXPIRED",
          planId: proMonthlyPlanId,
          originalTransactionId: sharedOriginalTxnId,
        },
      });

      const monthlyProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
      });
      const attempt = await prisma.purchaseAttempt.create({
        data: {
          userId: newOwner.user.id,
          companyId: newOwner.company.id,
          productId: monthlyProduct.id,
          appAccountToken: randomUUID(),
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proMonthly,
        originalTransactionId: sharedOriginalTxnId,
        appAccountToken: attempt.appAccountToken,
      });
      verifyJWSMock.mockResolvedValueOnce(txn);

      await syncTransaction(newOwner.user.id, newOwner.company.id, {
        purchase_attempt_id: attempt.id,
        store_product_id: STORE_PRODUCT_IDS.proMonthly,
        transaction_id: txn.transactionId,
        original_transaction_id: sharedOriginalTxnId,
        app_account_token: attempt.appAccountToken,
        environment: "Sandbox",
        signed_transaction: "stub-jws",
      });

      const previousEnt = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: previous.user.id },
      });
      expect(previousEnt.originalTransactionId).toBeNull();

      const newOwnerEnt = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: newOwner.user.id },
      });
      expect(newOwnerEnt.originalTransactionId).toBe(sharedOriginalTxnId);
      expect(newOwnerEnt.status).toBe("TRIAL_ACTIVE");
    });

    it("is idempotent — calling sync twice on the same attempt returns the existing snapshot", async () => {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });

      const annualProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proAnnual },
      });
      const attempt = await prisma.purchaseAttempt.create({
        data: {
          userId: user.id,
          companyId: company.id,
          productId: annualProduct.id,
          appAccountToken: randomUUID(),
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proAnnual,
        appAccountToken: attempt.appAccountToken,
      });
      verifyJWSMock.mockResolvedValue(txn);

      await syncTransaction(user.id, company.id, {
        purchase_attempt_id: attempt.id,
        store_product_id: STORE_PRODUCT_IDS.proAnnual,
        transaction_id: txn.transactionId,
        original_transaction_id: txn.originalTransactionId,
        app_account_token: attempt.appAccountToken,
        environment: "Sandbox",
        signed_transaction: "stub-jws",
      });

      const second = await syncTransaction(user.id, company.id, {
        purchase_attempt_id: attempt.id,
        store_product_id: STORE_PRODUCT_IDS.proAnnual,
        transaction_id: txn.transactionId,
        original_transaction_id: txn.originalTransactionId,
        app_account_token: attempt.appAccountToken,
        environment: "Sandbox",
        signed_transaction: "stub-jws",
      });

      expect(second.subscription_state).toBe("PRO_ACTIVE");

      const events = await prisma.subscriptionEvent.findMany({
        where: { transactionId: txn.transactionId },
      });
      expect(events).toHaveLength(1);
    });
  });

  // ─── restorePurchases ─────────────────────────────────

  describe("restorePurchases", () => {
    it("picks the latest transaction by Apple-signed purchaseDate, not array order", async () => {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });

      const oldOriginal = `otxn_${randomUUID()}`;
      const newOriginal = `otxn_${randomUUID()}`;
      const oldTxnId = `txn_${randomUUID()}`;
      const newTxnId = `txn_${randomUUID()}`;

      // Order in array is "newest first" but purchaseDate disagrees —
      // we should pick by purchaseDate.
      const newer = buildAppleTransactionInfo({
        transactionId: newTxnId,
        originalTransactionId: newOriginal,
        productId: STORE_PRODUCT_IDS.proMonthly,
        purchaseDate: Date.now(),
      });
      const older = buildAppleTransactionInfo({
        transactionId: oldTxnId,
        originalTransactionId: oldOriginal,
        productId: STORE_PRODUCT_IDS.proMonthly,
        purchaseDate: Date.now() - 10 * 24 * 60 * 60 * 1000,
      });

      verifyJWSMock
        .mockResolvedValueOnce(older)
        .mockResolvedValueOnce(newer);

      const snapshot = await restorePurchases(user.id, company.id, [
        {
          store_product_id: STORE_PRODUCT_IDS.proMonthly,
          transaction_id: oldTxnId,
          original_transaction_id: oldOriginal,
          app_account_token: null,
          environment: "Sandbox",
          signed_transaction: "stub-old",
        },
        {
          store_product_id: STORE_PRODUCT_IDS.proMonthly,
          transaction_id: newTxnId,
          original_transaction_id: newOriginal,
          app_account_token: null,
          environment: "Sandbox",
          signed_transaction: "stub-new",
        },
      ]);

      expect(snapshot.subscription_state).toBe("PRO_ACTIVE");
      const entitlement = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: user.id },
      });
      expect(entitlement.originalTransactionId).toBe(newOriginal);
    });

    it("blocks restore when an active entitlement already owns the latest originalTransactionId", async () => {
      const owner = await createUserWithFreeEntitlement({ freePlanId });
      const intruder = await createUserWithFreeEntitlement({
        freePlanId,
        email: `intruder-${randomUUID()}@example.com`,
      });

      const sharedOriginal = `otxn_${randomUUID()}`;

      await prisma.userEntitlement.update({
        where: { userId: owner.user.id },
        data: {
          status: "PRO_ACTIVE",
          planId: proMonthlyPlanId,
          originalTransactionId: sharedOriginal,
        },
      });

      const txn = buildAppleTransactionInfo({
        originalTransactionId: sharedOriginal,
        productId: STORE_PRODUCT_IDS.proMonthly,
      });
      verifyJWSMock.mockResolvedValueOnce(txn);

      await expect(
        restorePurchases(intruder.user.id, intruder.company.id, [
          {
            store_product_id: STORE_PRODUCT_IDS.proMonthly,
            transaction_id: txn.transactionId,
            original_transaction_id: sharedOriginal,
            app_account_token: null,
            environment: "Sandbox",
            signed_transaction: "stub-jws",
          },
        ]),
      ).rejects.toThrowError(/already linked/i);
    });
  });

  // ─── handleAppStoreWebhook ────────────────────────────

  describe("handleAppStoreWebhook", () => {
    async function setupActiveEntitlement(
      planId = proMonthlyPlanId,
    ) {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
      const originalTransactionId = `otxn_${randomUUID()}`;
      await prisma.userEntitlement.update({
        where: { userId: user.id },
        data: {
          status: "PRO_ACTIVE",
          planId,
          originalTransactionId,
          renewalDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        },
      });
      // Stand the buckets up to Pro size, mirroring what a real sync did.
      await prisma.usageBucket.updateMany({
        where: { userId: user.id, source: "STARTER_CREDITS" },
        data: { source: "PRO_SUBSCRIPTION", includedQuantity: 999999 },
      });
      return { user, company, originalTransactionId };
    }

    it("downgrades Pro buckets to 0 when the subscription EXPIREs", async () => {
      const { user, originalTransactionId } = await setupActiveEntitlement();

      const txn = buildAppleTransactionInfo({
        originalTransactionId,
        productId: STORE_PRODUCT_IDS.proMonthly,
      });
      const decoded = buildDecodedNotification({
        notificationType: AppleNotificationType.EXPIRED,
        transactionInfo: txn,
      });

      await handleAppStoreWebhook(decoded);

      const buckets = await prisma.usageBucket.findMany({
        where: { userId: user.id, source: "PRO_SUBSCRIPTION" },
      });
      expect(buckets).toHaveLength(2);
      expect(buckets.every((b) => b.includedQuantity === 0)).toBe(true);

      const ent = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: user.id },
      });
      expect(ent.status).toBe("EXPIRED");
    });

    it("dedupes by notificationUUID — second delivery of the same UUID is a no-op", async () => {
      const { user, originalTransactionId } = await setupActiveEntitlement();

      const txn = buildAppleTransactionInfo({
        originalTransactionId,
        productId: STORE_PRODUCT_IDS.proMonthly,
      });
      const sharedUUID = randomUUID();
      const decoded = buildDecodedNotification({
        notificationType: AppleNotificationType.DID_RENEW,
        notificationUUID: sharedUUID,
        transactionInfo: txn,
        renewalInfo: {
          originalTransactionId,
          productId: STORE_PRODUCT_IDS.proMonthly,
          autoRenewStatus: 1,
          renewalDate: Date.now() + 30 * 24 * 60 * 60 * 1000,
        },
      });

      await handleAppStoreWebhook(decoded);
      await handleAppStoreWebhook(decoded);

      const events = await prisma.subscriptionEvent.findMany({
        where: { userId: user.id },
      });
      expect(events).toHaveLength(1);
      expect(events[0].notificationUUID).toBe(sharedUUID);
    });

    it("bootstraps a brand-new entitlement when SUBSCRIBED arrives before iOS sync", async () => {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
      const monthlyProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
      });
      const appAccountToken = randomUUID();
      await prisma.purchaseAttempt.create({
        data: {
          userId: user.id,
          companyId: company.id,
          productId: monthlyProduct.id,
          appAccountToken,
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proMonthly,
        appAccountToken,
      });
      const decoded = buildDecodedNotification({
        notificationType: AppleNotificationType.SUBSCRIBED,
        subtype: AppleNotificationSubtype.INITIAL_BUY,
        transactionInfo: txn,
      });

      await handleAppStoreWebhook(decoded);

      const ent = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: user.id },
      });
      expect(["TRIAL_ACTIVE", "PRO_ACTIVE"]).toContain(ent.status);
      expect(ent.originalTransactionId).toBe(txn.originalTransactionId);
      expect(ent.latestTransactionId).toBe(txn.transactionId);

      const buckets = await prisma.usageBucket.findMany({
        where: { userId: user.id, source: "PRO_SUBSCRIPTION" },
      });
      expect(buckets.every((b) => b.includedQuantity === 999999)).toBe(true);

      const refreshedAttempt = await prisma.purchaseAttempt.findFirstOrThrow({
        where: { appAccountToken },
      });
      expect(refreshedAttempt.status).toBe("COMPLETED");
    });

    it("does not bootstrap a non-SUBSCRIBED notification with no entitlement", async () => {
      const { user, company } = await createUserWithFreeEntitlement({ freePlanId });
      const monthlyProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
      });
      const appAccountToken = randomUUID();
      await prisma.purchaseAttempt.create({
        data: {
          userId: user.id,
          companyId: company.id,
          productId: monthlyProduct.id,
          appAccountToken,
          status: "PENDING",
        },
      });

      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proMonthly,
        appAccountToken,
      });
      const decoded = buildDecodedNotification({
        notificationType: AppleNotificationType.DID_RENEW,
        transactionInfo: txn,
      });

      await handleAppStoreWebhook(decoded);

      // Entitlement should still be FREE — DID_RENEW without a prior
      // bind warns and returns; bootstrap is SUBSCRIBED-only.
      const ent = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: user.id },
      });
      expect(ent.status).toBe("FREE");
      expect(ent.originalTransactionId).toBeNull();
    });

    it("bootstrap refuses when originalTransactionId is already actively claimed by another user", async () => {
      const original = await createUserWithFreeEntitlement({ freePlanId });
      const incoming = await createUserWithFreeEntitlement({
        freePlanId,
        email: `incoming-${randomUUID()}@example.com`,
      });

      const sharedOriginal = `otxn_${randomUUID()}`;
      await prisma.userEntitlement.update({
        where: { userId: original.user.id },
        data: {
          status: "PRO_ACTIVE",
          planId: proMonthlyPlanId,
          originalTransactionId: sharedOriginal,
        },
      });

      const monthlyProduct = await prisma.subscriptionProduct.findFirstOrThrow({
        where: { storeProductId: STORE_PRODUCT_IDS.proMonthly },
      });
      const appAccountToken = randomUUID();
      await prisma.purchaseAttempt.create({
        data: {
          userId: incoming.user.id,
          companyId: incoming.company.id,
          productId: monthlyProduct.id,
          appAccountToken,
          status: "PENDING",
        },
      });

      // Webhook flow: Apple lookup by originalTransactionId hits the
      // *original* owner's entitlement, so the entitlement-found branch
      // runs (not the bootstrap branch). Test that the original owner's
      // state isn't disturbed and incoming user's attempt stays PENDING.
      const txn = buildAppleTransactionInfo({
        productId: STORE_PRODUCT_IDS.proMonthly,
        originalTransactionId: sharedOriginal,
        appAccountToken,
      });
      const decoded = buildDecodedNotification({
        notificationType: AppleNotificationType.DID_RENEW,
        transactionInfo: txn,
      });

      await handleAppStoreWebhook(decoded);

      const incomingEnt = await prisma.userEntitlement.findUniqueOrThrow({
        where: { userId: incoming.user.id },
      });
      expect(incomingEnt.status).toBe("FREE");

      const incomingAttempt = await prisma.purchaseAttempt.findFirstOrThrow({
        where: { appAccountToken },
      });
      expect(incomingAttempt.status).toBe("PENDING");
    });
  });
});
