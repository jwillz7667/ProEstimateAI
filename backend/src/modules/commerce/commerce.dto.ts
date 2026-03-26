import { SubscriptionProduct, Plan, UserEntitlement, UsageBucket } from '@prisma/client';
import { EntitlementStatus, PlanCode, UsageMetricCode, FeatureCode } from '../../types/enums';

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

/**
 * Derive feature flags from the plan code and current usage buckets.
 *
 * Pro plans unlock everything unconditionally.
 * Free plans gate CAN_GENERATE_PREVIEW and CAN_EXPORT_QUOTE behind
 * remaining starter credits; all other Pro-only flags stay false.
 */
export function deriveFeatureFlags(
  planCode: PlanCode,
  buckets: UsageBucket[],
): FeatureFlagsDto {
  const isPro = planCode === 'PRO_MONTHLY' || planCode === 'PRO_ANNUAL';

  if (isPro) {
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

  // FREE_STARTER: credit-gated features only
  const aiGenBucket = buckets.find((b) => b.metricCode === 'AI_GENERATION');
  const quoteExportBucket = buckets.find((b) => b.metricCode === 'QUOTE_EXPORT');

  const aiRemaining = aiGenBucket
    ? Math.max(0, aiGenBucket.includedQuantity - aiGenBucket.consumedQuantity)
    : 0;
  const quoteRemaining = quoteExportBucket
    ? Math.max(0, quoteExportBucket.includedQuantity - quoteExportBucket.consumedQuantity)
    : 0;

  return {
    CAN_GENERATE_PREVIEW: aiRemaining > 0,
    CAN_EXPORT_QUOTE: quoteRemaining > 0,
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
}

/**
 * Build the canonical entitlement snapshot returned to the iOS client.
 * Combines UserEntitlement + Plan + UsageBucket[] into a single DTO.
 */
export function toEntitlementSnapshotDto(
  entitlement: UserEntitlement & { plan: Plan },
  buckets: UsageBucket[],
): EntitlementSnapshotDto {
  const planCode = entitlement.plan.code as PlanCode;
  const flags = deriveFeatureFlags(planCode, buckets);
  const usageDtos = buckets.map(toUsageBucketDto);

  // Derive billing warning for degraded subscription states
  let billingWarning: string | null = null;
  if (entitlement.status === 'GRACE_PERIOD') {
    billingWarning = 'Your subscription payment failed. Please update your payment method to avoid losing access.';
  } else if (entitlement.status === 'BILLING_RETRY') {
    billingWarning = 'We are retrying your subscription payment. Please ensure your payment method is up to date.';
  } else if (entitlement.status === 'CANCELED_ACTIVE') {
    billingWarning = 'Your subscription has been canceled and will expire at the end of the current billing period.';
  } else if (entitlement.status === 'EXPIRED') {
    billingWarning = 'Your subscription has expired. Upgrade to continue using Pro features.';
  } else if (entitlement.status === 'REVOKED') {
    billingWarning = 'Your subscription has been revoked. Please contact support if you believe this is an error.';
  }

  return {
    subscription_state: entitlement.status,
    current_plan_code: planCode,
    feature_flags: flags,
    usage: usageDtos,
    renewal_date: entitlement.renewalDate ? entitlement.renewalDate.toISOString() : null,
    trial_ends_at: entitlement.trialEndsAt ? entitlement.trialEndsAt.toISOString() : null,
    grace_period_ends_at: entitlement.gracePeriodEndsAt ? entitlement.gracePeriodEndsAt.toISOString() : null,
    is_auto_renew_enabled: entitlement.isAutoRenewEnabled,
    billing_warning: billingWarning,
  };
}

// ─── Purchase Attempt Response ─────────────────────────

export interface PurchaseAttemptResponseDto {
  purchase_attempt_id: string;
  app_account_token: string;
}
