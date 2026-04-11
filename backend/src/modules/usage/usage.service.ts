import { UsageMetricCode } from '@prisma/client';
import { prisma } from '../../config/database';
import { NotFoundError, PaywallError } from '../../lib/errors';
import { isAdminUser } from '../../lib/admin';
import { UsageBucketDto, toUsageBucketDto } from './usage.dto';
import { PaywallPlacement } from '../../types/enums';

// Map metric codes to their paywall placements when limits are hit
const METRIC_TO_PLACEMENT: Record<UsageMetricCode, PaywallPlacement> = {
  AI_GENERATION: 'GENERATION_LIMIT_HIT',
  QUOTE_EXPORT: 'QUOTE_LIMIT_HIT',
};

// Human-readable labels for paywall error messages
const METRIC_LABELS: Record<UsageMetricCode, string> = {
  AI_GENERATION: 'AI generation',
  QUOTE_EXPORT: 'quote export',
};

/**
 * Return all usage buckets for the authenticated user as DTOs.
 */
export async function getUsageSummary(
  userId: string,
  companyId: string,
): Promise<UsageBucketDto[]> {
  const buckets = await prisma.usageBucket.findMany({
    where: { userId, companyId },
    orderBy: { metricCode: 'asc' },
  });

  return buckets.map(toUsageBucketDto);
}

/**
 * Atomically check whether the user has remaining credits for the given
 * metric and, if so, consume one unit.
 *
 * Returns the updated bucket DTO on success.
 * Throws PaywallError when the bucket is exhausted.
 */
export async function checkAndConsume(
  userId: string,
  companyId: string,
  metricCode: UsageMetricCode,
): Promise<UsageBucketDto> {
  // Admin users have unlimited access — return a synthetic unlimited bucket
  if (await isAdminUser(userId)) {
    return {
      metric_code: metricCode,
      included_quantity: 999999,
      consumed_quantity: 0,
      remaining_quantity: 999999,
      source: 'ADMIN',
    };
  }

  // Use a Prisma transaction with serializable isolation to prevent
  // double-spend race conditions on concurrent requests.
  const result = await prisma.$transaction(async (tx) => {
    // Find all buckets for this metric, prefer STARTER_CREDITS first (consume free credits before Pro)
    const buckets = await tx.usageBucket.findMany({
      where: { userId, metricCode },
      orderBy: { source: 'asc' }, // STARTER_CREDITS < PRO_SUBSCRIPTION alphabetically
    });

    // Find the first bucket with remaining credits
    const bucket = buckets.find(
      (b) => b.includedQuantity - b.consumedQuantity > 0,
    ) ?? buckets[0];

    if (!bucket) {
      throw new NotFoundError('UsageBucket', `${userId}/${metricCode}`);
    }

    const remaining = bucket.includedQuantity - bucket.consumedQuantity;

    if (remaining <= 0) {
      const placement = METRIC_TO_PLACEMENT[metricCode];
      const label = METRIC_LABELS[metricCode];

      // Sum across all buckets for accurate reporting
      const totalIncluded = buckets.reduce((s, b) => s + b.includedQuantity, 0);
      const totalConsumed = buckets.reduce((s, b) => s + b.consumedQuantity, 0);

      throw new PaywallError(
        `You have used all your free ${label} credits. Upgrade to Pro for unlimited access.`,
        {
          placement,
          metric_code: metricCode,
          included_quantity: totalIncluded,
          consumed_quantity: totalConsumed,
          remaining_quantity: 0,
        },
      );
    }

    // Atomically increment consumed quantity on the chosen bucket
    const updated = await tx.usageBucket.update({
      where: { id: bucket.id },
      data: { consumedQuantity: { increment: 1 } },
    });

    // Record the usage event for audit trail / analytics
    await tx.usageEvent.create({
      data: {
        userId,
        companyId,
        metricCode,
        quantity: 1,
        metadata: {
          bucket_id: bucket.id,
          consumed_before: bucket.consumedQuantity,
          consumed_after: bucket.consumedQuantity + 1,
        },
      },
    });

    return updated;
  });

  return toUsageBucketDto(result);
}
