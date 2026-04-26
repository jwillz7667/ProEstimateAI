-- Update Plan.featuresJson with the new monetization model:
--   * FREE_STARTER  → no AI access at all (any AI call routes to TRIAL_OFFER paywall).
--   * PRO_MONTHLY   → unlimited AI features within rolling daily/weekly/monthly caps.
--   * PRO_ANNUAL    → same as Pro Monthly.
--
-- Caps are stored in featuresJson.LIMITS so they can be tuned without a code deploy.
-- The entitlement gate (`backend/src/modules/commerce/entitlement-gate.ts`) reads
-- these and the rolling-window check in `backend/src/lib/usage-limits.ts` enforces.

UPDATE "Plan"
SET "featuresJson" = jsonb_build_object(
  'CAN_GENERATE_PREVIEW',       false,
  'CAN_EXPORT_QUOTE',           false,
  'CAN_REMOVE_WATERMARK',       false,
  'CAN_USE_BRANDING',           false,
  'CAN_CREATE_INVOICE',         false,
  'CAN_SHARE_APPROVAL_LINK',    false,
  'CAN_EXPORT_MATERIAL_LINKS',  false,
  'CAN_USE_HIGH_RES_PREVIEW',   false
)
WHERE "code" = 'FREE_STARTER';

UPDATE "Plan"
SET "featuresJson" = jsonb_build_object(
  'CAN_GENERATE_PREVIEW',       true,
  'CAN_EXPORT_QUOTE',           true,
  'CAN_REMOVE_WATERMARK',       true,
  'CAN_USE_BRANDING',           true,
  'CAN_CREATE_INVOICE',         true,
  'CAN_SHARE_APPROVAL_LINK',    true,
  'CAN_EXPORT_MATERIAL_LINKS',  true,
  'CAN_USE_HIGH_RES_PREVIEW',   true,
  'LIMITS', jsonb_build_object(
    'AI_GENERATION', jsonb_build_object('daily', 20, 'weekly', 75,  'monthly', 200),
    'QUOTE_EXPORT',  jsonb_build_object('daily', 30, 'weekly', 150, 'monthly', 400)
  )
)
WHERE "code" IN ('PRO_MONTHLY', 'PRO_ANNUAL');
