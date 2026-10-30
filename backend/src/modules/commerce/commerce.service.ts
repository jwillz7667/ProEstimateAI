import { Prisma, type EntitlementStatus } from "@prisma/client";
import { getEntitlementUsageSnapshot } from "../../lib/entitlement-usage";
import { prisma } from "../../config/database";
import {
  AccountMismatchError,
  NotFoundError,
  SubscriptionOwnedByOtherUserError,
  ValidationError,
} from "../../lib/errors";
import { v4 as uuidv4 } from "uuid";
import { isAdminUser } from "../../lib/admin";
import { logger } from "../../config/logger";
import {
  cached,
  invalidateCache,
  CacheKeys,
  CacheTTL,
} from "../../config/redis";
import {
  DecodedAppleNotification,
  AppleNotificationType,
  AppleNotificationSubtype,
  AppleTransactionInfo,
  AppleJWSVerificationError,
  EXPECTED_BUNDLE_ID,
  verifyAppleJWS,
} from "../../lib/apple-storekit";
import {
  AppStoreServerApiError,
  AppStoreTransactionNotFoundError,
  assertTransactionInHistory,
  isAppStoreServerApiConfigured,
} from "../../lib/apple-server-api";
import {
  StoreProductDto,
  toStoreProductDto,
  EntitlementSnapshotDto,
  toEntitlementSnapshotDto,
  PurchaseAttemptResponseDto,
  ADMIN_ENTITLEMENT_SNAPSHOT,
} from "./commerce.dto";
import {
  SyncTransactionInput,
  RestoreTransactionInput,
} from "./commerce.validators";

// ─── Entitlement Service ───────────────────────────────

export async function getEffectiveEntitlement(
  userId: string,
  companyId: string,
): Promise<EntitlementSnapshotDto> {
  // Admin users get full Pro access without a real subscription
  if (await isAdminUser(userId)) {
    return ADMIN_ENTITLEMENT_SNAPSHOT;
  }

  // Rebuild effective status and rolling counters on every read. Caching the
  // final DTO can grant access past a signed deadline or show stale usage.
  const entitlement = await prisma.userEntitlement.findUnique({
    where: { userId },
    include: { plan: true },
  });
  if (!entitlement) throw new NotFoundError("UserEntitlement");
  const buckets = await prisma.usageBucket.findMany({ where: { userId, companyId } });
  return toEntitlementSnapshotDto(
    entitlement, buckets,
    await getEntitlementUsageSnapshot(userId, companyId, entitlement, buckets),
  );
}

// ─── Commerce Product Service ──────────────────────────

export async function getProducts(): Promise<StoreProductDto[]> {
  return cached(
    CacheKeys.commerceProducts(),
    CacheTTL.COMMERCE_PRODUCTS,
    async () => {
      // The Premium subscription tier is retired. Even if Premium
      // SubscriptionProduct rows still linger in a deployed DB, never
      // surface them to the client — only FREE and PRO are sellable.
      const products = await prisma.subscriptionProduct.findMany({
        where: {
          plan: {
            code: { notIn: ["PREMIUM_MONTHLY", "PREMIUM_ANNUAL"] },
            isActive: true,
          },
        },
        include: { plan: true },
        orderBy: { sortOrder: "asc" },
      });

      return products.map(toStoreProductDto);
    },
  );
}

// ─── Purchase Attempt Service ──────────────────────────

/**
 * How long a `PurchaseAttempt` may sit in `PENDING` before we treat it
 * as abandoned. The StoreKit purchase sheet itself has no analog of
 * "session expired", but realistically a user either completes the buy
 * within minutes or walks away. Anything older than a day is dead
 * weight — keeping it around bloats the table and clutters the audit
 * view. 24h is generous enough to absorb users who started a purchase
 * on Apple's pending-approval flow (Ask to Buy) and confirmed later.
 */
const PURCHASE_ATTEMPT_EXPIRY_HOURS = 24;

