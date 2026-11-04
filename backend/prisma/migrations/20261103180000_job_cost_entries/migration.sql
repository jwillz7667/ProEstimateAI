CREATE TABLE "JobCostEntry" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "projectId" TEXT NOT NULL REFERENCES "Project"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "requestId" TEXT NOT NULL,
  "payloadHash" TEXT NOT NULL,
  "category" "LineItemCategory" NOT NULL,
  "description" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL CHECK ("amount" > 0),
  "currencyCode" TEXT NOT NULL DEFAULT 'USD',
  "laborHours" DECIMAL(10,2),
  "hourlyRate" DECIMAL(12,2),
  "recordedAt" TIMESTAMP(3) NOT NULL,
  "createdByUserId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "voidedAt" TIMESTAMP(3),
  "receiptData" TEXT,
  "receiptMimeType" TEXT,
  "receiptFilename" TEXT,
  "receiptHash" TEXT
);
CREATE UNIQUE INDEX "JobCostEntry_companyId_requestId_key" ON "JobCostEntry"("companyId", "requestId");
CREATE INDEX "JobCostEntry_companyId_projectId_createdAt_id_idx" ON "JobCostEntry"("companyId", "projectId", "createdAt", "id");
