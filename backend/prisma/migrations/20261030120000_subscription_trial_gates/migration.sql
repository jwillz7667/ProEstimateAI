-- Catalog policy only: preserve user subscriptions, signed trial deadlines,
-- purchase history, historical usage and any existing starter-credit balances.
BEGIN;

UPDATE "SubscriptionProduct"
SET "hasIntroOffer" = true,
    "introOfferDisplayText" = '3-day free trial'
WHERE "storeProductId" IN ('proestimate.pro.monthly', 'proestimate.pro.annual');

UPDATE "SubscriptionProduct"
SET "description" = 'AI previews within plan limits, invoicing, and branding'
WHERE "storeProductId" = 'proestimate.pro.monthly';

UPDATE "Plan"
SET "description" = 'AI previews and estimates within plan limits, branding, and invoicing'
WHERE "code" = 'PRO_MONTHLY';

-- Saving a manual project is not a subscription feature or billable AI action.
UPDATE "Plan"
SET "featuresJson" = jsonb_set(
  "featuresJson", '{LIMITS}', ("featuresJson"->'LIMITS') - 'PROJECT_CREATED'
)
WHERE jsonb_typeof("featuresJson"->'LIMITS') = 'object'
  AND ("featuresJson"->'LIMITS') ? 'PROJECT_CREATED';

UPDATE "Plan"
SET "featuresJson" = jsonb_set(jsonb_set("featuresJson",
  '{CAN_GENERATE_PREVIEW}', 'false'), '{CAN_EXPORT_QUOTE}', 'false')
WHERE "code" = 'FREE_STARTER' AND jsonb_typeof("featuresJson") = 'object';

COMMIT;
