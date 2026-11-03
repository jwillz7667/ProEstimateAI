import { randomUUID } from "node:crypto";
import { once } from "node:events";
import type { Server } from "node:http";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createApp } from "../../src/app";
import { prisma } from "../../src/config/database";
import { signAccessToken } from "../../src/lib/jwt";

let server: Server;
let origin: string;
beforeAll(async () => {
  server = createApp().listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Expected a local listener");
  origin = `http://127.0.0.1:${address.port}`;
});
afterAll(async () => {
  if (server) await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
});
beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });

async function fixture() {
  const company = await prisma.company.create({ data: { name: "Read-only workspace" } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: "Read-only member", role: "VIEWER" } });
  const token = signAccessToken({ userId: user.id, companyId: company.id });
  const request = (method: string, path: string, body?: object) => fetch(`${origin}/v1${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { company, user, request };
}

describe("read-only workspace access through the real route mounts", () => {
  it("denies every business mutation before resource lookup, paid gates or provider work", async () => {
    const t = await fixture();
    const mutations = [
      ["PATCH", "/companies/me"], ["POST", "/companies/me/logo"], ["DELETE", "/companies/me/logo"],
      ["POST", "/clients"], ["POST", "/projects"], ["DELETE", "/assets/missing"],
      ["PATCH", "/materials/missing"], ["POST", "/projects/missing/assets"],
      ["POST", "/projects/missing/generations"], ["POST", "/projects/missing/estimates"],
      ["PATCH", "/estimate-line-items/missing"], ["POST", "/estimates/missing/line-items"],
      ["DELETE", "/estimate-exports/missing"], ["POST", "/estimates/missing/exports"],
      ["PATCH", "/proposals/missing"], ["PATCH", "/invoices/missing"],
      ["PATCH", "/invoice-line-items/missing"], ["POST", "/pricing-profiles"],
      ["PATCH", "/labor-rates/missing"], ["POST", "/maps/lawn-area"],
      ["POST", "/estimate-library/items"], ["DELETE", "/job-costs/missing"],
      ["POST", "/follow-ups"], ["POST", "/payment-settings/onboarding"],
    ];
    for (const [method, path] of mutations) {
      const response = await t.request(method, path, method === "DELETE" ? undefined : {});
      expect(response.status, `${method} ${path}`).toBe(403);
      expect(await response.json()).toMatchObject({ error: { code: "FORBIDDEN" } });
    }
    expect(await prisma.usageEvent.count()).toBe(0);
    expect(await prisma.project.count()).toBe(0);
    expect(await prisma.invoicePayment.count()).toBe(0);
  });
  it("preserves reads and personal profile updates, and observes a role change on the same token", async () => {
    const t = await fixture();
    expect((await t.request("GET", "/companies/me")).status).toBe(200);
    expect((await t.request("PATCH", "/users/me", { full_name: "Updated member" })).status).toBe(200);
    expect((await t.request("PATCH", "/companies/me", { default_ai_preview_enabled: false })).status).toBe(403);
    await prisma.user.update({ where: { id: t.user.id }, data: { role: "ESTIMATOR" } });
    expect((await t.request("PATCH", "/companies/me", { default_ai_preview_enabled: false })).status).toBe(200);
    expect((await prisma.company.findUniqueOrThrow({ where: { id: t.company.id } })).defaultAiPreviewEnabled).toBe(false);
  });
});
