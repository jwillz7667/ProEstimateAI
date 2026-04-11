import { prisma } from '../../config/database';
import { NotFoundError, ValidationError } from '../../lib/errors';
import { v4 as uuidv4 } from 'uuid';
import { isAdminUser } from '../../lib/admin';
import { logger } from '../../config/logger';
import {
  DecodedAppleNotification,
  AppleNotificationType,
  AppleNotificationSubtype,
} from '../../lib/apple-storekit';
import {
  StoreProductDto,
  toStoreProductDto,
  EntitlementSnapshotDto,
  toEntitlementSnapshotDto,
  PurchaseAttemptResponseDto,
  ADMIN_ENTITLEMENT_SNAPSHOT,
} from './commerce.dto';
import {
  SyncTransactionInput,
  RestoreTransactionInput,
} from './commerce.validators';

// ─── Entitlement Service ───────────────────────────────

export async function getEffectiveEntitlement(
  userId: string,
  companyId: string,
): Promise<EntitlementSnapshotDto> {
  // Admin users get full Pro access without a real subscription
  if (await isAdminUser(userId)) {
    return ADMIN_ENTITLEMENT_SNAPSHOT;
  }

  // Fetch entitlement with plan in a single query
  const entitlement = await prisma.userEntitlement.findUnique({
    where: { userId },
    include: { plan: true },
  });

  if (!entitlement) {
    throw new NotFoundError('UserEntitlement');
  }

  // Fetch all usage buckets for this user
  const buckets = await prisma.usageBucket.findMany({
    where: { userId, companyId },
  });

  return toEntitlementSnapshotDto(entitlement, buckets);
}

// ─── Commerce Product Service ──────────────────────────

export async function getProducts(): Promise<StoreProductDto[]> {
  const products = await prisma.subscriptionProduct.findMany({
    include: { plan: true },
    orderBy: { sortOrder: 'asc' },
  });

  return products.map(toStoreProductDto);
}

// ─── Purchase Attempt Service ──────────────────────────

export async function createPurchaseAttempt(
  userId: string,
  companyId: string,
  productId: string,
  placement?: string,
): Promise<PurchaseAttemptResponseDto> {
  // Verify the product exists
  const product = await prisma.subscriptionProduct.findUnique({
    where: { storeProductId: productId },
  });

  if (!product) {
    throw new NotFoundError('SubscriptionProduct', productId);
  }

  // Generate a unique app account token for StoreKit 2 purchase tracking
  const appAccountToken = uuidv4();

  const attempt = await prisma.purchaseAttempt.create({
    data: {
      userId,
      companyId,
      productId: product.id,
      placement: placement ?? null,
      appAccountToken,
      status: 'PENDING',
    },
  });

  return {
    purchase_attempt_id: attempt.id,
    app_account_token: attempt.appAccountToken,
  };
}

// ─── Commerce Sync Service ─────────────────────────────

