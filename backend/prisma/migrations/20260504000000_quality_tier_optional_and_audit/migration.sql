-- Make Project.qualityTier optional so the iOS picker can skip it ("Auto"
-- mode where the AI infers tier from description + photos at gen time).
ALTER TABLE "Project" ALTER COLUMN "qualityTier" DROP DEFAULT;
ALTER TABLE "Project" ALTER COLUMN "qualityTier" DROP NOT NULL;

-- Snapshot the tier on each generation/estimate at create time so a later
-- edit to Project.qualityTier doesn't retroactively reinterpret bounds the
-- AI was clamped against.
ALTER TABLE "AIGeneration" ADD COLUMN "qualityTier" "QualityTier";
ALTER TABLE "MaterialSuggestion" ADD COLUMN "qualityTier" "QualityTier";
ALTER TABLE "Estimate" ADD COLUMN "qualityTier" "QualityTier";
