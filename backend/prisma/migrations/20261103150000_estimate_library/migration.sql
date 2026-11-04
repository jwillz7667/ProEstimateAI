CREATE TABLE "EstimateTemplate" (
  "id" TEXT NOT NULL, "companyId" TEXT NOT NULL, "name" TEXT NOT NULL,
  "description" TEXT, "projectType" "ProjectType" NOT NULL DEFAULT 'CUSTOM',
  "snapshotJson" JSONB NOT NULL, "itemCount" INTEGER NOT NULL,
  "totalAmount" DECIMAL(12,2) NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "EstimateTemplate_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "EstimateTemplate_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE TABLE "SavedEstimateItem" (
  "id" TEXT NOT NULL, "companyId" TEXT NOT NULL,
  "category" "LineItemCategory" NOT NULL DEFAULT 'MATERIALS', "name" TEXT NOT NULL,
  "description" TEXT, "quantity" DECIMAL(10,2) NOT NULL, "unit" TEXT NOT NULL,
  "unitCost" DECIMAL(12,2) NOT NULL, "markupPercent" DECIMAL(5,2) NOT NULL DEFAULT 0,
  "taxRate" DECIMAL(5,4) NOT NULL DEFAULT 0, "itemType" TEXT DEFAULT 'per_unit',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SavedEstimateItem_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SavedEstimateItem_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE TABLE "EstimateLibraryOperation" (
  "id" TEXT NOT NULL, "companyId" TEXT NOT NULL, "requestId" TEXT NOT NULL,
  "operation" TEXT NOT NULL, "payloadHash" TEXT NOT NULL, "resultId" TEXT NOT NULL,
  "proposalDefaults" JSONB, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "EstimateLibraryOperation_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "EstimateLibraryOperation_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "EstimateTemplate_companyId_createdAt_id_idx" ON "EstimateTemplate"("companyId", "createdAt", "id");
CREATE INDEX "SavedEstimateItem_companyId_createdAt_id_idx" ON "SavedEstimateItem"("companyId", "createdAt", "id");
CREATE UNIQUE INDEX "EstimateLibraryOperation_companyId_requestId_key" ON "EstimateLibraryOperation"("companyId", "requestId");
CREATE INDEX "EstimateLibraryOperation_companyId_resultId_idx" ON "EstimateLibraryOperation"("companyId", "resultId");
