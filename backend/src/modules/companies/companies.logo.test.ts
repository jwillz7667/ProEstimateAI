import { beforeEach, describe, expect, it, vi } from "vitest";
const company = vi.hoisted(() => ({ findUnique: vi.fn(), update: vi.fn() }));
vi.mock("../../config/database", () => ({ prisma: { company } }));
vi.mock("../../config/env", () => ({ env: { API_BASE_URL: "https://api.example.test" } }));
vi.mock("../../config/redis", () => ({ invalidateCache: vi.fn(), CacheKeys: { companyProfile: (id: string) => id } }));
import { uploadLogo } from "./companies.service";
beforeEach(() => { vi.resetAllMocks(); company.findUnique.mockResolvedValue({ id: "company" }); company.update.mockImplementation(async ({ data }) => data); });
describe("logo URL cache invalidation", () => {
  it("uses stable content versions and changes the URL on replacement", async () => {
    const a = await uploadLogo("company", { image_data: "Zmlyc3Q=", mime_type: "image/png" });
    const b = await uploadLogo("company", { image_data: "c2Vjb25k", mime_type: "image/png" });
    const repeated = await uploadLogo("company", { image_data: "c2Vjb25k", mime_type: "image/png" });
    expect(a.logoUrl).toMatch(/^https:\/\/api.example.test\/v1\/companies\/company\/logo\?v=[a-f0-9]{16}$/);
    expect(b.logoUrl).not.toBe(a.logoUrl);
    expect(repeated.logoUrl).toBe(b.logoUrl);
  });
});
