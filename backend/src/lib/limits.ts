/**
 * Free-tier credit limits.
 *
 * Single source of truth for how much "free trial without paying" a brand-new
 * account gets before they hit the paywall. Changing this constant updates:
 *   - `auth.service.ts` (signup) — UsageBucket seed quantity for new accounts.
 *   - `entitlement-gate.ts` — auto-create-on-first-call fallback for legacy
 *     FREE accounts that pre-date the bucket-on-signup change.
 *   - `prisma/seed.ts` — demo free-user starter credits.
 *
 * Keep the iOS side (`AppConstants.freeGenerationCredits`) in sync.
 */
export const FREE_TIER_AI_GENERATION_CREDITS = 5;

/**
 * Source label used on the UsageBucket row that tracks free-tier starter
 * credits. Distinguishes from Pro / Premium plan-included buckets which
 * may live alongside the starter bucket on the same user record.
 */
export const STARTER_CREDITS_SOURCE = "STARTER_CREDITS";
