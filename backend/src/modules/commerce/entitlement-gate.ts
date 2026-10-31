import { prisma } from "../../config/database";
import type { Prisma } from '@prisma/client';
import { PaywallError, AuthenticationError } from "../../lib/errors";
import { invalidateCache, CacheKeys } from "../../config/redis";
import { hasEffectiveProAccess } from "../../lib/entitlement-access";
import {
  checkUsageLimit,
  readEffectivePlanLimits,
  type LimitCheckResult,
  type UsageMetric,
} from "../../lib/usage-limits";

/** Reserve billable AI/export capacity only for a verified active entitlement.
 * Manual project creation is free. Historical starter balances never authorize
 * new compute; explicit review overrides still use the normal finite plan caps.
 */

export interface GateOptions {
  userId: string;
  companyId: string;
  metric: UsageMetric;
}

function isTrialEligible(args: {
  status: string;
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
    headline: "Try Pro Free for 3 Days",
    subheadline: `Eligible subscribers can try ${metricNoun(metric)} and Pro features free for 3 days. Apple confirms trial eligibility before purchase.`,
    primary_cta_title: "View Pro Plans",
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
    subheadline: `Subscribe or restore an existing purchase to use ${metricNoun(metric)}. Your projects and manual tools remain available.`,
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
  const noun = metricNoun(metric);

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

export interface UsageReservation {
  eventId: string;
  userId: string;
  starterBucketId?: string;
}

/** Reserve capacity before compute. A user-row lock prevents parallel requests
 * from exceeding the remaining rolling plan capacity. */
export async function gateAIAction(
  opts: GateOptions,
  transaction?: Prisma.TransactionClient,
): Promise<UsageReservation | undefined> {
  const reserve = async (tx: Prisma.TransactionClient) => {
    const users = await tx.$queryRaw<
      Array<{ id: string }>
    >`SELECT id FROM "User" WHERE id = ${opts.userId} AND "companyId" = ${opts.companyId} AND "isActive" = true FOR UPDATE`;
    if (users.length !== 1)
      throw new AuthenticationError("Account is unavailable");
    // A manual save must not depend on subscription state or spend AI capacity.
    if (opts.metric === "PROJECT_CREATED") return undefined;
    const entitlement = await tx.userEntitlement.findUnique({
      where: { userId: opts.userId },
      include: { plan: true },
    });
    if (!entitlement || entitlement.companyId !== opts.companyId) {
      throw new PaywallError(
        "AI features require an active subscription.",
        buildTrialOfferPaywall(opts.metric),
      );
    }
    if (hasEffectiveProAccess(entitlement)) {
      const result = await checkUsageLimit(
        opts.userId,
        opts.metric,
        readEffectivePlanLimits(entitlement.plan.featuresJson, entitlement.plan.code, opts.metric),
        tx,
      );
      if (!result.allowed)
        throw new PaywallError(
          `${result.window} ${opts.metric.toLowerCase()} limit of ${result.cap} reached.`,
          buildUsageLimitPaywall(opts.metric, result),
        );
    } else {
      throw new PaywallError(
        "AI features require an active subscription.",
        isTrialEligible(entitlement)
          ? buildTrialOfferPaywall(opts.metric)
          : buildSubscribeNoTrialPaywall(opts.metric),
      );
    }
    const event = await tx.usageEvent.create({
      data: {
        userId: opts.userId,
        companyId: opts.companyId,
        metricCode: opts.metric,
        quantity: 1,
      },
    });
    return { eventId: event.id, userId: opts.userId };
  };
  const reservation = transaction ? await reserve(transaction) : await prisma.$transaction(reserve);
  // A caller-owned transaction invalidates after committing its larger action.
  if (!transaction) await invalidateCache(CacheKeys.entitlement(opts.userId));
  return reservation;
}

/** Release a failed reservation once. Successful actions retain exactly one event. */
export async function runReservedAction<T>(
  reservation: UsageReservation | undefined,
  action: () => Promise<T>,
): Promise<T> {
  try {
    return await action();
  } catch (error) {
    if (reservation) {
      await prisma.$transaction(async (tx) => {
        const released = await tx.usageEvent.deleteMany({
          where: { id: reservation.eventId, quantity: { gt: 0 } },
        });
        if (released.count === 1 && reservation.starterBucketId) {
          await tx.usageBucket.updateMany({
            where: {
              id: reservation.starterBucketId,
              consumedQuantity: { gt: 0 },
            },
            data: { consumedQuantity: { decrement: 1 } },
          });
        }
      });
      await invalidateCache(CacheKeys.entitlement(reservation.userId));
    }
    throw error;
  }
}
