-- Persist additional Company-level settings so user customizations survive
-- across sessions and devices.
--
--  * defaultTaxRate widened from Decimal(5,4) to Decimal(6,3). The previous
--    precision capped values at 9.9999, which clashed with the iOS client
--    sending percentage values like 8.25. Existing rows are preserved.
--  * taxInclusivePricing — toggle that controls whether prices shown to
--    clients include tax in the displayed amount.
--  * appearanceMode — per-account theme preference (system/light/dark) so
--    the visual mode follows the user across devices.

ALTER TABLE "Company"
  ALTER COLUMN "defaultTaxRate" TYPE DECIMAL(6, 3);

ALTER TABLE "Company"
  ADD COLUMN "taxInclusivePricing" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "Company"
  ADD COLUMN "appearanceMode" TEXT DEFAULT 'system';