export async function createPurchaseAttempt(
  userId: string,
  companyId: string,
  productId: string,
  placement?: string,
): Promise<PurchaseAttemptResponseDto> {
  // Verify the product exists
  const product = await prisma.subscriptionProduct.findUnique({
    where: { storeProductId: productId },
    include: { plan: true },
  });

  if (!product || !product.plan.isActive || product.plan.code.startsWith("PREMIUM_")) {
    throw new NotFoundError("SubscriptionProduct", productId);
  }

  // Lazy expiry: roll any of this user's stale PENDING attempts to
  // ABANDONED before minting a new one. Cheap (uses the userId index)
  // and keeps the table's PENDING set bounded without needing a cron.
  const expiryCutoff = new Date(
    Date.now() - PURCHASE_ATTEMPT_EXPIRY_HOURS * 60 * 60 * 1000,
  );
  await prisma.purchaseAttempt.updateMany({
    where: {
      userId,
      status: "PENDING",
      createdAt: { lt: expiryCutoff },
    },
    data: { status: "ABANDONED" },
  });

  // Generate a unique app account token for StoreKit 2 purchase tracking
  const appAccountToken = uuidv4();

  const attempt = await prisma.purchaseAttempt.create({
    data: {
      userId,
      companyId,
      productId: product.id,
      placement: placement ?? null,
      appAccountToken,
      status: "PENDING",
    },
  });

  return {
    purchase_attempt_id: attempt.id,
    app_account_token: attempt.appAccountToken,
  };
}

// ─── Verified Apple subscription reconciliation ─────────────────────────────

const LIVE_CLAIM_STATUSES: EntitlementStatus[] = [
  "TRIAL_ACTIVE", "PRO_ACTIVE", "GRACE_PERIOD", "BILLING_RETRY",
  "CANCELED_ACTIVE", "ADMIN_OVERRIDE",
];

function signedTimestamp(payload: AppleTransactionInfo): number {
  return payload.signedDate ?? payload.purchaseDate;
}

function validateAppleTransaction(payload: AppleTransactionInfo): void {
  if (payload.bundleId !== EXPECTED_BUNDLE_ID ||
      payload.type !== "Auto-Renewable Subscription" ||
      !payload.transactionId || !payload.originalTransactionId || !payload.productId ||
      !Number.isFinite(payload.purchaseDate) ||
      !Number.isFinite(payload.expiresDate) ||
      !Number.isFinite(signedTimestamp(payload)) ||
      (payload.revocationDate !== undefined && !Number.isFinite(payload.revocationDate))) {
    throw new ValidationError("Signed transaction is not a valid subscription for this app");
  }
}

async function verifySignedTransactionPayload(args: {
  signedTransaction: string;
  expectedTransactionId: string;
  expectedOriginalTransactionId: string;
  expectedProductId: string;
  expectedAppAccountToken?: string;
}): Promise<AppleTransactionInfo> {
  let payload: AppleTransactionInfo;
  try {
    payload = await verifyAppleJWS<AppleTransactionInfo>(args.signedTransaction, "commerceTransaction");
  } catch (err) {
    if (err instanceof AppleJWSVerificationError) {
      throw new ValidationError(`Signed transaction failed Apple verification: ${err.message}`);
    }
    throw err;
  }
  validateAppleTransaction(payload);
  if (payload.transactionId !== args.expectedTransactionId ||
      payload.originalTransactionId !== args.expectedOriginalTransactionId ||
      payload.productId !== args.expectedProductId) {
    throw new ValidationError("Signed transaction identifiers do not match request body");
  }
  if (args.expectedAppAccountToken && payload.appAccountToken &&
      payload.appAccountToken.toLowerCase() !== args.expectedAppAccountToken.toLowerCase()) {
    throw new ValidationError("Signed transaction appAccountToken does not match purchase attempt");
  }

  if (isAppStoreServerApiConfigured()) {
    try {
      const current = await assertTransactionInHistory({
        originalTransactionId: payload.originalTransactionId,
        transactionId: payload.transactionId,
      });
      validateAppleTransaction(current);
      if (current.originalTransactionId !== payload.originalTransactionId ||
          current.productId !== payload.productId) {
        throw new ValidationError("Apple transaction history does not match the signed transaction");
      }
      payload = current;
    } catch (err) {
      if (err instanceof AppStoreTransactionNotFoundError) {
        throw new ValidationError("Transaction could not be confirmed against Apple's server-side history");
      }
      if (!(err instanceof AppStoreServerApiError)) throw err;
      // The signed payload still bounds access to its actual expiration. A
      // later locally persisted refund cannot be overwritten by this old JWS.
      logger.warn({ statusCode: err.statusCode }, "Apple history unavailable; using bounded signed transaction");
    }
  }
  return payload;
}

