-- AlterEnum
ALTER TYPE "EntitlementStatus" ADD VALUE 'ADMIN_OVERRIDE';

-- AlterEnum
ALTER TYPE "SubscriptionEventType" ADD VALUE 'INITIAL_PURCHASE';
ALTER TYPE "SubscriptionEventType" ADD VALUE 'GRACE_PERIOD_ENTERED';
ALTER TYPE "SubscriptionEventType" ADD VALUE 'GRACE_PERIOD_RECOVERED';
ALTER TYPE "SubscriptionEventType" ADD VALUE 'BILLING_RETRY_ENTERED';
ALTER TYPE "SubscriptionEventType" ADD VALUE 'AUTO_RENEW_DISABLED';
ALTER TYPE "SubscriptionEventType" ADD VALUE 'AUTO_RENEW_ENABLED';
ALTER TYPE "SubscriptionEventType" ADD VALUE 'REFUNDED';
ALTER TYPE "SubscriptionEventType" ADD VALUE 'PRODUCT_CHANGED';

-- DropIndex
DROP INDEX "UsageBucket_userId_metricCode_key";

-- AlterTable
ALTER TABLE "ActivityLogEntry" ADD COLUMN     "companyId" TEXT,
ADD COLUMN     "entityId" TEXT,
ADD COLUMN     "entityType" TEXT,
ADD COLUMN     "metadataJson" JSONB,
ALTER COLUMN "projectId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "Company" ADD COLUMN     "defaultLanguage" TEXT DEFAULT 'en',
ADD COLUMN     "nextProposalNumber" INTEGER NOT NULL DEFAULT 1001,
ADD COLUMN     "proposalPrefix" TEXT DEFAULT 'PROP',
ADD COLUMN     "taxLabel" TEXT DEFAULT 'Tax',
ADD COLUMN     "timezone" TEXT DEFAULT 'America/New_York',
ADD COLUMN     "websiteUrl" TEXT;

-- AlterTable
ALTER TABLE "Estimate" ADD COLUMN     "assumptions" TEXT,
ADD COLUMN     "contingencyAmount" DECIMAL(12,2),
ADD COLUMN     "createdByUserId" TEXT,
ADD COLUMN     "exclusions" TEXT,
ADD COLUMN     "pricingProfileId" TEXT,
ADD COLUMN     "title" TEXT;

-- AlterTable
ALTER TABLE "EstimateLineItem" ADD COLUMN     "itemType" TEXT DEFAULT 'per_unit',
ADD COLUMN     "parentLineItemId" TEXT,
ADD COLUMN     "sourceMaterialSuggestionId" TEXT;

-- AlterTable
ALTER TABLE "Invoice" ADD COLUMN     "currencyCode" TEXT DEFAULT 'USD',
ADD COLUMN     "discountAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN     "issuedDate" TIMESTAMP(3),
ADD COLUMN     "paymentInstructions" TEXT,
ADD COLUMN     "proposalId" TEXT;

-- AlterTable
ALTER TABLE "LaborRateRule" ADD COLUMN     "flatRate" DECIMAL(10,2),
ADD COLUMN     "rateType" TEXT NOT NULL DEFAULT 'hourly',
ADD COLUMN     "unit" TEXT,
ADD COLUMN     "unitRate" DECIMAL(10,2);

-- AlterTable
ALTER TABLE "Proposal" ADD COLUMN     "footerText" TEXT,
ADD COLUMN     "introText" TEXT,
ADD COLUMN     "pdfAssetId" TEXT,
ADD COLUMN     "proposalNumber" TEXT,
ADD COLUMN     "scopeOfWork" TEXT,
ADD COLUMN     "timelineText" TEXT,
ADD COLUMN     "title" TEXT;

-- AlterTable
ALTER TABLE "SubscriptionEvent" ADD COLUMN     "appAccountToken" TEXT,
ADD COLUMN     "companyId" TEXT,
ADD COLUMN     "effectiveAt" TIMESTAMP(3),
ADD COLUMN     "payloadJson" JSONB,
ADD COLUMN     "platform" TEXT,
ADD COLUMN     "userId" TEXT;

-- AlterTable
ALTER TABLE "UserEntitlement" ADD COLUMN     "endsAt" TIMESTAMP(3),
ADD COLUMN     "environment" TEXT,
ADD COLUMN     "latestTransactionId" TEXT,
ADD COLUMN     "source" TEXT,
ADD COLUMN     "startsAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "UserIdentity" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "providerUserId" TEXT NOT NULL,
    "email" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserIdentity_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "UserIdentity_userId_idx" ON "UserIdentity"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "UserIdentity_provider_providerUserId_key" ON "UserIdentity"("provider", "providerUserId");

-- CreateIndex
CREATE INDEX "ActivityLogEntry_companyId_idx" ON "ActivityLogEntry"("companyId");

-- CreateIndex
CREATE INDEX "EstimateLineItem_parentLineItemId_idx" ON "EstimateLineItem"("parentLineItemId");

-- CreateIndex
CREATE INDEX "SubscriptionEvent_transactionId_idx" ON "SubscriptionEvent"("transactionId");

-- CreateIndex
CREATE UNIQUE INDEX "UsageBucket_userId_companyId_metricCode_source_key" ON "UsageBucket"("userId", "companyId", "metricCode", "source");

-- AddForeignKey
ALTER TABLE "EstimateLineItem" ADD CONSTRAINT "EstimateLineItem_parentLineItemId_fkey" FOREIGN KEY ("parentLineItemId") REFERENCES "EstimateLineItem"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserIdentity" ADD CONSTRAINT "UserIdentity_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
