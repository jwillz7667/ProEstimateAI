import type { Plan, UsageBucket, UserEntitlement } from '@prisma/client';
import { prisma } from '../config/database';
import { STARTER_CREDITS_SOURCE } from './limits';
import { hasEffectiveProAccess } from './entitlement-access';
import { readEffectivePlanLimits, type UsageMetric } from './usage-limits';
import { toUsageBucketDto, type UsageBucketDto } from '../modules/commerce/commerce.dto';

const METRICS: readonly UsageMetric[] = [
  'AI_GENERATION', 'QUOTE_EXPORT', 'PROJECT_CREATED', 'ESTIMATE_GENERATED',
];

/** Canonical counters use the same usage ledger and caps as the action gate. */
export async function getEntitlementUsageSnapshot(
  userId: string,
  companyId: string,
  entitlement: UserEntitlement & { plan: Plan },
  buckets: UsageBucket[],
): Promise<UsageBucketDto[]> {
  if (!hasEffectiveProAccess(entitlement)) {
    if (entitlement.status !== 'FREE') return [];
    return buckets
      .filter((bucket) => bucket.source === STARTER_CREDITS_SOURCE)
      .map(toUsageBucketDto);
  }

  const events = await prisma.usageEvent.groupBy({
    by: ['metricCode'],
    where: { userId, companyId, createdAt: { gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) } },
    _sum: { quantity: true },
  });
  return METRICS.map((metric) => {
    const included = readEffectivePlanLimits(entitlement.plan.featuresJson, entitlement.plan.code, metric).monthly ?? 0;
    const consumed = events.find((event) => event.metricCode === metric)?._sum.quantity ?? 0;
    return {
      metric_code: metric,
      included_quantity: included,
      consumed_quantity: consumed,
      remaining_quantity: Math.max(0, included - consumed),
      source: 'PRO_SUBSCRIPTION',
    };
  });
}