type Notification = DecodedAppleNotification;
type SubscriptionEventType = Prisma.SubscriptionEventCreateInput['eventType'];

function eventTypeForNotification(type: string, subtype?: string): SubscriptionEventType {
  switch (type) {
    case AppleNotificationType.SUBSCRIBED:
      return subtype === AppleNotificationSubtype.INITIAL_BUY ? "INITIAL_PURCHASE" : "PURCHASED";
    case AppleNotificationType.DID_RENEW:
      return subtype === AppleNotificationSubtype.BILLING_RECOVERY ? "GRACE_PERIOD_RECOVERED" : "RENEWED";
    case AppleNotificationType.DID_FAIL_TO_RENEW:
      return subtype === AppleNotificationSubtype.GRACE_PERIOD ? "GRACE_PERIOD_ENTERED" : "BILLING_RETRY_ENTERED";
    case AppleNotificationType.EXPIRED:
    case AppleNotificationType.GRACE_PERIOD_EXPIRED: return "EXPIRED";
    case AppleNotificationType.REVOKE: return "REVOKED";
    case AppleNotificationType.REFUND: return "REFUNDED";
    case AppleNotificationType.REFUND_REVERSED: return "RESTORED";
    case AppleNotificationType.DID_CHANGE_RENEWAL_STATUS:
      return subtype === AppleNotificationSubtype.AUTO_RENEW_DISABLED ? "AUTO_RENEW_DISABLED" : "AUTO_RENEW_ENABLED";
    default: return "PRODUCT_CHANGED";
  }
}

function deriveSignedState(
  payload: AppleTransactionInfo,
  notification?: Notification,
  existingAutoRenew?: boolean | null,
) {
  const expiresAt = new Date(payload.expiresDate!);
  const now = Date.now();
  const isTrial = payload.offerType === 1 && payload.offerDiscountType === "FREE_TRIAL";
  const renewal = notification?.renewalInfo;
  const type = notification?.payload.notificationType;
  const subtype = notification?.payload.subtype;
  let status: EntitlementStatus = expiresAt.getTime() > now
    ? (isTrial ? "TRIAL_ACTIVE" : "PRO_ACTIVE") : "EXPIRED";
  let autoRenew = renewal ? renewal.autoRenewStatus === 1 : existingAutoRenew ?? null;
  let gracePeriodEndsAt: Date | null = null;
  let endsAt = expiresAt;

  if (type === AppleNotificationType.DID_CHANGE_RENEWAL_STATUS) {
    autoRenew = subtype !== AppleNotificationSubtype.AUTO_RENEW_DISABLED;
  }
  if (status !== "EXPIRED" && autoRenew === false) status = "CANCELED_ACTIVE";

  if (renewal?.gracePeriodExpiresDate && renewal.gracePeriodExpiresDate > now) {
    gracePeriodEndsAt = new Date(renewal.gracePeriodExpiresDate);
    status = "GRACE_PERIOD";
  } else if (type === AppleNotificationType.DID_FAIL_TO_RENEW) {
    status = "BILLING_RETRY";
  }
  if (type === AppleNotificationType.EXPIRED || type === AppleNotificationType.GRACE_PERIOD_EXPIRED) {
    status = "EXPIRED";
    gracePeriodEndsAt = null;
  }
  if (payload.revocationDate !== undefined || type === AppleNotificationType.REFUND || type === AppleNotificationType.REVOKE) {
    status = "REVOKED";
    endsAt = new Date(payload.revocationDate ?? notification!.payload.signedDate);
    gracePeriodEndsAt = null;
  }
  return {
    status,
    startsAt: new Date(payload.purchaseDate),
    endsAt,
    renewalDate: expiresAt,
    trialEndsAt: isTrial ? expiresAt : null,
    gracePeriodEndsAt,
    isAutoRenewEnabled: autoRenew,
    source: "APP_STORE",
    environment: payload.environment,
    latestTransactionId: payload.transactionId,
  };
}

