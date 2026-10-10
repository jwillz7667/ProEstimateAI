import { randomUUID } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { prisma } from "../../src/config/database";
import * as jwt from "../../src/lib/jwt";
import { refresh } from "../../src/modules/auth/auth.service";
import { update as updateProject } from "../../src/modules/projects/projects.service";
import { create as createEstimate } from "../../src/modules/estimates/estimates.service";

// Uses only the disposable TEST_DATABASE_URL configured by setup.ts. All
// session consumption, uniqueness constraints, rollback and tenant lookups
// execute against PostgreSQL; no provider or production account is contacted.
beforeEach(async () => {
  await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE');
});
afterEach(() => vi.restoreAllMocks());
async function tenant() {
  const company = await prisma.company.create({ data: { name: "Security test" } });
  const user = await prisma.user.create({ data: {
    companyId: company.id, email: `${randomUUID()}@example.test`, fullName: "Security tester",
  } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: "Test project", projectType: "KITCHEN" } });
  return { company, user, project };
}
async function session(userId: string, companyId: string) {
  const token = jwt.signRefreshToken({ userId, companyId });
  await prisma.refreshToken.create({ data: { userId, token, expiresAt: new Date(Date.now() + 60_000) } });
  return token;
}

describe("authentication and tenancy database boundaries", () => {
  it("only one concurrent refresh can succeed", async () => {
    const { user, company } = await tenant();
    const token = await session(user.id, company.id);
    const results = await Promise.allSettled([refresh(token), refresh(token)]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(results.filter((r) => r.status === "rejected")).toHaveLength(1);
    expect(await prisma.refreshToken.findUnique({ where: { token } })).toBeNull();
    // Replay detection may revoke the winner if the losing request observes
    // the token after commit; it must never create two successor sessions.
    expect(await prisma.refreshToken.count({ where: { userId: user.id } })).toBeLessThanOrEqual(1);
  });
  it("rolls consumption back if successor insertion fails", async () => {
    const { user, company } = await tenant();
    const token = await session(user.id, company.id);
    const existing = await session(user.id, company.id);
    vi.spyOn(jwt, "signRefreshToken").mockReturnValue(existing);
    await expect(refresh(token)).rejects.toThrow();
    expect(await prisma.refreshToken.findUnique({ where: { token } })).not.toBeNull();
    expect(await prisma.refreshToken.count({ where: { userId: user.id } })).toBe(2);
  });
  it("rejects disabled users without creating successor sessions", async () => {
    const { user, company } = await tenant();
    const token = await session(user.id, company.id);
    await prisma.user.update({ where: { id: user.id }, data: { isActive: false } });
    await expect(refresh(token)).rejects.toThrow(/unavailable/);
    expect(await prisma.refreshToken.count({ where: { userId: user.id } })).toBe(1);
  });
  it("rejects a real foreign-company client and preserves the project", async () => {
    const owner = await tenant();
    const other = await tenant();
    const client = await prisma.client.create({ data: { companyId: other.company.id, name: "Other tenant client" } });
    await expect(updateProject(owner.project.id, owner.company.id, { client_id: client.id })).rejects.toThrow(/Client/);
    expect((await prisma.project.findUniqueOrThrow({ where: { id: owner.project.id } })).clientId).toBeNull();
  });
  it("rejects a real foreign-company pricing profile without consuming an estimate number", async () => {
    const owner = await tenant();
    const other = await tenant();
    const profile = await prisma.pricingProfile.create({ data: { companyId: other.company.id, name: "Other pricing" } });
    await expect(createEstimate(owner.company.id, owner.user.id, { project_id: owner.project.id, pricing_profile_id: profile.id })).rejects.toThrow(/PricingProfile/);
    expect(await prisma.estimate.count({ where: { companyId: owner.company.id } })).toBe(0);
    expect((await prisma.company.findUniqueOrThrow({ where: { id: owner.company.id } })).nextEstimateNumber).toBe(owner.company.nextEstimateNumber);
  });
});
