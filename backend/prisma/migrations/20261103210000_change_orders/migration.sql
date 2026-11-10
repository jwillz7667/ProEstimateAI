ALTER TABLE "Invoice" ADD COLUMN "creditAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
 ADD COLUMN "rootInvoiceId" TEXT, ADD COLUMN "sourceChangeOrderId" TEXT,
 ADD COLUMN "financialBasisLocked" BOOLEAN NOT NULL DEFAULT false;
CREATE TABLE "ChangeOrder" (
 "id" TEXT PRIMARY KEY, "companyId" TEXT NOT NULL, "projectId" TEXT NOT NULL,
 "rootEstimateId" TEXT NOT NULL, "baseEstimateId" TEXT NOT NULL, "estimateId" TEXT NOT NULL,
 "proposalId" TEXT NOT NULL, "requestId" TEXT NOT NULL, "parentChangeOrderId" TEXT,
 "rootInvoiceId" TEXT, "status" TEXT NOT NULL DEFAULT 'DRAFT', "title" TEXT NOT NULL,
 "reason" TEXT NOT NULL, "baseSnapshot" JSONB NOT NULL, "comparisonSnapshot" JSONB,
 "approvedDocumentHash" TEXT, "appliedAt" TIMESTAMP(3), "createdByUserId" TEXT NOT NULL,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "ChangeOrder_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "ChangeOrder_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "ChangeOrder_baseEstimateId_fkey" FOREIGN KEY ("baseEstimateId") REFERENCES "Estimate"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "ChangeOrder_estimateId_fkey" FOREIGN KEY ("estimateId") REFERENCES "Estimate"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "ChangeOrder_companyId_requestId_key" ON "ChangeOrder"("companyId","requestId");
CREATE UNIQUE INDEX "ChangeOrder_estimateId_key" ON "ChangeOrder"("estimateId");
CREATE UNIQUE INDEX "ChangeOrder_proposalId_key" ON "ChangeOrder"("proposalId");
CREATE INDEX "ChangeOrder_companyId_rootEstimateId_createdAt_idx" ON "ChangeOrder"("companyId","rootEstimateId","createdAt");
CREATE UNIQUE INDEX "Invoice_sourceChangeOrderId_key" ON "Invoice"("sourceChangeOrderId");
ALTER TABLE "Invoice" ADD CONSTRAINT "Invoice_sourceChangeOrderId_fkey" FOREIGN KEY ("sourceChangeOrderId") REFERENCES "ChangeOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE TABLE "CreditNote" (
 "id" TEXT PRIMARY KEY, "companyId" TEXT NOT NULL, "projectId" TEXT NOT NULL,
 "rootEstimateId" TEXT NOT NULL, "sourceChangeOrderId" TEXT NOT NULL,
 "creditNumber" TEXT NOT NULL, "amount" DECIMAL(12,2) NOT NULL,
 "subtotalDelta" DECIMAL(12,2) NOT NULL, "taxDelta" DECIMAL(12,2) NOT NULL,
 "discountDelta" DECIMAL(12,2) NOT NULL, "currencyCode" TEXT NOT NULL DEFAULT 'USD',
 "reason" TEXT NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "CreditNote_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "CreditNote_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "CreditNote_sourceChangeOrderId_fkey" FOREIGN KEY ("sourceChangeOrderId") REFERENCES "ChangeOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "CreditNote_sourceChangeOrderId_key" ON "CreditNote"("sourceChangeOrderId");
CREATE UNIQUE INDEX "CreditNote_companyId_creditNumber_key" ON "CreditNote"("companyId","creditNumber");
CREATE INDEX "CreditNote_companyId_rootEstimateId_createdAt_idx" ON "CreditNote"("companyId","rootEstimateId","createdAt");
CREATE TABLE "CreditAllocation" (
 "id" TEXT PRIMARY KEY, "creditNoteId" TEXT NOT NULL, "invoiceId" TEXT NOT NULL,
 "amount" DECIMAL(12,2) NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "CreditAllocation_creditNoteId_fkey" FOREIGN KEY ("creditNoteId") REFERENCES "CreditNote"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "CreditAllocation_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "Invoice"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "CreditAllocation_creditNoteId_idx" ON "CreditAllocation"("creditNoteId");
CREATE INDEX "CreditAllocation_invoiceId_idx" ON "CreditAllocation"("invoiceId");
CREATE TABLE "ChangeOrderApplyRequest" (
 "id" TEXT PRIMARY KEY, "companyId" TEXT NOT NULL, "requestId" TEXT NOT NULL,
 "changeOrderId" TEXT NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "ChangeOrderApplyRequest_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "ChangeOrderApplyRequest_changeOrderId_fkey" FOREIGN KEY ("changeOrderId") REFERENCES "ChangeOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "ChangeOrderApplyRequest_companyId_requestId_key" ON "ChangeOrderApplyRequest"("companyId","requestId");
ALTER TABLE "CreditNote" ADD CONSTRAINT "CreditNote_positive_amount" CHECK ("amount">0);
ALTER TABLE "CreditAllocation" ADD CONSTRAINT "CreditAllocation_positive_amount" CHECK ("amount">0);
ALTER TABLE "Invoice" ADD CONSTRAINT "Invoice_nonnegative_credit" CHECK ("creditAmount">=0);
-- Issued notes and allocations are audit records; privacy erasure may delete
-- their parent project/company, but no caller may rewrite recorded amounts.
CREATE FUNCTION "rejectCreditAuditUpdate"() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Issued credit records are immutable'; END; $$;
CREATE TRIGGER "CreditNote_immutable_update" BEFORE UPDATE ON "CreditNote" FOR EACH ROW EXECUTE FUNCTION "rejectCreditAuditUpdate"();
CREATE TRIGGER "CreditAllocation_immutable_update" BEFORE UPDATE ON "CreditAllocation" FOR EACH ROW EXECUTE FUNCTION "rejectCreditAuditUpdate"();