/** All claim writers share these transaction locks, including webhook bootstrap. */
async function lockSubscription(transaction: Prisma.TransactionClient, originalId: string) {
  await transaction.$queryRaw`
    SELECT pg_advisory_xact_lock(hashtext('proestimate:apple-subscription'), hashtext(${originalId}))::text
  `;
}

async function lockAccount(transaction: Prisma.TransactionClient, userId: string) {
  await transaction.$queryRaw`
    SELECT pg_advisory_xact_lock(hashtext('proestimate:commerce-user'), hashtext(${userId}))::text
  `;
}

async function assertAndReleasePriorClaim(
  transaction: Prisma.TransactionClient,
  userId: string,
  originalTransactionId: string,
) {
  const otherClaims = await transaction.userEntitlement.findMany({
    where: { originalTransactionId, userId: { not: userId } },
  });
  if (otherClaims.some((claim) => LIVE_CLAIM_STATUSES.includes(claim.status))) {
    throw new SubscriptionOwnedByOtherUserError();
  }
  await transaction.userEntitlement.updateMany({
    where: {
      originalTransactionId,
      userId: { not: userId },
      status: { notIn: LIVE_CLAIM_STATUSES },
    },
    data: { originalTransactionId: null },
  });
}

interface ApplyTransactionOptions {
  userId: string;
  companyId: string;
  payload: AppleTransactionInfo;
  eventType: SubscriptionEventType;
  notification?: Notification;
  attemptToken?: string;
  attemptId?: string;
}

