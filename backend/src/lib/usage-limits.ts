import { prisma } from '../config/database';
import type { UsageMetricCode } from '@prisma/client';

/**
 * Rolling-window usage gating. We count UsageEvent rows for a metric over the
 * last 24h / 7d / 30d, compare against per-plan caps, and return either an
 * "allowed" result with current usage, or a "blocked" result naming the window
 * that tripped and the timestamp at which capacity will reopen.
 *
 * The reset timestamp uses true rolling-window semantics: capacity opens when
 * the OLDEST event in the relevant window ages out (not at midnight). This is
 * fairer to users than calendar-aligned resets and trivial to compute.
 */

export type UsageMetric = Extract<UsageMetricCode, 'AI_GENERATION' | 'QUOTE_EXPORT'>;

export interface UsageLimits {
  daily?: number;
  weekly?: number;
  monthly?: number;
}

export interface UsageWindow {
  daily: number;
  weekly: number;
  monthly: number;
}

export interface LimitCheckBlocked {
  allowed: false;
  window: 'daily' | 'weekly' | 'monthly';
  cap: number;
  used: number;
  resetAt: Date;
  caps: UsageLimits;
  usage: UsageWindow;
}

export interface LimitCheckAllowed {
  allowed: true;
  caps: UsageLimits;
  usage: UsageWindow;
}

export type LimitCheckResult = LimitCheckBlocked | LimitCheckAllowed;

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;
const MONTH_MS = 30 * DAY_MS;

/**
 * Pull window-based caps for a given metric out of a Plan.featuresJson blob.
 * Schema convention:
 *   featuresJson.LIMITS = { AI_GENERATION: { daily: 20, weekly: 75, monthly: 200 }, ... }
 * If a plan has no LIMITS block (e.g. legacy FREE_STARTER), returns an empty
 * object — meaning no rolling caps apply and only the entitlement gate matters.
 */
export function readPlanLimits(
  featuresJson: unknown,
  metric: UsageMetric,
): UsageLimits {
  if (!featuresJson || typeof featuresJson !== 'object') return {};
  const limits = (featuresJson as Record<string, unknown>).LIMITS;
  if (!limits || typeof limits !== 'object') return {};
  const perMetric = (limits as Record<string, unknown>)[metric];
  if (!perMetric || typeof perMetric !== 'object') return {};
  const obj = perMetric as Record<string, unknown>;
  const result: UsageLimits = {};
  if (typeof obj.daily === 'number' && obj.daily >= 0) result.daily = obj.daily;
  if (typeof obj.weekly === 'number' && obj.weekly >= 0) result.weekly = obj.weekly;
  if (typeof obj.monthly === 'number' && obj.monthly >= 0) result.monthly = obj.monthly;
  return result;
}

/**
 * Count usage in three rolling windows and compare against caps.
 * Single Prisma query (last 30d) because three separate queries would be wasteful
 * and the windows nest.
 */
export async function checkUsageLimit(
  userId: string,
  metric: UsageMetric,
  limits: UsageLimits,
): Promise<LimitCheckResult> {
  const now = new Date();
  const dayStart = new Date(now.getTime() - DAY_MS);
  const weekStart = new Date(now.getTime() - WEEK_MS);
  const monthStart = new Date(now.getTime() - MONTH_MS);

  const events = await prisma.usageEvent.findMany({
    where: {
      userId,
      metricCode: metric,
      createdAt: { gte: monthStart },
    },
    select: { createdAt: true, quantity: true },
    orderBy: { createdAt: 'asc' },
  });

  let monthly = 0;
  let weekly = 0;
  let daily = 0;
  for (const ev of events) {
    monthly += ev.quantity;
    if (ev.createdAt >= weekStart) weekly += ev.quantity;
    if (ev.createdAt >= dayStart) daily += ev.quantity;
  }

  const usage: UsageWindow = { daily, weekly, monthly };

  // Determine when capacity reopens for a given window: when the OLDEST event
  // still in that window ages out.
  const resetForWindow = (windowStart: Date, windowMs: number): Date => {
    const oldestInWindow = events.find((e) => e.createdAt >= windowStart);
    return oldestInWindow
      ? new Date(oldestInWindow.createdAt.getTime() + windowMs)
      : new Date(now.getTime() + windowMs);
  };

  // Check from strictest (daily) to loosest (monthly). The daily cap will trip
  // first under heavy bursts; the monthly cap catches sustained high-volume users.
  if (limits.daily !== undefined && daily >= limits.daily) {
    return {
      allowed: false,
      window: 'daily',
      cap: limits.daily,
      used: daily,
      resetAt: resetForWindow(dayStart, DAY_MS),
      caps: limits,
      usage,
    };
  }
  if (limits.weekly !== undefined && weekly >= limits.weekly) {
    return {
      allowed: false,
      window: 'weekly',
      cap: limits.weekly,
      used: weekly,
      resetAt: resetForWindow(weekStart, WEEK_MS),
      caps: limits,
      usage,
    };
  }
  if (limits.monthly !== undefined && monthly >= limits.monthly) {
    return {
      allowed: false,
      window: 'monthly',
      cap: limits.monthly,
      used: monthly,
      resetAt: resetForWindow(monthStart, MONTH_MS),
      caps: limits,
      usage,
    };
  }

  return { allowed: true, caps: limits, usage };
}

/**
 * Append a UsageEvent for a metric. Called immediately after a successful AI
 * action (image generation queued, AI estimate generated, etc).
 */
export async function recordUsage(
  userId: string,
  companyId: string,
  metric: UsageMetric,
  metadata?: Record<string, unknown>,
): Promise<void> {
  await prisma.usageEvent.create({
    data: {
      userId,
      companyId,
      metricCode: metric,
      quantity: 1,
      metadata: metadata as never,
    },
  });
}
