-- Account trials are independent of signed Apple subscription dates. Existing
-- users receive their full seven days on their next entitlement refresh.
ALTER TABLE "UserEntitlement"
  ADD COLUMN "accountTrialStartedAt" TIMESTAMP(3),
  ADD COLUMN "accountTrialEndsAt" TIMESTAMP(3),
  ADD CONSTRAINT "UserEntitlement_account_trial_dates_check" CHECK (
    ("accountTrialStartedAt" IS NULL AND "accountTrialEndsAt" IS NULL) OR
    ("accountTrialStartedAt" IS NOT NULL AND "accountTrialEndsAt" IS NOT NULL AND
     "accountTrialEndsAt" = "accountTrialStartedAt" + INTERVAL '7 days')
  );

UPDATE "SubscriptionProduct"
SET "introOfferDisplayText" = '7-day free trial'
WHERE "storeProductId" IN ('proestimate.pro.monthly', 'proestimate.pro.annual');
