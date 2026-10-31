import type { EntitlementStatus } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { effectiveSubscriptionStatus, hasEffectiveProAccess, type EntitlementAccessRecord } from './entitlement-access';

const now = new Date('2026-10-30T12:00:00Z');
const past = new Date(now.getTime() - 1);
const future = new Date(now.getTime() + 60_000);
const record = (status: EntitlementStatus, overrides: Partial<EntitlementAccessRecord> = {}): EntitlementAccessRecord => ({
  status, endsAt: future, renewalDate: future, trialEndsAt: null, gracePeriodEndsAt: null, ...overrides,
});

describe('effective subscription access', () => {
  it.each(['PRO_ACTIVE', 'CANCELED_ACTIVE', 'TRIAL_ACTIVE'] as const)('expires %s locally when its signed period ends', (status) => {
    const entitlement = record(status, { endsAt: past, renewalDate: past, trialEndsAt: status === 'TRIAL_ACTIVE' ? past : null });
    expect(effectiveSubscriptionStatus(entitlement, now)).toBe('EXPIRED');
    expect(hasEffectiveProAccess(entitlement, now)).toBe(false);
  });

  it('requires a signed deadline or an explicit reviewer grant', () => {
    const undated = record('PRO_ACTIVE', { endsAt: null, renewalDate: null });
    expect(hasEffectiveProAccess(undated, now)).toBe(false);
    expect(hasEffectiveProAccess({ ...undated, status: 'ADMIN_OVERRIDE' }, now)).toBe(false);
    expect(hasEffectiveProAccess({ ...undated, status: 'ADMIN_OVERRIDE', source: 'APP_REVIEW_DEMO' }, now)).toBe(true);
  });

  it('grants a real grace period and denies billing retry without one', () => {
    expect(hasEffectiveProAccess(record('BILLING_RETRY'), now)).toBe(false);
    expect(hasEffectiveProAccess(record('BILLING_RETRY', { gracePeriodEndsAt: future }), now)).toBe(true);
    expect(effectiveSubscriptionStatus(record('BILLING_RETRY', { gracePeriodEndsAt: future }), now)).toBe('GRACE_PERIOD');
    expect(hasEffectiveProAccess(record('GRACE_PERIOD', { gracePeriodEndsAt: past }), now)).toBe(false);
  });

  it.each(['FREE', 'EXPIRED', 'REVOKED'] as const)('never turns %s into paid access because dates remain in the future', (status) => {
    expect(hasEffectiveProAccess(record(status), now)).toBe(false);
  });
});
