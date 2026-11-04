-- Existing pending reservations may already have reached Stripe. Preserve
-- their request identity conservatively rather than inventing attempt history.
ALTER TABLE "StripeMerchant"
  ADD COLUMN "creationStarted" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "creationLeaseId" TEXT,
  ADD COLUMN "creationLeaseExpiresAt" TIMESTAMP(3);

ALTER TABLE "StripeMerchant" ADD CONSTRAINT "StripeMerchant_creation_lease_pair"
  CHECK (("creationLeaseId" IS NULL) = ("creationLeaseExpiresAt" IS NULL));
