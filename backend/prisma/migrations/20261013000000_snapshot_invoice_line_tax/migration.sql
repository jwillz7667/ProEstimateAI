-- Preserve the rate agreed at invoice creation instead of recalculating past
-- invoices with the company's latest tax setting. Existing invoices retain
-- their effective blended tax rate because historical line rates were not stored.
ALTER TABLE "InvoiceLineItem" ADD COLUMN "taxRate" DECIMAL(5,4) NOT NULL DEFAULT 0;

UPDATE "InvoiceLineItem" AS item
SET "taxRate" = LEAST(1, GREATEST(0, invoice."taxAmount" / invoice."subtotal"))
FROM "Invoice" AS invoice
WHERE item."invoiceId" = invoice.id AND invoice."subtotal" > 0;

-- Recover exact source rates only if the entire source distribution reproduces
-- the historical bill and the source estimate has not changed since invoicing.
-- A matching name/quantity/total alone cannot establish a historical tax rate.
WITH source_matches AS (
  SELECT item.id, item."invoiceId", item."lineTotal",
         COUNT(source.id) AS source_count,
         MIN(source."taxRate") AS source_tax_rate
  FROM "InvoiceLineItem" AS item
  JOIN "Invoice" AS invoice ON item."invoiceId" = invoice.id
  LEFT JOIN "EstimateLineItem" AS source
    ON source."estimateId" = invoice."estimateId"
   AND source."name" = item."name"
   AND source."sortOrder" = item."sortOrder"
   AND source."quantity" = item."quantity"
   AND source."unit" = item."unit"
   AND source."lineTotal" = item."lineTotal"
  GROUP BY item.id, item."invoiceId", item."lineTotal"
), safe_invoices AS (
  SELECT matches."invoiceId"
  FROM source_matches AS matches
  JOIN "Invoice" AS invoice ON matches."invoiceId" = invoice.id
  JOIN "Estimate" AS source_estimate ON source_estimate.id = invoice."estimateId"
  WHERE source_estimate."updatedAt" <= invoice."createdAt"
  GROUP BY matches."invoiceId", invoice."subtotal", invoice."taxAmount"
  HAVING BOOL_AND(matches.source_count = 1)
     AND ROUND(SUM(matches."lineTotal"), 2) = invoice."subtotal"
     AND ROUND(SUM(matches."lineTotal" * matches.source_tax_rate), 2) = invoice."taxAmount"
)
UPDATE "InvoiceLineItem" AS item
SET "taxRate" = matches.source_tax_rate
FROM source_matches AS matches
JOIN safe_invoices AS safe ON safe."invoiceId" = matches."invoiceId"
WHERE item.id = matches.id;
