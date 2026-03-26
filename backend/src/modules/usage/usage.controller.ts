import { Request, Response } from 'express';
import { UsageMetricCode } from '@prisma/client';
import { sendSuccess } from '../../lib/envelope';
import { getEffectiveEntitlement } from '../commerce/commerce.service';
import * as usageService from './usage.service';

/**
 * GET /usage
 * Returns the full entitlement snapshot (reuses commerce EntitlementService)
 * so the iOS client has feature flags + usage in one call.
 */
export async function getSummary(req: Request, res: Response) {
  const snapshot = await getEffectiveEntitlement(req.userId!, req.companyId!);
  sendSuccess(res, snapshot);
}

/**
 * POST /usage/check
 * Atomically consume one unit of the given metric.
 * Returns the updated usage bucket on success.
 * Throws PaywallError (402) when credits are exhausted.
 */
export async function check(req: Request, res: Response) {
  const metricCode = req.body.metric_code as UsageMetricCode;

  const updatedBucket = await usageService.checkAndConsume(
    req.userId!,
    req.companyId!,
    metricCode,
  );

  sendSuccess(res, updatedBucket);
}
