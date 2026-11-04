CREATE TABLE "EstimateRevisionRequest" (
  "id" TEXT NOT NULL PRIMARY KEY, "companyId" TEXT NOT NULL, "requestId" TEXT NOT NULL,
  "sourceEstimateId" TEXT, "revisionEstimateId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "EstimateRevisionRequest_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "EstimateRevisionRequest_sourceEstimateId_fkey" FOREIGN KEY ("sourceEstimateId") REFERENCES "Estimate"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "EstimateRevisionRequest_revisionEstimateId_fkey" FOREIGN KEY ("revisionEstimateId") REFERENCES "Estimate"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "EstimateRevisionRequest_companyId_requestId_key" ON "EstimateRevisionRequest"("companyId", "requestId");
CREATE INDEX "EstimateRevisionRequest_sourceEstimateId_idx" ON "EstimateRevisionRequest"("sourceEstimateId");
CREATE INDEX "EstimateRevisionRequest_revisionEstimateId_idx" ON "EstimateRevisionRequest"("revisionEstimateId");
INSERT INTO "EstimateRevisionRequest" ("id", "companyId", "requestId", "sourceEstimateId", "revisionEstimateId", "createdAt")
SELECT 'legacy-revision-' || id, "companyId", "revisionRequestId", "revisesEstimateId", id, "createdAt"
FROM "Estimate" WHERE "revisionRequestId" IS NOT NULL;
