import { prisma } from "../../config/database";
import type { Prisma } from '@prisma/client';
import { PaywallError, AuthenticationError } from "../../lib/errors";
import { invalidateCache, CacheKeys } from "../../config/redis";
import { isAdminUser } from "../../lib/admin";
import { hasEffectiveProAccess } from "../../lib/entitlement-access";
import {
  checkUsageLimit,
  readEffectivePlanLimits,
  type LimitCheckResult,
  type UsageMetric,
} from "../../lib/usage-limits";
import {
  FREE_TIER_AI_GENERATION_CREDITS,
  STARTER_CREDITS_SOURCE,
} from "../../lib/limits";

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

function buildGenerationLimitHitPaywall(args: {
  included: number;
  consumed: number;
}) {
  return {
    placement: "GENERATION_LIMIT_HIT",
    metric: "AI_GENERATION" as UsageMetric,
    trigger_reason: "Free generation credits exhausted",
    blocking: true,
    headline: "You've Used All 5 Free Generations",
    subheadline:
      "Start a 7-day free trial to keep generating AI previews — unlimited while you trial, then keep going on any paid plan.",
    primary_cta_title: "Start 7-Day Free Trial",
    secondary_cta_title: "Restore Purchases",
    show_continue_free: false,
    show_restore_purchases: true,
    recommended_product_id: "proestimate.pro.monthly",
    available_products: null,
    // Machine-readable counter so the iOS paywall can render
    // "5 of 5 free generations used" without a separate API round-trip.
    included_quantity: args.included,
    consumed_quantity: args.consumed,
    remaining_quantity: 0,
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

export interface UsageReservation {
  eventId: string;
  userId: string;
  starterBucketId?: string;
}

/** Reserve capacity before compute. A user-row lock prevents parallel requests
 * from both consuming the final credit or exceeding a rolling plan cap. */
export async function gateAIAction(
  opts: GateOptions,
  transaction?: Prisma.TransactionClient,
): Promise<UsageReservation | undefined> {
  if (await (transaction ? isAdminUser(opts.userId, transaction) : isAdminUser(opts.userId))) return;
  const reserve = async (tx: Prisma.TransactionClient) => {
    const users = await tx.$queryRaw<
      Array<{ id: string }>
    >`SELECT id FROM "User" WHERE id = ${opts.userId} AND "companyId" = ${opts.companyId} AND "isActive" = true FOR UPDATE`;
    if (users.length !== 1)
      throw new AuthenticationError("Account is unavailable");
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
    let starterBucketId: string | undefined;
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
    } else if (
      entitlement.status === "FREE" &&
      opts.metric === "PROJECT_CREATED"
    ) {
      // Projects are needed to try the core estimating workflow.
    } else if (
      entitlement.status === "FREE" &&
      opts.metric === "AI_GENERATION"
    ) {
      const bucket = await tx.usageBucket.upsert({
        where: {
          userId_companyId_metricCode_source: {
            userId: opts.userId,
            companyId: opts.companyId,
            metricCode: "AI_GENERATION",
            source: STARTER_CREDITS_SOURCE,
          },
        },
        create: {
          userId: opts.userId,
          companyId: opts.companyId,
          metricCode: "AI_GENERATION",
          source: STARTER_CREDITS_SOURCE,
          includedQuantity: FREE_TIER_AI_GENERATION_CREDITS,
        },
        update: {},
      });
      if (bucket.consumedQuantity >= bucket.includedQuantity) {
        throw new PaywallError(
          "You've used all your free AI generation credits.",
          buildGenerationLimitHitPaywall({
            included: bucket.includedQuantity,
            consumed: bucket.consumedQuantity,
          }),
        );
      }
      await tx.usageBucket.update({
        where: { id: bucket.id },
        data: { consumedQuantity: { increment: 1 } },
      });
      starterBucketId = bucket.id;
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
        ...(starterBucketId
          ? {
              metadata: {
                source: STARTER_CREDITS_SOURCE,
                bucket_id: starterBucketId,
              },
            }
          : {}),
      },
    });
    return { eventId: event.id, userId: opts.userId, starterBucketId };
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
