-- AlterEnum
-- This migration adds two new ProjectType values: OUTDOOR_LIVING (decks,
-- patios, pergolas, pools, firepits) and GARAGE (workshop fit-outs,
-- EV-ready bays, livable conversions, storage build-outs). Postgres
-- requires each ALTER TYPE ... ADD VALUE to run in its own transaction,
-- so we issue them as separate statements.
ALTER TYPE "ProjectType" ADD VALUE 'OUTDOOR_LIVING';
ALTER TYPE "ProjectType" ADD VALUE 'GARAGE';
