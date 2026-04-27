-- Expand the catalog of supported project types and capture per-property
-- measurements that downstream prompts consume to ground AI estimates.
--
-- New project types:
--   * LANDSCAPING — one-time install jobs (planting, hardscape, irrigation).
--   * LAWN_CARE   — recurring B2B/HOA contracts (mow, fertilize, aerate).
--
-- New Project columns:
--   * lawnAreaSqFt / roofAreaSqFt   — measured square footage from MapKit
--                                     polygons or Google Solar API segments.
--   * propertyLatitude/Longitude    — geocoded lat/lng. Stored once so we
--                                     don't re-geocode on every supplier
--                                     search or maps fetch.
--
-- New MaterialSuggestion column:
--   * supplierSearchQuery           — retailer-friendly query string the
--                                     iOS client deep-links into Home Depot /
--                                     Lowe's / SiteOne / etc. for live
--                                     price verification.

ALTER TYPE "ProjectType" ADD VALUE 'LANDSCAPING';
ALTER TYPE "ProjectType" ADD VALUE 'LAWN_CARE';

ALTER TABLE "Project"
  ADD COLUMN "lawnAreaSqFt" DECIMAL(10, 2),
  ADD COLUMN "roofAreaSqFt" DECIMAL(10, 2),
  ADD COLUMN "propertyLatitude" DECIMAL(10, 7),
  ADD COLUMN "propertyLongitude" DECIMAL(10, 7);

ALTER TABLE "MaterialSuggestion"
  ADD COLUMN "supplierSearchQuery" TEXT;
