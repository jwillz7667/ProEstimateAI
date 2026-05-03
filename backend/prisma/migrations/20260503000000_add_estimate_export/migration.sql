-- Snapshot of a rendered estimate PDF so the contractor can re-download
-- past exports from the project detail screen without regenerating.
-- pdfData is base64-encoded to match the storage shape used by Asset.imageData.

CREATE TABLE "EstimateExport" (
    "id"           TEXT NOT NULL,
    "estimateId"   TEXT NOT NULL,
    "projectId"    TEXT NOT NULL,
    "fileName"     TEXT NOT NULL,
    "contentType"  TEXT NOT NULL DEFAULT 'application/pdf',
    "fileSize"     INTEGER NOT NULL,
    "pdfData"      TEXT NOT NULL,
    "createdAt"    TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EstimateExport_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "EstimateExport_estimateId_idx" ON "EstimateExport"("estimateId");
CREATE INDEX "EstimateExport_projectId_idx" ON "EstimateExport"("projectId");

ALTER TABLE "EstimateExport"
    ADD CONSTRAINT "EstimateExport_estimateId_fkey"
    FOREIGN KEY ("estimateId") REFERENCES "Estimate"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "EstimateExport"
    ADD CONSTRAINT "EstimateExport_projectId_fkey"
    FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE CASCADE ON UPDATE CASCADE;