export async function syncTransaction(
  userId: string,
  companyId: string,
  input: SyncTransactionInput,
): Promise<EntitlementSnapshotDto> {
  // 1. Find and verify the purchase attempt by app account token
  const attempt = await prisma.purchaseAttempt.findUnique({
    where: { appAccountToken: input.app_account_token },
  });

  if (!attempt) {
    throw new NotFoundError('PurchaseAttempt');
  }

  if (attempt.userId !== userId) {
    throw new ValidationError('Purchase attempt does not belong to this user');
  }

  // Idempotency: if already completed, return current snapshot
  if (attempt.status === 'COMPLETED') {
    return getEffectiveEntitlement(userId, companyId);
  }

  // 2. Find the subscription product by store product ID
  const product = await prisma.subscriptionProduct.findUnique({
    where: { storeProductId: input.store_product_id },
    include: { plan: true },
  });

  if (!product) {
    throw new NotFoundError('SubscriptionProduct', input.store_product_id);
  }

  const planCode = product.plan.code;
  const now = new Date();

  // 3. Determine new entitlement status and dates
  let newStatus: 'TRIAL_ACTIVE' | 'PRO_ACTIVE';
  let trialEndsAt: Date | null = null;
  let renewalDate: Date;

  if (product.hasIntroOffer) {
    // Product has a 7-day free trial intro offer
    newStatus = 'TRIAL_ACTIVE';
    trialEndsAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    renewalDate = trialEndsAt;
  } else {
    newStatus = 'PRO_ACTIVE';
    // Set renewal date based on billing period
    if (product.billingPeriodLabel === 'month') {
      renewalDate = new Date(now);
      renewalDate.setMonth(renewalDate.getMonth() + 1);
    } else {
      // Annual
      renewalDate = new Date(now);
      renewalDate.setFullYear(renewalDate.getFullYear() + 1);
    }
  }

  // 4. Execute all state changes atomically in a transaction
  const result = await prisma.$transaction(async (tx) => {
    // Update purchase attempt to COMPLETED
    await tx.purchaseAttempt.update({
      where: { id: attempt.id },
      data: {
        status: 'COMPLETED',
        transactionId: input.transaction_id,
        completedAt: now,
      },
    });

    // Upsert the user entitlement
    const entitlement = await tx.userEntitlement.upsert({
      where: { userId },
      create: {
        userId,
        companyId,
        planId: product.planId,
        status: newStatus,
        storeProductId: input.store_product_id,
        originalTransactionId: input.original_transaction_id,
        renewalDate,
        trialEndsAt,
        gracePeriodEndsAt: null,
        isAutoRenewEnabled: true,
      },
      update: {
        planId: product.planId,
        status: newStatus,
        storeProductId: input.store_product_id,
        originalTransactionId: input.original_transaction_id,
        renewalDate,
        trialEndsAt,
        gracePeriodEndsAt: null,
        isAutoRenewEnabled: true,
      },
      include: { plan: true },
    });

    // Create subscription event
    const eventType = product.hasIntroOffer ? 'TRIAL_STARTED' : 'PURCHASED';
    await tx.subscriptionEvent.create({
      data: {
        entitlementId: entitlement.id,
        eventType,
        storeProductId: input.store_product_id,
        transactionId: input.transaction_id,
        environment: input.environment,
        metadata: {
          original_transaction_id: input.original_transaction_id,
          purchase_attempt_id: input.purchase_attempt_id,
          plan_code: planCode,
        },
      },
    });

    // Upgrade usage buckets to Pro limits (effectively unlimited)
    const PRO_INCLUDED_QUANTITY = 999999;

    await tx.usageBucket.upsert({
      where: {
        userId_companyId_metricCode_source: {
          userId, companyId, metricCode: 'AI_GENERATION', source: 'PRO_SUBSCRIPTION',
        },
      },
      create: {
        userId,
        companyId,
        metricCode: 'AI_GENERATION',
        includedQuantity: PRO_INCLUDED_QUANTITY,
        consumedQuantity: 0,
        resetPolicy: 'MONTHLY',
        source: 'PRO_SUBSCRIPTION',
      },
      update: {
        includedQuantity: PRO_INCLUDED_QUANTITY,
      },
    });

    await tx.usageBucket.upsert({
      where: {
        userId_companyId_metricCode_source: {
          userId, companyId, metricCode: 'QUOTE_EXPORT', source: 'PRO_SUBSCRIPTION',
        },
      },
      create: {
        userId,
        companyId,
        metricCode: 'QUOTE_EXPORT',
        includedQuantity: PRO_INCLUDED_QUANTITY,
        consumedQuantity: 0,
        resetPolicy: 'MONTHLY',
        source: 'PRO_SUBSCRIPTION',
      },
      update: {
        includedQuantity: PRO_INCLUDED_QUANTITY,
      },
    });

    // Fetch the updated buckets for the snapshot
    const buckets = await tx.usageBucket.findMany({
      where: { userId, companyId },
    });

    return { entitlement, buckets };
  });

  return toEntitlementSnapshotDto(result.entitlement, result.buckets);
}

