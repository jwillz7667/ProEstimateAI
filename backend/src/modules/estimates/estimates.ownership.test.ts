import { beforeEach, describe, expect, it, vi } from "vitest";
import { Prisma } from "@prisma/client";
const mocks = vi.hoisted(() => ({
  $queryRaw: vi.fn(),
  project: { findFirst: vi.fn() }, pricingProfile: { findFirst: vi.fn() },
  estimate: { findFirst: vi.fn(), create: vi.fn(), update: vi.fn() },
  proposal: { findFirst: vi.fn() }, estimateLineItem: { findMany: vi.fn() },
  company: { update: vi.fn() }, activityLogEntry: { create: vi.fn() },
}));
vi.mock("../../config/database", () => ({ prisma: { ...mocks,
  $transaction: async (fn: (tx: unknown) => unknown) => fn(mocks),
} }));
vi.mock("../../lib/project-quality-tier", () => ({ readProjectQualityTier: vi.fn().mockResolvedValue(null) }));
vi.mock("../../lib/estimate-gen", () => ({ generateEstimate: vi.fn() }));
vi.mock("../commerce/entitlement-gate", () => ({ gateAIAction: vi.fn(), runReservedAction: (_reservation: unknown, action: () => Promise<unknown>) => action() }));
vi.mock("../../lib/usage-limits", () => ({ recordUsage: vi.fn() }));
import { create, update } from "./estimates.service";
beforeEach(() => {
  vi.resetAllMocks(); mocks.$queryRaw.mockResolvedValue([{ id: "estimate" }]); mocks.project.findFirst.mockResolvedValue({ id: "project" });
  mocks.estimate.findFirst.mockResolvedValue({ id: "estimate", projectId: "project", status: "DRAFT", updatedAt: new Date(), discountAmount: new Prisma.Decimal(0), totalAmount: new Prisma.Decimal(0) });
  mocks.proposal.findFirst.mockResolvedValue(null);
  mocks.estimateLineItem.findMany.mockResolvedValue([]);
  mocks.company.update.mockResolvedValue({ estimatePrefix: "EST", nextEstimateNumber: 2 });
});
describe("estimate pricing profile ownership", () => {
  it("does not let a valid owned profile bypass a sent-document edit restriction", async () => {
    mocks.pricingProfile.findFirst.mockResolvedValue({ id: "owned" });
    mocks.proposal.findFirst.mockResolvedValue({ id: "sent-proposal" });
    await expect(update("estimate", "company", "user", { pricing_profile_id: "owned" })).rejects.toMatchObject({ statusCode: 409 });
    expect(mocks.estimate.update).not.toHaveBeenCalled();
  });
  for (const operation of ["create", "update"]) {
    const run = (pricing_profile_id: string | null) => operation === "create"
      ? create("company", "user", { project_id: "project", pricing_profile_id })
      : update("estimate", "company", "user", { pricing_profile_id });
    it(`${operation} rejects foreign or missing profiles before writing`, async () => {
      mocks.pricingProfile.findFirst.mockResolvedValue(null);
      await expect(run("foreign-profile")).rejects.toThrow(/PricingProfile/);
      expect(mocks.pricingProfile.findFirst).toHaveBeenCalledWith({ where: { id: "foreign-profile", companyId: "company" }, select: { id: true } });
      expect(mocks.estimate.create).not.toHaveBeenCalled();
      expect(mocks.estimate.update).not.toHaveBeenCalled();
    });
    it(`${operation} allows an owned profile`, async () => {
      mocks.pricingProfile.findFirst.mockResolvedValue({ id: "owned" });
      await run("owned");
      expect(mocks.estimate[operation === "create" ? "create" : "update"]).toHaveBeenCalled();
    });
    it(`${operation} allows clearing a profile`, async () => {
      await run(null);
      expect(mocks.pricingProfile.findFirst).not.toHaveBeenCalled();
      expect(mocks.estimate[operation === "create" ? "create" : "update"]).toHaveBeenCalled();
    });
  }
});
