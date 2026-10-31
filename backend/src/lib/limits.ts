/** New accounts use Apple's eligible three-day subscription trial.
 * Historical starter balances remain stored for audit/refund compatibility,
 * but never authorize paid AI or exports.
 */
export const FREE_TIER_AI_GENERATION_CREDITS = 0;

/**
 * Source label used on the UsageBucket row that tracks free-tier starter
 * credits. Distinguishes from Pro / Premium plan-included buckets which
 * may live alongside the starter bucket on the same user record.
 */
export const STARTER_CREDITS_SOURCE = "STARTER_CREDITS";
