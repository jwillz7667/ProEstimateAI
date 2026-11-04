ALTER TABLE "EstimateLineItem"
  ALTER COLUMN "markupPercent" TYPE DECIMAL(7,2),
  ADD COLUMN "priceOrigin" TEXT NOT NULL DEFAULT 'UNSPECIFIED',
  ADD COLUMN "priceSourceLabel" TEXT,
  ADD COLUMN "priceSourceUrl" TEXT,
  ADD COLUMN "priceCheckedAt" TIMESTAMP(3),
  ADD COLUMN "priceCheckedByUserId" TEXT,
  ADD COLUMN "quantityBasis" TEXT,
  ADD COLUMN "quantityCheckedAt" TIMESTAMP(3);
UPDATE "EstimateLineItem" SET "priceOrigin" = 'AI_SUGGESTED' WHERE "sourceMaterialSuggestionId" IS NOT NULL;
ALTER TABLE "SavedEstimateItem" ALTER COLUMN "markupPercent" TYPE DECIMAL(7,2);
