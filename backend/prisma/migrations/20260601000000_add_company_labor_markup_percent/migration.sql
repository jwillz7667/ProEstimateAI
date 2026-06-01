-- Add a per-company labor markup percentage, distinct from defaultMarkupPercent
-- (which governs materials). Nullable so existing rows fall back to the
-- platform default (25%) until a contractor sets their own.
ALTER TABLE "Company" ADD COLUMN "laborMarkupPercent" DECIMAL(5,2);
