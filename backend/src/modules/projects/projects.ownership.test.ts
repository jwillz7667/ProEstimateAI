import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({
  project: { findFirst: vi.fn(), create: vi.fn(), update: vi.fn() },
  client: { findFirst: vi.fn() }, gate: vi.fn(),
}));
vi.mock("../../config/database", () => ({ prisma: mocks }));
vi.mock("../../config/env", () => ({ env: {} }));
vi.mock("../commerce/entitlement-gate", () => ({ gateAIAction: mocks.gate }));
vi.mock("../../lib/usage-limits", () => ({ recordUsage: vi.fn() }));
import { create, update } from "./projects.service";
beforeEach(() => { vi.resetAllMocks(); mocks.project.findFirst.mockResolvedValue({ id: "project" }); });
describe("project client ownership", () => {
  for (const operation of ["create", "update"]) {
    const run = (client_id: string | null) => operation === "create"
      ? create("company", "user", { title: "Test", client_id, ai_preview_enabled: false })
      : update("project", "company", { client_id });
    it(`${operation} rejects foreign or missing clients before writing`, async () => {
      mocks.client.findFirst.mockResolvedValue(null);
      await expect(run("foreign-client")).rejects.toThrow(/Client/);
      expect(mocks.client.findFirst).toHaveBeenCalledWith({ where: { id: "foreign-client", companyId: "company" }, select: { id: true } });
      expect(mocks.project.create).not.toHaveBeenCalled();
      expect(mocks.project.update).not.toHaveBeenCalled();
    });
    it(`${operation} allows an owned client`, async () => {
      mocks.client.findFirst.mockResolvedValue({ id: "owned" });
      await run("owned");
      expect(mocks.project[operation === "create" ? "create" : "update"]).toHaveBeenCalled();
    });
    it(`${operation} allows clearing a client`, async () => {
      await run(null);
      expect(mocks.client.findFirst).not.toHaveBeenCalled();
      expect(mocks.project[operation === "create" ? "create" : "update"]).toHaveBeenCalled();
    });
  }
});
