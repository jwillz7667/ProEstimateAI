import { UsageBucket } from '@prisma/client';

export interface UsageBucketDto {
  metric_code: string;
  included_quantity: number;
  consumed_quantity: number;
  remaining_quantity: number;
  source: string;
}

export function toUsageBucketDto(bucket: UsageBucket): UsageBucketDto {
  const remaining = Math.max(0, bucket.includedQuantity - bucket.consumedQuantity);
  return {
    metric_code: bucket.metricCode,
    included_quantity: bucket.includedQuantity,
    consumed_quantity: bucket.consumedQuantity,
    remaining_quantity: remaining,
    source: bucket.source,
  };
}
