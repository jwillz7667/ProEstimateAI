ALTER TABLE "Invoice" ADD COLUMN "shareToken" TEXT NOT NULL DEFAULT gen_random_uuid()::text;
CREATE UNIQUE INDEX "Invoice_shareToken_key" ON "Invoice"("shareToken");

CREATE TABLE "InvoicePayment" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "invoiceId" TEXT NOT NULL REFERENCES "Invoice"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "companyId" TEXT NOT NULL REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "requestId" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "method" TEXT NOT NULL,
  "reference" TEXT,
  "notes" TEXT,
  "recordedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "providerPaymentId" TEXT
);
CREATE UNIQUE INDEX "InvoicePayment_companyId_requestId_key" ON "InvoicePayment"("companyId", "requestId");
CREATE UNIQUE INDEX "InvoicePayment_providerPaymentId_key" ON "InvoicePayment"("providerPaymentId");
CREATE INDEX "InvoicePayment_invoiceId_createdAt_idx" ON "InvoicePayment"("invoiceId", "createdAt");

-- Preserve pre-ledger totals without inventing when or how historical payments were made.
INSERT INTO "InvoicePayment" ("id", "invoiceId", "companyId", "requestId", "amount", "method")
SELECT 'opening-' || "id", "id", "companyId", 'opening-' || "id", "amountPaid", 'OPENING_BALANCE'
FROM "Invoice" WHERE "amountPaid" > 0;

CREATE TABLE "InvoiceInstallment" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "invoiceId" TEXT NOT NULL REFERENCES "Invoice"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "title" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL CHECK ("amount" > 0),
  "dueDate" TIMESTAMP(3),
  "sortOrder" INTEGER NOT NULL
);
CREATE UNIQUE INDEX "InvoiceInstallment_invoiceId_sortOrder_key" ON "InvoiceInstallment"("invoiceId", "sortOrder");
