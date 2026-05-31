-- AlterEnum
-- Adds 13 home-service trade ProjectType values. Unlike the remodel types
-- these are service calls (no redesign), so the app defaults them to no
-- reference photo and no AI image. Postgres requires each ALTER TYPE ...
-- ADD VALUE as its own statement; none of the new values are used within
-- this migration, so the column adds below are safe in the same file.
ALTER TYPE "ProjectType" ADD VALUE 'PLUMBING';
ALTER TYPE "ProjectType" ADD VALUE 'ELECTRICAL';
ALTER TYPE "ProjectType" ADD VALUE 'HVAC';
ALTER TYPE "ProjectType" ADD VALUE 'APPLIANCE_REPAIR';
ALTER TYPE "ProjectType" ADD VALUE 'HANDYMAN';
ALTER TYPE "ProjectType" ADD VALUE 'PEST_CONTROL';
ALTER TYPE "ProjectType" ADD VALUE 'HOUSE_CLEANING';
ALTER TYPE "ProjectType" ADD VALUE 'JUNK_REMOVAL';
ALTER TYPE "ProjectType" ADD VALUE 'PRESSURE_WASHING';
ALTER TYPE "ProjectType" ADD VALUE 'GUTTER_SERVICES';
ALTER TYPE "ProjectType" ADD VALUE 'FENCING';
ALTER TYPE "ProjectType" ADD VALUE 'GARAGE_DOOR';
ALTER TYPE "ProjectType" ADD VALUE 'WINDOW_CLEANING';

-- AlterTable
-- Per-project image-generation switch. When false the AI pipeline produces a
-- text-only estimate (materials + labor) and skips image generation.
ALTER TABLE "Project" ADD COLUMN "aiPreviewEnabled" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
-- Company-wide default seeded onto new projects at creation time.
ALTER TABLE "Company" ADD COLUMN "defaultAiPreviewEnabled" BOOLEAN NOT NULL DEFAULT true;