/** Must run under the subscription lock; account lock serializes competing restores. */
async function applyVerifiedTransaction(
  transaction: Prisma.TransactionClient,
  options: ApplyTransactionOptions,
): Promise<void> {
  const { userId, companyId, payload, notification } = options;
  await lockAccount(transaction, userId);
  if (notification && await transaction.subscriptionEvent.findUnique({
    where: { notificationUUID: notification.payload.notificationUUID },
  })) return;

  const current = await transaction.userEntitlement.findUnique({ where: { userId } });
  const product = await transaction.subscriptionProduct.findUnique({
    where: { storeProductId: payload.productId },
    include: { plan: true },
  });
  // Retired products remain restorable; isActive governs new sales only.
  if (!product) throw new NotFoundError("SubscriptionProduct", payload.productId);

  // During the interval before initial sync/webhook binding, the signed token
  // already identifies the purchaser. A restore must not let another account
  // win that claim. Unknown tokens remain restorable after a database reset.
  if (payload.appAccountToken) {
    const signedAttempt = await transaction.purchaseAttempt.findUnique({
      where: { appAccountToken: payload.appAccountToken.toLowerCase() },
    });
    if (signedAttempt && (signedAttempt.userId !== userId || signedAttempt.companyId !== companyId)) {
      throw new AccountMismatchError();
    }
  }

  let attempt;
  if (options.attemptToken) {
    attempt = await transaction.purchaseAttempt.findUnique({
      where: { appAccountToken: options.attemptToken.toLowerCase() },
    });
    if (!attempt) throw new NotFoundError("PurchaseAttempt");
    if (attempt.userId !== userId || attempt.companyId !== companyId) throw new AccountMismatchError();
    // Older app releases send the token in this field. The authenticated
    // token lookup still binds that legacy request to this exact attempt.
    if (options.attemptId && options.attemptId !== attempt.id &&
        options.attemptId.toLowerCase() !== attempt.appAccountToken.toLowerCase()) {
      throw new ValidationError("Purchase attempt ID does not match app account token");
    }
    if (attempt.productId !== product.id &&
        !(attempt.status === "COMPLETED" && current?.originalTransactionId === payload.originalTransactionId)) {
      throw new ValidationError("Signed product does not match purchase attempt");
    }
  }

  const appleSignedDate = notification?.payload.signedDate ?? signedTimestamp(payload);
  const latestEvent = current ? await transaction.subscriptionEvent.findFirst({
    where: {
      entitlementId: current.id,
      metadata: { path: ['applied'], equals: true },
    },
    orderBy: { effectiveAt: 'desc' },
  }) : null;
  const latestDate = latestEvent?.effectiveAt?.getTime() ?? 0;
  // A refund for a prior renewal period must not revoke the current paid
  // period. Arrival order and originalTransactionId alone cannot establish it.
  const previousPeriod = current?.startsAt &&
    payload.purchaseDate < current.startsAt.getTime() &&
    payload.transactionId !== current.latestTransactionId;
  const stale = Boolean(previousPeriod || appleSignedDate < latestDate || payload.isUpgraded);
  const state = deriveSignedState(payload, notification, current?.isAutoRenewEnabled);
  if (!stale) await assertAndReleasePriorClaim(transaction, userId, payload.originalTransactionId);

  const entitlement = stale && current ? current : await transaction.userEntitlement.upsert({
    where: { userId },
    create: {
      userId, companyId, planId: product.planId, storeProductId: payload.productId,
      originalTransactionId: payload.originalTransactionId, ...state,
    },
    update: {
      planId: product.planId, storeProductId: payload.productId,
      originalTransactionId: payload.originalTransactionId, ...state,
    },
  });

  if (attempt) {
    await transaction.purchaseAttempt.update({
      where: { id: attempt.id },
      data: { status: "COMPLETED", transactionId: payload.transactionId, completedAt: new Date() },
    });
  }

  if (!stale) {
    const grantsAccess = state.status === "PRO_ACTIVE" || state.status === "TRIAL_ACTIVE" ||
      state.status === "CANCELED_ACTIVE" || state.status === "GRACE_PERIOD";
    for (const metricCode of ["AI_GENERATION", "QUOTE_EXPORT"] as const) {
      await transaction.usageBucket.upsert({
        where: { userId_companyId_metricCode_source: {
          userId, companyId, metricCode, source: "PRO_SUBSCRIPTION",
        } },
        create: { userId, companyId, metricCode, includedQuantity: grantsAccess ? 999999 : 0,
          consumedQuantity: 0, resetPolicy: "MONTHLY", source: "PRO_SUBSCRIPTION" },
        update: { includedQuantity: grantsAccess ? 999999 : 0 },
      });
    }
  }

  const event = notification ? null : await transaction.subscriptionEvent.findFirst({
    where: { entitlementId: entitlement.id, transactionId: payload.transactionId,
      eventType: options.eventType, effectiveAt: new Date(appleSignedDate) },
  });
  if (!event) {
    await transaction.subscriptionEvent.create({
      data: {
        entitlementId: entitlement.id, userId, companyId,
        eventType: options.eventType, transactionId: payload.transactionId,
        storeProductId: payload.productId, environment: payload.environment,
        platform: "ios", appAccountToken: payload.appAccountToken ?? null,
        notificationUUID: notification?.payload.notificationUUID,
        effectiveAt: new Date(appleSignedDate),
        metadata: {
          original_transaction_id: payload.originalTransactionId,
          apple_signed_date: appleSignedDate,
          applied: !stale,
          purchase_attempt_id: attempt?.id ?? null,
          plan_code: product.plan.code,
        },
        payloadJson: notification ? {
          notificationType: notification.payload.notificationType,
          subtype: notification.payload.subtype ?? null,
        } : undefined,
      },
    });
  }
}

