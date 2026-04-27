-- Premium tier + Google OAuth.
--
-- New plan codes:
--   * PREMIUM_MONTHLY — $49.99/mo, unlimited projects/AI gens/estimates.
--   * PREMIUM_ANNUAL  — $499.99/yr (~17% off the monthly equivalent).
--
-- New usage metrics:
--   * PROJECT_CREATED   — counts toward the Pro tier 2/mo cap.
--   * ESTIMATE_GENERATED — counts toward the Pro tier 20/mo estimate cap.
--   AI_GENERATION (existing) is now used for the Pro tier 20/mo image cap.
--
-- New User column:
--   * googleId — Google "sub" claim. Mirror of appleUserId for the Google
--     sign-in flow. Unique so two users can't claim the same Google
--     identity.

ALTER TYPE "PlanCode" ADD VALUE 'PREMIUM_MONTHLY';
ALTER TYPE "PlanCode" ADD VALUE 'PREMIUM_ANNUAL';

ALTER TYPE "UsageMetricCode" ADD VALUE 'PROJECT_CREATED';
ALTER TYPE "UsageMetricCode" ADD VALUE 'ESTIMATE_GENERATED';

ALTER TABLE "User"
  ADD COLUMN "googleId" TEXT;

CREATE UNIQUE INDEX "User_googleId_key" ON "User"("googleId");
