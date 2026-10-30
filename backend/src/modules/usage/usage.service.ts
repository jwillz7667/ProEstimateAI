import type { UsageMetricCode } from '@prisma/client';
import type { UsageBucketDto } from './usage.dto';
import { getEffectiveEntitlement } from '../commerce/commerce.service';
import { gateAIAction, runReservedAction } from '../commerce/entitlement-gate';

export async function getUsageSummary(
  userId: string,
  companyId: string,
): Promise<UsageBucketDto[]> {
  return (await getEffectiveEntitlement(userId, companyId)).usage;
}

/** Use the same atomic subscription and rolling-cap gate as the compute routes. */
export async function checkAndConsume(
  userId: string,
  companyId: string,
  metricCode: UsageMetricCode,
): Promise<UsageBucketDto> {
  const reservation = await gateAIAction({ userId, companyId, metric: metricCode });
  return runReservedAction(reservation, async () => {
    const snapshot = await getEffectiveEntitlement(userId, companyId);
    return snapshot.usage.find((bucket) => bucket.metric_code === metricCode) ?? {
      metric_code: metricCode,
      included_quantity: 0,
      consumed_quantity: 0,
      remaining_quantity: 0,
      source: 'PRO_SUBSCRIPTION',
    };
  });
}
