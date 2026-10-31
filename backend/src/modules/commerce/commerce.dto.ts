import { SubscriptionProduct, Plan, UserEntitlement, UsageBucket } from '@prisma/client';
import type { PlanCode } from '../../types/enums';
import { effectiveSubscriptionStatus, hasEffectiveProAccess } from '../../lib/entitlement-access';

// ─── Store Product DTO ─────────────────────────────────

export interface StoreProductDto {
  product_id: string;
  plan_code: string;
  display_name: string;
  description: string;
  price_display: string;
  billing_period_label: string;
  has_intro_offer: boolean;
  intro_offer_display_text: string | null;
  is_eligible_for_intro_offer: boolean | null;
  is_featured: boolean;
  savings_text: string | null;
}

export function toStoreProductDto(
  product: SubscriptionProduct & { plan: Plan },
): StoreProductDto {
  return {
    product_id: product.storeProductId,
    plan_code: product.plan.code,
    display_name: product.displayName,
    description: product.description,
    price_display: product.priceDisplay,
    billing_period_label: product.billingPeriodLabel,
    has_intro_offer: product.hasIntroOffer,
    intro_offer_display_text: product.introOfferDisplayText,
    // Eligibility is determined client-side via StoreKit 2; backend returns null
    is_eligible_for_intro_offer: null,
    is_featured: product.isFeatured,
    savings_text: product.savingsText,
  };
}

// ─── Usage Bucket DTO ──────────────────────────────────

export interface UsageBucketDto {
  metric_code: string;
  included_quantity: number;
  consumed_quantity: number;
  remaining_quantity: number;
  source: string;
}

export function toUsageBucketDto(bucket: UsageBucket): UsageBucketDto {
  const remaining = Math.max(0, bucket.includedQuantity - bucket.consumedQuantity);
  return {
    metric_code: bucket.metricCode,
    included_quantity: bucket.includedQuantity,
    consumed_quantity: bucket.consumedQuantity,
    remaining_quantity: remaining,
    source: bucket.source,
  };
}

// ─── Feature Flags ─────────────────────────────────────

export interface FeatureFlagsDto {
  CAN_GENERATE_PREVIEW: boolean;
  CAN_EXPORT_QUOTE: boolean;
  CAN_REMOVE_WATERMARK: boolean;
  CAN_USE_BRANDING: boolean;
  CAN_CREATE_INVOICE: boolean;
  CAN_SHARE_APPROVAL_LINK: boolean;
  CAN_EXPORT_MATERIAL_LINKS: boolean;
  CAN_USE_HIGH_RES_PREVIEW: boolean;
}

/** Paid flags require an effective subscription; historical credits do not grant access. */
export function deriveFeatureFlags(
  planCode: PlanCode,
  _buckets: UsageBucket[],
): FeatureFlagsDto {
  // Premium is retired and is no longer offered or served (the products
  // endpoint filters it out), but any legacy/sandbox Premium entitlement
  // stays grandfathered with full Pro access here — Premium must never
  // resolve to fewer features than Pro. Explicit allow-list rather than
  // `!== 'FREE_STARTER'` so an unexpected or corrupt plan code denies by
  // default instead of over-granting paid access.
  const isPaid =
    planCode === 'PRO_MONTHLY' ||
    planCode === 'PRO_ANNUAL' ||
    planCode === 'PREMIUM_MONTHLY' ||
    planCode === 'PREMIUM_ANNUAL';

  if (isPaid) {
    return {
      CAN_GENERATE_PREVIEW: true,
      CAN_EXPORT_QUOTE: true,
      CAN_REMOVE_WATERMARK: true,
      CAN_USE_BRANDING: true,
      CAN_CREATE_INVOICE: true,
      CAN_SHARE_APPROVAL_LINK: true,
      CAN_EXPORT_MATERIAL_LINKS: true,
      CAN_USE_HIGH_RES_PREVIEW: true,
    };
  }

  return {
    CAN_GENERATE_PREVIEW: false,
    CAN_EXPORT_QUOTE: false,
    CAN_REMOVE_WATERMARK: false,
    CAN_USE_BRANDING: false,
    CAN_CREATE_INVOICE: false,
    CAN_SHARE_APPROVAL_LINK: false,
    CAN_EXPORT_MATERIAL_LINKS: false,
    CAN_USE_HIGH_RES_PREVIEW: false,
  };
}