export async function restorePurchases(
  userId: string,
  companyId: string,
  transactions: RestoreTransactionInput[],
): Promise<EntitlementSnapshotDto> {
  if (transactions.length === 0) {
    return getEffectiveEntitlement(userId, companyId);
  }

  // Process the most recent transaction (last in the array, which is typically
  // the latest from the StoreKit 2 transaction history).
  const latestTx = transactions[transactions.length - 1];

  // Find the subscription product to determine what they are restoring
  const product = await prisma.subscriptionProduct.findUnique({
    where: { storeProductId: latestTx.store_product_id },
    include: { plan: true },
  });

  if (!product) {
    throw new NotFoundError('SubscriptionProduct', latestTx.store_product_id);
  }

  const now = new Date();
  const planCode = product.plan.code;

  // For restores, assume an active Pro subscription (non-trial)
  let renewalDate: Date;
  if (product.billingPeriodLabel === 'month') {
    renewalDate = new Date(now);
    renewalDate.setMonth(renewalDate.getMonth() + 1);
  } else {
    renewalDate = new Date(now);
    renewalDate.setFullYear(renewalDate.getFullYear() + 1);
  }

  const PRO_INCLUDED_QUANTITY = 999999;

  const result = await prisma.$transaction(async (tx) => {
    // Upsert entitlement to PRO_ACTIVE for a restore
    const entitlement = await tx.userEntitlement.upsert({
      where: { userId },
      create: {
        userId,
        companyId,
        planId: product.planId,
        status: 'PRO_ACTIVE',
        storeProductId: latestTx.store_product_id,
        originalTransactionId: latestTx.original_transaction_id,
        renewalDate,
        trialEndsAt: null,
        gracePeriodEndsAt: null,
        isAutoRenewEnabled: true,
      },
      update: {
        planId: product.planId,
        status: 'PRO_ACTIVE',
        storeProductId: latestTx.store_product_id,
        originalTransactionId: latestTx.original_transaction_id,
        renewalDate,
        trialEndsAt: null,
        gracePeriodEndsAt: null,
        isAutoRenewEnabled: true,
      },
      include: { plan: true },
    });

    // Create RESTORED subscription event
    await tx.subscriptionEvent.create({
      data: {
        entitlementId: entitlement.id,
        eventType: 'RESTORED',
        storeProductId: latestTx.store_product_id,
        transactionId: latestTx.transaction_id,
        environment: latestTx.environment,
        metadata: {
          original_transaction_id: latestTx.original_transaction_id,
          plan_code: planCode,
          restored_transactions_count: transactions.length,
        },
      },
    });

    // Upgrade usage buckets to Pro limits
    await tx.usageBucket.upsert({
      where: {
        userId_companyId_metricCode_source: {
          userId, companyId, metricCode: 'AI_GENERATION', source: 'PRO_SUBSCRIPTION',
        },
      },
      create: {
        userId,
        companyId,
        metricCode: 'AI_GENERATION',
        includedQuantity: PRO_INCLUDED_QUANTITY,
        consumedQuantity: 0,
        resetPolicy: 'MONTHLY',
        source: 'PRO_SUBSCRIPTION',
      },
      update: {
        includedQuantity: PRO_INCLUDED_QUANTITY,
      },
    });

    await tx.usageBucket.upsert({
      where: {
        userId_companyId_metricCode_source: {
          userId, companyId, metricCode: 'QUOTE_EXPORT', source: 'PRO_SUBSCRIPTION',
        },
      },
      create: {
        userId,
        companyId,
        metricCode: 'QUOTE_EXPORT',
        includedQuantity: PRO_INCLUDED_QUANTITY,
        consumedQuantity: 0,
        resetPolicy: 'MONTHLY',
        source: 'PRO_SUBSCRIPTION',
      },
      update: {
        includedQuantity: PRO_INCLUDED_QUANTITY,
      },
    });

    const buckets = await tx.usageBucket.findMany({
      where: { userId, companyId },
    });

    return { entitlement, buckets };
  });

  return toEntitlementSnapshotDto(result.entitlement, result.buckets);
}

// ─── App Store Webhook Handler ────────────────────────

export async function handleAppStoreWebhook(
  decoded: DecodedAppleNotification,
): Promise<void> {
  const { payload, transactionInfo, renewalInfo } = decoded;
  const { notificationType, subtype } = payload;
  const { originalTransactionId, transactionId, productId, appAccountToken, environment } = transactionInfo;

  const entitlement = await prisma.userEntitlement.findFirst({
    where: { originalTransactionId },
    include: { plan: true },
  });

  if (!entitlement) {
    if (appAccountToken) {
      const attempt = await prisma.purchaseAttempt.findFirst({
        where: { appAccountToken },
      });
      if (attempt) {
        logger.warn(
          { originalTransactionId, appAccountToken, notificationType },
          'Found purchase attempt but no entitlement — notification arrived before sync',
        );
      }
    }
    logger.warn({ originalTransactionId, notificationType }, 'No entitlement for App Store notification — skipping');
    return;
  }

  const eventType = mapNotificationToEventType(notificationType, subtype);

  // Idempotency: skip if we already processed this transactionId + eventType
  const existingEvent = await prisma.subscriptionEvent.findFirst({
    where: { entitlementId: entitlement.id, transactionId, eventType },
  });
  if (existingEvent) {
    logger.info({ transactionId, notificationType }, 'Duplicate App Store notification — already processed');
    return;
  }

  const statusUpdate = mapNotificationToStatus(notificationType, subtype, renewalInfo);

  await prisma.$transaction(async (tx) => {
    if (statusUpdate.status) {
      const updateData: Record<string, unknown> = {
        status: statusUpdate.status,
        latestTransactionId: transactionId,
        environment,
      };
      if (statusUpdate.renewalDate) updateData.renewalDate = statusUpdate.renewalDate;
      if (statusUpdate.gracePeriodEndsAt !== undefined) updateData.gracePeriodEndsAt = statusUpdate.gracePeriodEndsAt;
      if (statusUpdate.isAutoRenewEnabled !== undefined) updateData.isAutoRenewEnabled = statusUpdate.isAutoRenewEnabled;
      if (statusUpdate.endsAt) updateData.endsAt = statusUpdate.endsAt;

      await tx.userEntitlement.update({ where: { id: entitlement.id }, data: updateData });
    }

    await tx.subscriptionEvent.create({
      data: {
        entitlementId: entitlement.id,
        userId: entitlement.userId,
        companyId: entitlement.companyId,
        eventType,
        storeProductId: productId,
        transactionId,
        environment,
        platform: 'ios',
        appAccountToken: appAccountToken ?? null,
        effectiveAt: new Date(),
        payloadJson: { notificationType, subtype: subtype ?? null, notificationUUID: payload.notificationUUID },
        metadata: { originalTransactionId, auto_renew_status: renewalInfo?.autoRenewStatus, expiration_intent: renewalInfo?.expirationIntent },
      },
    });
  });

  logger.info(
    { entitlementId: entitlement.id, userId: entitlement.userId, notificationType, subtype, newStatus: statusUpdate.status, eventType },
    'App Store webhook processed — entitlement updated',
  );
}

