import { Prisma, type QualityTier } from "@prisma/client";
import { prisma } from "../config/database";

export function normalizeQualityTier(value: unknown): QualityTier | null {
  return value === "STANDARD" || value === "PREMIUM" || value === "LUXURY"
    ? value
    : null;
}

/** Cast to text to tolerate historical Prisma enum nullability mismatches,
 * while honoring the contractor's saved tier instead of silently using Auto. */
export async function readProjectQualityTiers(
  projectIds: readonly string[],
  companyId: string,
): Promise<Map<string, QualityTier | null>> {
  if (projectIds.length === 0) return new Map();
  const rows = await prisma.$queryRaw<
    Array<{ id: string; qualityTier: string | null }>
  >(Prisma.sql`
    SELECT id, "qualityTier"::text AS "qualityTier" FROM "Project"
    WHERE "companyId" = ${companyId} AND id IN (${Prisma.join(projectIds)})
  `);
  return new Map(
    rows.map((row) => [row.id, normalizeQualityTier(row.qualityTier)]),
  );
}

export async function readProjectQualityTier(
  projectId: string,
  companyId: string,
): Promise<QualityTier | null> {
  return (
    (await readProjectQualityTiers([projectId], companyId)).get(projectId) ??
    null
  );
}