// ─── Entitlement Snapshot DTO ──────────────────────────

export interface EntitlementSnapshotDto {
  subscription_state: string;
  current_plan_code: string;
  feature_flags: FeatureFlagsDto;
  usage: UsageBucketDto[];
  renewal_date: string | null;
  trial_ends_at: string | null;
  grace_period_ends_at: string | null;
  is_auto_renew_enabled: boolean | null;
  billing_warning: string | null;
  starts_at: string | null;
  ends_at: string | null;
  source: string | null;
  latest_transaction_id: string | null;
  environment: string | null;
}

/**
 * Build the canonical entitlement snapshot returned to the iOS client.
 * Combines UserEntitlement + Plan + UsageBucket[] into a single DTO.
 */
export function toEntitlementSnapshotDto(
  entitlement: UserEntitlement & { plan: Plan },
  buckets: UsageBucket[],
  effectiveUsage?: UsageBucketDto[],
): EntitlementSnapshotDto {
  const planCode = entitlement.plan.code as PlanCode;
  const effectiveStatus = effectiveSubscriptionStatus(entitlement);
  const hasPaidAccess = hasEffectiveProAccess(entitlement);
  const flags = hasPaidAccess
    ? deriveFeatureFlags(planCode, buckets)
    : deriveFeatureFlags('FREE_STARTER', []);
  if (hasPaidAccess && typeof entitlement.plan.featuresJson === 'object' &&
    entitlement.plan.featuresJson !== null && !Array.isArray(entitlement.plan.featuresJson)) {
    // Plan-specific feature restrictions apply consistently to API and UI.
    for (const feature of Object.keys(flags) as Array<keyof FeatureFlagsDto>) {
      if (entitlement.plan.featuresJson[feature] === false) flags[feature] = false;
    }
  }
  const usageDtos = effectiveUsage ?? buckets
    .filter(() => hasPaidAccess)
    .map(toUsageBucketDto);

  // Derive billing warning for degraded subscription states
  let billingWarning: string | null = null;
  if (effectiveStatus === 'GRACE_PERIOD') {
    billingWarning = 'Your subscription payment failed. Please update your payment method to avoid losing access.';
  } else if (effectiveStatus === 'BILLING_RETRY') {
    billingWarning = 'We are retrying your subscription payment. Please ensure your payment method is up to date.';
  } else if (effectiveStatus === 'CANCELED_ACTIVE') {
    billingWarning = 'Your subscription has been canceled and will expire at the end of the current billing period.';
  } else if (effectiveStatus === 'EXPIRED') {
    billingWarning = 'Your subscription has expired. Upgrade to continue using Pro features.';
  } else if (effectiveStatus === 'REVOKED') {
    billingWarning = 'Your subscription has been revoked. Please contact support if you believe this is an error.';
  }

  return {
    subscription_state: effectiveStatus,
    current_plan_code: planCode,
    feature_flags: flags,
    usage: usageDtos,
    renewal_date: entitlement.renewalDate ? entitlement.renewalDate.toISOString() : null,
    trial_ends_at: entitlement.trialEndsAt ? entitlement.trialEndsAt.toISOString() : null,
    grace_period_ends_at: entitlement.gracePeriodEndsAt ? entitlement.gracePeriodEndsAt.toISOString() : null,
    is_auto_renew_enabled: entitlement.isAutoRenewEnabled,
    billing_warning: billingWarning,
    starts_at: entitlement.startsAt?.toISOString() ?? null,
    ends_at: entitlement.endsAt?.toISOString() ?? null,
    source: entitlement.source ?? null,
    latest_transaction_id: entitlement.latestTransactionId ?? null,
    environment: entitlement.environment ?? null,
  };
}

// ─── Purchase Attempt Response ─────────────────────────

export interface PurchaseAttemptResponseDto {
  purchase_attempt_id: string;
  app_account_token: string;
}
