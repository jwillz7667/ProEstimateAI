-- Restore the free-tier starter pack at 5 AI generation credits.
--
-- Background: signup used to hand out 3 starter credits, then was changed to
-- zero (every paid action paywalled on first tap). We're walking that back to
-- a 5-credit starter pack so contractors can try the AI preview loop end-to-end
-- before deciding to subscribe.
--
-- This migration backfills the new bucket for every existing FREE user who
-- doesn't already have an AI_GENERATION starter bucket. Users created via
-- the new signup path will already have one (auth.service.ts seeds it inside
-- the signup transaction), so the WHERE NOT EXISTS guard makes this idempotent
-- and safe to re-run if it ever needs to be replayed.
--
-- We do NOT touch existing buckets — anyone already mid-flow on a 0-credit or
-- 3-credit bucket keeps what they have. Bumping their includedQuantity would
-- effectively grant them additional credits beyond what was promised at signup.

INSERT INTO "UsageBucket" (
  "id",
  "userId",
  "companyId",
  "metricCode",
  "includedQuantity",
  "consumedQuantity",
  "resetPolicy",
  "source",
  "createdAt",
  "updatedAt"
)
SELECT
  -- CUID-ish placeholder generated server-side. Prisma's @default(cuid())
  -- only fires on application-side INSERTs; raw SQL needs an explicit value.
  -- gen_random_uuid() is fine here because the column is just a string PK
  -- and uniqueness is the only contract we're upholding.
  'bf_' || replace(gen_random_uuid()::text, '-', ''),
  ue."userId",
  ue."companyId",
  'AI_GENERATION',
  5,
  0,
  'NEVER',
  'STARTER_CREDITS',
  NOW(),
  NOW()
FROM "UserEntitlement" ue
WHERE ue."status" = 'FREE'
  AND NOT EXISTS (
    SELECT 1
    FROM "UsageBucket" ub
    WHERE ub."userId" = ue."userId"
      AND ub."companyId" = ue."companyId"
      AND ub."metricCode" = 'AI_GENERATION'
      AND ub."source" = 'STARTER_CREDITS'
  );
