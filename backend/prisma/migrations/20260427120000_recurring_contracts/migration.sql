-- Recurring service contract terms on Project. Used primarily by
-- LAWN_CARE (B2B / HOA) bids where the contractor sells a 6–12 month
-- mowing/fertilization route stop rather than a one-time install.
--
-- Schema decisions:
--  * `isRecurring` is a bool flag (rather than inferring from a non-null
--    frequency) so a contractor can stage a recurring config without
--    flipping it live, and so non-LAWN_CARE projects can stay
--    explicitly non-recurring.
--  * `recurrenceFrequency` is a free-form text column (not a Postgres
--    enum) because adding new cadences shouldn't require a migration.
--    Application-level Zod validation keeps the values restricted.
--  * `visitsPerMonth` is Decimal(5,2) so quarterly (~0.33) and
--    weekly-with-rain-skips (e.g. 3.7) can be expressed honestly.
--  * `contractMonths` is the headline contract length used for the
--    annual / contract-total roll-up the contractor signs.
--  * `recurrenceStartDate` is when the schedule begins; null until the
--    contractor commits a start date in the wizard.

ALTER TABLE "Project"
  ADD COLUMN "isRecurring" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "recurrenceFrequency" TEXT,
  ADD COLUMN "visitsPerMonth" DECIMAL(5, 2),
  ADD COLUMN "contractMonths" INTEGER,
  ADD COLUMN "recurrenceStartDate" TIMESTAMP(3);
