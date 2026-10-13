-- Preserve the rate agreed at invoice creation instead of recalculating past
-- invoices with the company's latest tax setting. Existing invoices retain
-- their effective blended tax rate because historical line rates were not stored.
ALTER TABLE "InvoiceLineItem" ADD COLUMN "taxRate" DECIMAL(5,4) NOT NULL DEFAULT 0;

UPDATE "InvoiceLineItem" AS item
SET "taxRate" = LEAST(1, GREATEST(0, invoice."taxAmount" / invoice."subtotal"))
FROM "Invoice" AS invoice
WHERE item."invoiceId" = invoice.id AND invoice."subtotal" > 0;

-- Recover exact source rates only when an unchanged converted line has one
-- unambiguous matching estimate line. Manually edited/ambiguous lines retain
-- the historical invoice's effective rate from the backfill above.
UPDATE "InvoiceLineItem" AS item
SET "taxRate" = source."taxRate"
FROM "Invoice" AS invoice, "EstimateLineItem" AS source
WHERE item."invoiceId" = invoice.id
  AND source."estimateId" = invoice."estimateId"
  AND source."name" = item."name"
  AND source."sortOrder" = item."sortOrder"
  AND source."quantity" = item."quantity"
  AND source."lineTotal" = item."lineTotal"
  AND (SELECT COUNT(*) FROM "EstimateLineItem" AS match
       WHERE match."estimateId" = invoice."estimateId"
         AND match."name" = item."name"
         AND match."sortOrder" = item."sortOrder"
         AND match."quantity" = item."quantity"
         AND match."lineTotal" = item."lineTotal") = 1;
