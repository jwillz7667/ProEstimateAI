import type { RequestHandler } from 'express';
import { prisma } from '../config/database';
import { PaywallError } from '../lib/errors';
import { getEffectiveEntitlement } from '../modules/commerce/commerce.service';
import type { FeatureFlagsDto } from '../modules/commerce/commerce.dto';
import type { PaywallPlacement } from '../types/enums';

function paidFeatureGate(
  feature: keyof FeatureFlagsDto | undefined,
  placement: PaywallPlacement,
  label: string,
): RequestHandler {
  return async (req, _res, next) => {
    try {
      const snapshot = await getEffectiveEntitlement(req.userId!, req.companyId!);
      const paid = ['PRO_ACTIVE', 'TRIAL_ACTIVE', 'CANCELED_ACTIVE', 'GRACE_PERIOD', 'ADMIN_OVERRIDE'].includes(snapshot.subscription_state);
      if (!paid || (feature && !snapshot.feature_flags[feature])) {
        throw new PaywallError(`${label} requires an active subscription`, {
          placement, blocking: true, trigger_reason: `${label} requires an active subscription`,
          headline: `${label} Requires Pro`, subheadline: 'Subscribe or restore an existing purchase to continue.',
          primary_cta_title: 'View Plans', secondary_cta_title: 'Restore Purchases',
          show_continue_free: false, show_restore_purchases: true,
          recommended_product_id: 'proestimate.pro.monthly', available_products: null,
        });
      }
      next();
    } catch (error) { next(error); }
  };
}

export const requireApprovalShareAccess = paidFeatureGate('CAN_SHARE_APPROVAL_LINK', 'APPROVAL_SHARE_LOCKED', 'Client approval links');
export const requireBrandingAccess = paidFeatureGate('CAN_USE_BRANDING', 'BRANDING_LOCKED', 'Custom branding');
// Matches FeatureGateCoordinator.guardUseMaps() in the existing iOS product.
export const requireMapsAccess = paidFeatureGate(undefined, 'GENERATION_LIMIT_HIT', 'Property maps');

/** Ordinary company details remain editable; unchanged/default colors are safe. */
export const requireBrandingForCompanyChanges: RequestHandler = async (req, res, next) => {
  try {
    const current = await prisma.company.findUnique({
      where: { id: req.companyId! },
      select: { logoUrl: true, primaryColor: true, secondaryColor: true },
    });
    if (!current) { next(); return; }
    const fields = [
      ['logo_url', 'logoUrl'], ['primary_color', 'primaryColor'], ['secondary_color', 'secondaryColor'],
    ] as const;
    const changesBranding = fields.some(([wireName, modelName]) => {
      const value: unknown = req.body[wireName];
      if (typeof value !== 'string' || value.length === 0) return false;
      return wireName === 'logo_url' ? value !== current[modelName]
        : value.toLowerCase() !== current[modelName]?.toLowerCase();
    });
    if (changesBranding) { await requireBrandingAccess(req, res, next); return; }
    next();
  } catch (error) { next(error); }
};
