import type { EntitlementStatus, UserEntitlement } from '@prisma/client';

export type EntitlementAccessRecord = Pick<UserEntitlement,
  'status' | 'trialEndsAt' | 'renewalDate' | 'endsAt' | 'gracePeriodEndsAt'
> & Partial<Pick<UserEntitlement, 'source'>>;

/** Interpret persisted state against its signed deadline, even if a webhook is delayed. */
export function effectiveSubscriptionStatus(
  entitlement: EntitlementAccessRecord,
  now: Date = new Date(),
): EntitlementStatus {
  const { status } = entitlement;
  // Only the explicitly provisioned reviewer grant bypasses an Apple purchase.
  if (status === 'ADMIN_OVERRIDE') return entitlement.source === 'APP_REVIEW_DEMO' ? 'ADMIN_OVERRIDE' : 'EXPIRED';
  if (status === 'FREE' || status === 'REVOKED' || status === 'EXPIRED') {
    return status;
  }
  if (status === 'GRACE_PERIOD' || status === 'BILLING_RETRY') {
    if (entitlement.gracePeriodEndsAt && entitlement.gracePeriodEndsAt > now) {
      return 'GRACE_PERIOD';
    }
    // Billing retry alone is a collection state, not a paid service extension.
    return status === 'BILLING_RETRY' ? 'BILLING_RETRY' : 'EXPIRED';
  }
  const deadline = status === 'TRIAL_ACTIVE'
    ? entitlement.trialEndsAt ?? entitlement.endsAt ?? entitlement.renewalDate
    : entitlement.endsAt ?? entitlement.renewalDate;
  return deadline && deadline > now ? status : 'EXPIRED';
}

export function hasEffectiveProAccess(
  entitlement: EntitlementAccessRecord,
  now: Date = new Date(),
): boolean {
  const status = effectiveSubscriptionStatus(entitlement, now);
  return status === 'ADMIN_OVERRIDE' || status === 'PRO_ACTIVE' ||
    status === 'TRIAL_ACTIVE' || status === 'CANCELED_ACTIVE' || status === 'GRACE_PERIOD';
}
