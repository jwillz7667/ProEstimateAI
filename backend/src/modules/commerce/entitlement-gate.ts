import type { EntitlementStatus } from "@prisma/client";
import { prisma } from "../../config/database";
import { PaywallError } from "../../lib/errors";
import { isAdminUser } from "../../lib/admin";
import {
  checkUsageLimit,
  readPlanLimits,
  type LimitCheckResult,
  type UsageMetric,
} from "../../lib/usage-limits";

/**
 * Centralized AI-action gate. Used by every endpoint that triggers paid AI
 * compute (image preview generation, AI estimate generation, etc).
 *
 * Decision tree:
 *   1. Admin user → allow.
 *   2. No entitlement on record → block, treat as "never trialed" (trial offer).
 *   3. Subscription state grants access (trial, pro, grace, retry, cancelled-active,
 *      admin override) → check rolling-window usage caps from the user's plan.
 *      Cap hit → block with USAGE_LIMIT_<window> paywall and reset timestamp.
 *   4. Subscription state does NOT grant access (FREE, EXPIRED, REVOKED) →
 *      block with TRIAL_OFFER if user has never been on a trial, else
 *      SUBSCRIBE_NO_TRIAL.
 *
 * Throws PaywallError on block; returns on allow. Caller is responsible for
 * recording the UsageEvent AFTER the action succeeds.
 */

export interface GateOptions {
  userId: string;
  companyId: string;
  metric: UsageMetric;
}

const PRO_ACCESS_STATES: ReadonlySet<EntitlementStatus> = new Set([
  "TRIAL_ACTIVE",
  "PRO_ACTIVE",
  "GRACE_PERIOD",
  "BILLING_RETRY",
  "CANCELED_ACTIVE",
  "ADMIN_OVERRIDE",
]);

function hasProAccess(status: EntitlementStatus): boolean {
  return PRO_ACCESS_STATES.has(status);
}

function isTrialEligible(args: {
  status: EntitlementStatus;
  trialEndsAt: Date | null;
}): boolean {
  // Trial is single-use. Eligible only if the user has never had one.
  return args.status === "FREE" && args.trialEndsAt === null;
}

function metricNoun(metric: UsageMetric): string {
  switch (metric) {
    case "QUOTE_EXPORT":
      return "AI quote exports";
    case "PROJECT_CREATED":
      return "projects";
    case "ESTIMATE_GENERATED":
      return "AI-generated estimates";
    case "AI_GENERATION":
    default:
      return "AI generations";
  }
}

function metricTriggerReason(
  metric: UsageMetric,
  base: "requires Pro" | "cap reached",
): string {
  switch (metric) {
    case "QUOTE_EXPORT":
      return `AI quote export ${base}`;
    case "PROJECT_CREATED":
      return `Creating projects ${base}`;
    case "ESTIMATE_GENERATED":
      return `AI estimate generation ${base}`;
    case "AI_GENERATION":
    default:
      return `AI generation ${base}`;
  }
}

function buildTrialOfferPaywall(metric: UsageMetric) {
  return {
    placement: "TRIAL_OFFER",
    metric,
    trigger_reason: metricTriggerReason(metric, "requires Pro"),
    blocking: true,
    headline: "Start Your 7-Day Free Trial",
    subheadline: `Unlock ${metricNoun(metric)} and every other Pro feature — free for 7 days.`,
    primary_cta_title: "Start 7-Day Free Trial",
    // No "Maybe Later" / dismiss path. The contractor has to either
    // start a trial, restore an existing purchase, or stay blocked on
    // this action.
    secondary_cta_title: "Restore Purchases",
    show_continue_free: false,
    show_restore_purchases: true,
    recommended_product_id: "proestimate.pro.monthly",
    available_products: null,
  };
}

function buildSubscribeNoTrialPaywall(metric: UsageMetric) {
  return {
    placement: "SUBSCRIBE_NO_TRIAL",
    metric,
    trigger_reason: metricTriggerReason(metric, "requires Pro"),
    blocking: true,
    headline: "Upgrade to Continue",
    subheadline: `Your free trial has ended. Upgrade to keep using ${metricNoun(metric)} and the rest of the app.`,
    primary_cta_title: "Upgrade",
    secondary_cta_title: "Restore Purchases",
    show_continue_free: false,
    show_restore_purchases: true,
    recommended_product_id: "proestimate.pro.monthly",
    available_products: null,
  };
}

function buildUsageLimitPaywall(
  metric: UsageMetric,
  result: Extract<LimitCheckResult, { allowed: false }>,
) {
  const windowLabel = result.window;
  const niceWindow =
    windowLabel === "daily"
      ? "today"
      : windowLabel === "weekly"
        ? "this week"
        : "this month";
  const isExport = metric === "QUOTE_EXPORT";
  const noun = isExport ? "AI quote exports" : "AI generations";

  return {
    placement: `USAGE_LIMIT_${windowLabel.toUpperCase()}`,
    metric,
    trigger_reason: `${windowLabel} ${metric.toLowerCase()} cap reached`,
    blocking: true,
    headline: `You've Hit Your ${windowLabel === "daily" ? "Daily" : windowLabel === "weekly" ? "Weekly" : "Monthly"} Limit`,
    subheadline: `You've used all ${result.cap} ${noun} ${niceWindow}. Capacity reopens at ${result.resetAt.toISOString()}.`,
    primary_cta_title: "OK",
    secondary_cta_title: null,
    show_continue_free: false,
    show_restore_purchases: false,
    recommended_product_id: null,
    available_products: null,
    // Machine-readable fields for the iOS client to render a precise countdown.
    cap: result.cap,
    used: result.used,
    window: result.window,
    reset_at: result.resetAt.toISOString(),
    usage: {
      daily: result.usage.daily,
      weekly: result.usage.weekly,
      monthly: result.usage.monthly,
    },
  };
}

export async function gateAIAction(opts: GateOptions): Promise<void> {
  // 1. Admin bypass.
  if (await isAdminUser(opts.userId)) return;

  // 2. Resolve entitlement + plan.
  const entitlement = await prisma.userEntitlement.findUnique({
    where: { userId: opts.userId },
    include: { plan: true },
  });

  if (!entitlement) {
    // No entitlement means we never bootstrapped commerce for this user — treat
    // as a brand-new account: offer the trial.
    throw new PaywallError(
      "AI features require an active subscription.",
      buildTrialOfferPaywall(opts.metric),
    );
  }

  // 3. Subscribed (or in trial) → check rolling caps.
  if (hasProAccess(entitlement.status)) {
    const limits = readPlanLimits(entitlement.plan.featuresJson, opts.metric);
    // No caps configured → unlimited (e.g., legacy plans).
    if (Object.keys(limits).length === 0) return;

    const result = await checkUsageLimit(opts.userId, opts.metric, limits);
    if (!result.allowed) {
      throw new PaywallError(
        `${result.window} ${opts.metric.toLowerCase()} limit of ${result.cap} reached.`,
        buildUsageLimitPaywall(opts.metric, result),
      );
    }
    return;
  }

  // 4. Free / Expired / Revoked → trial offer if eligible, else subscribe.
  if (
    isTrialEligible({
      status: entitlement.status,
      trialEndsAt: entitlement.trialEndsAt,
    })
  ) {
    throw new PaywallError(
      "AI features require an active subscription.",
      buildTrialOfferPaywall(opts.metric),
    );
  }

  throw new PaywallError(
    "AI features require an active subscription.",
    buildSubscribeNoTrialPaywall(opts.metric),
  );
}
