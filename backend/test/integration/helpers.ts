import { randomUUID } from "node:crypto";
import { prisma } from "../../src/config/database";
import {
  AppleNotificationType,
  AppleNotificationSubtype,
  EXPECTED_BUNDLE_ID,
  type AppleTransactionInfo,
  type DecodedAppleNotification,
} from "../../src/lib/apple-storekit";

// ─── Truncate helpers ──────────────────────────────────

/**
 * Wipe every commerce-relevant table. Order matters because of FKs:
 * SubscriptionEvent → UserEntitlement → Plan, PurchaseAttempt → User,
 * UsageBucket → User, User → Company.
 *
 * RESTART IDENTITY isn't strictly necessary (we use cuid not serial),
 * but CASCADE handles any future FK we forget to enumerate here.
 */
export async function resetCommerceTables() {
  await prisma.$executeRawUnsafe(`
    TRUNCATE TABLE
      "SubscriptionEvent",
      "PurchaseAttempt",
      "UsageBucket",
      "UsageEvent",
      "UserEntitlement",
      "SubscriptionProduct",
      "Plan",
      "RefreshToken",
      "UserIdentity",
      "User",
      "Company"
    RESTART IDENTITY CASCADE;
  `);
}

// ─── Plan / product fixtures ───────────────────────────

const PRO_MONTHLY_STORE_ID = "ai.proestimate.pro.monthly";
const PRO_ANNUAL_STORE_ID = "ai.proestimate.pro.annual";

/**
 * Seed the canonical FREE_STARTER plan, the PRO_MONTHLY plan with its
 * 7-day trial product, and the PRO_ANNUAL plan with no intro offer.
 * Mirrors the shape of `prisma/seed.ts` but trimmed to what the
 * commerce flows actually read.
 */
export async function seedPlansAndProducts() {
  const free = await prisma.plan.create({
    data: {
      code: "FREE_STARTER",
      displayName: "Starter",
      description: "Free plan with starter credits",
      featuresJson: {},
    },
  });

  const proMonthly = await prisma.plan.create({
    data: {
      code: "PRO_MONTHLY",
      displayName: "Pro Monthly",
      description: "Monthly Pro plan",
      featuresJson: {},
    },
  });

  const proAnnual = await prisma.plan.create({
    data: {
      code: "PRO_ANNUAL",
      displayName: "Pro Annual",
      description: "Annual Pro plan",
      featuresJson: {},
    },
  });

  const monthlyProduct = await prisma.subscriptionProduct.create({
    data: {
      planId: proMonthly.id,
      storeProductId: PRO_MONTHLY_STORE_ID,
      displayName: "Pro Monthly",
      description: "Pro features billed monthly",
      priceDisplay: "$19.99/month",
      billingPeriodLabel: "month",
      hasIntroOffer: true,
      introOfferDisplayText: "7-day free trial",
      sortOrder: 1,
    },
  });

  const annualProduct = await prisma.subscriptionProduct.create({
    data: {
      planId: proAnnual.id,
      storeProductId: PRO_ANNUAL_STORE_ID,
      displayName: "Pro Annual",
      description: "Pro features billed annually",
      priceDisplay: "$149/year",
      billingPeriodLabel: "year",
      hasIntroOffer: false,
      isFeatured: true,
      sortOrder: 2,
    },
  });

  return { free, proMonthly, proAnnual, monthlyProduct, annualProduct };
}

// ─── User / company fixtures ───────────────────────────

export async function createUserWithFreeEntitlement(args: {
  email?: string;
  freePlanId: string;
}) {
  const company = await prisma.company.create({
    data: { name: "Acme Renovations" },
  });

  const user = await prisma.user.create({
    data: {
      companyId: company.id,
      email: args.email ?? `user-${randomUUID()}@example.com`,
      fullName: "Test User",
      passwordHash: "not-used-in-commerce-tests",
    },
  });

  const entitlement = await prisma.userEntitlement.create({
    data: {
      userId: user.id,
      companyId: company.id,
      planId: args.freePlanId,
      status: "FREE",
    },
  });

  await prisma.usageBucket.createMany({
    data: [
      {
        userId: user.id,
        companyId: company.id,
        metricCode: "AI_GENERATION",
        includedQuantity: 3,
        consumedQuantity: 0,
        resetPolicy: "NEVER",
        source: "STARTER_CREDITS",
      },
      {
        userId: user.id,
        companyId: company.id,
        metricCode: "QUOTE_EXPORT",
        includedQuantity: 3,
        consumedQuantity: 0,
        resetPolicy: "NEVER",
        source: "STARTER_CREDITS",
      },
    ],
  });

  return { company, user, entitlement };
}

// ─── JWS payload + notification builders ───────────────

/**
 * Build an `AppleTransactionInfo` payload for the JWS verification mock
 * to return. Defaults match what StoreKit 2 typically emits for a fresh
 * monthly subscription purchase.
 */
export function buildAppleTransactionInfo(
  overrides: Partial<AppleTransactionInfo> = {},
): AppleTransactionInfo {
  const now = Date.now();
  return {
    transactionId: `txn_${randomUUID()}`,
    originalTransactionId: `otxn_${randomUUID()}`,
    productId: PRO_MONTHLY_STORE_ID,
    bundleId: EXPECTED_BUNDLE_ID,
    purchaseDate: now,
    expiresDate: now + 30 * 24 * 60 * 60 * 1000,
    type: "Auto-Renewable Subscription",
    environment: "Sandbox",
    ...overrides,
  };
}

/**
 * Build a fully-decoded notification — what `verifyAndDecodeNotification`
 * would return — for direct injection into `handleAppStoreWebhook`.
 */
export function buildDecodedNotification(args: {
  notificationType: string;
  subtype?: string;
  notificationUUID?: string;
  transactionInfo: AppleTransactionInfo;
  renewalInfo?: DecodedAppleNotification["renewalInfo"];
}): DecodedAppleNotification {
  return {
    payload: {
      notificationType: args.notificationType,
      subtype: args.subtype,
      notificationUUID: args.notificationUUID ?? randomUUID(),
      data: {
        signedTransactionInfo: "stub-jws",
        signedRenewalInfo: undefined,
        bundleId: EXPECTED_BUNDLE_ID,
        environment: args.transactionInfo.environment,
      },
      version: "2.0",
      signedDate: Date.now(),
    },
    transactionInfo: args.transactionInfo,
    renewalInfo: args.renewalInfo ?? null,
  };
}

export const STORE_PRODUCT_IDS = {
  proMonthly: PRO_MONTHLY_STORE_ID,
  proAnnual: PRO_ANNUAL_STORE_ID,
};

// Convenience constant re-exports so tests don't need a second import.
export { AppleNotificationType, AppleNotificationSubtype };