type WebhookEventType = 'PURCHASED' | 'INITIAL_PURCHASE' | 'RENEWED' | 'TRIAL_STARTED' | 'TRIAL_CONVERTED' | 'CANCELED' | 'EXPIRED' | 'GRACE_PERIOD_ENTERED' | 'GRACE_PERIOD_RECOVERED' | 'BILLING_RETRY_ENTERED' | 'REVOKED' | 'RESTORED' | 'AUTO_RENEW_DISABLED' | 'AUTO_RENEW_ENABLED' | 'REFUNDED' | 'PRODUCT_CHANGED';

function mapNotificationToEventType(notificationType: string, subtype?: string): WebhookEventType {
  switch (notificationType) {
    case AppleNotificationType.SUBSCRIBED:
      return subtype === AppleNotificationSubtype.INITIAL_BUY ? 'INITIAL_PURCHASE' : 'PURCHASED';
    case AppleNotificationType.DID_RENEW:
      return subtype === AppleNotificationSubtype.BILLING_RECOVERY ? 'GRACE_PERIOD_RECOVERED' : 'RENEWED';
    case AppleNotificationType.DID_FAIL_TO_RENEW:
      return subtype === AppleNotificationSubtype.GRACE_PERIOD ? 'GRACE_PERIOD_ENTERED' : 'BILLING_RETRY_ENTERED';
    case AppleNotificationType.EXPIRED:
      return 'EXPIRED';
    case AppleNotificationType.REVOKE:
      return 'REVOKED';
    case AppleNotificationType.REFUND:
      return 'REFUNDED';
    case AppleNotificationType.DID_CHANGE_RENEWAL_STATUS:
      return subtype === AppleNotificationSubtype.AUTO_RENEW_DISABLED ? 'AUTO_RENEW_DISABLED' : 'AUTO_RENEW_ENABLED';
    case AppleNotificationType.DID_CHANGE_RENEWAL_PREF:
      return 'PRODUCT_CHANGED';
    default:
      return 'PURCHASED';
  }
}

interface StatusUpdate {
  status: string | null;
  renewalDate?: Date;
  gracePeriodEndsAt?: Date | null;
  isAutoRenewEnabled?: boolean;
  endsAt?: Date;
}

function mapNotificationToStatus(
  notificationType: string,
  subtype?: string,
  renewalInfo?: { autoRenewStatus: number; renewalDate?: number; gracePeriodExpiresDate?: number } | null,
): StatusUpdate {
  switch (notificationType) {
    case AppleNotificationType.SUBSCRIBED:
      return { status: 'PRO_ACTIVE', gracePeriodEndsAt: null };
    case AppleNotificationType.DID_RENEW:
      return {
        status: 'PRO_ACTIVE',
        renewalDate: renewalInfo?.renewalDate ? new Date(renewalInfo.renewalDate) : undefined,
        gracePeriodEndsAt: null, isAutoRenewEnabled: true,
      };
    case AppleNotificationType.DID_FAIL_TO_RENEW:
      if (subtype === AppleNotificationSubtype.GRACE_PERIOD) {
        return { status: 'GRACE_PERIOD', gracePeriodEndsAt: renewalInfo?.gracePeriodExpiresDate ? new Date(renewalInfo.gracePeriodExpiresDate) : null };
      }
      return { status: 'BILLING_RETRY' };
    case AppleNotificationType.EXPIRED:
    case AppleNotificationType.GRACE_PERIOD_EXPIRED:
      return { status: 'EXPIRED', endsAt: new Date(), gracePeriodEndsAt: null };
    case AppleNotificationType.REVOKE:
    case AppleNotificationType.REFUND:
      return { status: 'REVOKED', endsAt: new Date() };
    case AppleNotificationType.DID_CHANGE_RENEWAL_STATUS:
      if (subtype === AppleNotificationSubtype.AUTO_RENEW_DISABLED) return { status: 'CANCELED_ACTIVE', isAutoRenewEnabled: false };
      return { status: 'PRO_ACTIVE', isAutoRenewEnabled: true };
    default:
      return { status: null };
  }
}