export async function syncTransaction(
  userId: string,
  companyId: string,
  input: SyncTransactionInput,
): Promise<EntitlementSnapshotDto> {
  const payload = await verifySignedTransactionPayload({
    signedTransaction: input.signed_transaction,
    expectedTransactionId: input.transaction_id,
    expectedOriginalTransactionId: input.original_transaction_id,
    expectedProductId: input.store_product_id,
    expectedAppAccountToken: input.app_account_token,
  });
  // A new purchase always supplies the token to StoreKit. Without its signed
  // echo, an unrelated account could attach a tokenless historical receipt.
  if (!payload.appAccountToken) throw new ValidationError("Signed transaction is missing app account token");
  await prisma.$transaction(async (transaction) => {
    await lockSubscription(transaction, payload.originalTransactionId);
    await applyVerifiedTransaction(transaction, {
      userId, companyId, payload, eventType: payload.offerType === 1 &&
        payload.offerDiscountType === "FREE_TRIAL" ? "TRIAL_STARTED" : "PURCHASED",
      attemptToken: input.app_account_token, attemptId: input.purchase_attempt_id,
    });
  }, { maxWait: 10_000, timeout: 30_000 });
  await invalidateCache(CacheKeys.entitlement(userId));
  return getEffectiveEntitlement(userId, companyId);
}

export async function restorePurchases(
  userId: string,
  companyId: string,
  transactions: RestoreTransactionInput[],
): Promise<EntitlementSnapshotDto> {
  const verified: AppleTransactionInfo[] = [];
  for (const input of transactions) {
    verified.push(await verifySignedTransactionPayload({
      signedTransaction: input.signed_transaction,
      expectedTransactionId: input.transaction_id,
      expectedOriginalTransactionId: input.original_transaction_id,
      expectedProductId: input.store_product_id,
      expectedAppAccountToken: input.app_account_token ?? undefined,
    }));
  }
  // Prefer a current entitled period over a more recently purchased but
  // revoked/expired product, then use Apple's signed purchase chronology.
  verified.sort((a, b) => {
    const active = (item: AppleTransactionInfo) => !item.revocationDate &&
      !item.isUpgraded && item.expiresDate! > Date.now() ? 1 : 0;
    return active(a) - active(b) || a.purchaseDate - b.purchaseDate || signedTimestamp(a) - signedTimestamp(b);
  });
  const payload = verified.at(-1);
  if (payload) {
    await prisma.$transaction(async (transaction) => {
      await lockSubscription(transaction, payload.originalTransactionId);
      await applyVerifiedTransaction(transaction, { userId, companyId, payload, eventType: "RESTORED" });
    }, { maxWait: 10_000, timeout: 30_000 });
    await invalidateCache(CacheKeys.entitlement(userId));
  }
  return getEffectiveEntitlement(userId, companyId);
}

export async function handleAppStoreWebhook(decoded: DecodedAppleNotification): Promise<void> {
  const { transactionInfo: payload, payload: notification } = decoded;
  validateAppleTransaction(payload);
  let affectedUser: string | undefined;
  await prisma.$transaction(async (transaction) => {
    await lockSubscription(transaction, payload.originalTransactionId);
    if (await transaction.subscriptionEvent.findUnique({ where: { notificationUUID: notification.notificationUUID } })) return;
    let entitlement = await transaction.userEntitlement.findFirst({
      where: { originalTransactionId: payload.originalTransactionId },
    });
    let attemptToken: string | undefined;
    if (!entitlement && notification.notificationType === AppleNotificationType.SUBSCRIBED && payload.appAccountToken) {
      const attempt = await transaction.purchaseAttempt.findUnique({ where: { appAccountToken: payload.appAccountToken.toLowerCase() } });
      if (attempt?.status === "PENDING") {
        entitlement = await transaction.userEntitlement.findUnique({ where: { userId: attempt.userId } });
        attemptToken = attempt.appAccountToken;
      }
    }
    if (!entitlement) {
      // Do not acknowledge an otherwise valid unbound subscription as handled.
      // Apple can retry after purchase sync establishes the account binding.
      throw new NotFoundError("UserEntitlement for Apple subscription");
    }
    affectedUser = entitlement.userId;
    await applyVerifiedTransaction(transaction, {
      userId: entitlement.userId, companyId: entitlement.companyId,
      payload, notification: decoded,
      eventType: eventTypeForNotification(notification.notificationType, notification.subtype),
      attemptToken,
    });
  }, { maxWait: 10_000, timeout: 30_000 });
  if (affectedUser) await invalidateCache(CacheKeys.entitlement(affectedUser));
}
