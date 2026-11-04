import { randomUUID } from "node:crypto";
import type { Request, Response } from "express";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import { listProjectsHandler } from "../../src/modules/clients/clients.controller";

async function history(companyId: string, clientId: string, query: Record<string, string> = {}) {
  let body: any;
  const response = {
    req: { requestId: "client-history-test" },
    status() { return response; },
    json(value: unknown) { body = value; return response; },
  };
  await listProjectsHandler({ companyId, params: { id: clientId }, query } as unknown as Request, response as unknown as Response);
  return body;
}

describe("client project history", () => {
  beforeEach(async () => {
    await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE');
  });

  it("returns only the selected client's projects and continues every page without duplicates", async () => {
    const company = await prisma.company.create({ data: { name: "Client history" } });
    const client = await prisma.client.create({ data: { companyId: company.id, name: "Selected client" } });
    const other = await prisma.client.create({ data: { companyId: company.id, name: "Other client" } });
    for (let index = 0; index < 4; index++) {
      await prisma.project.create({ data: {
        companyId: company.id, clientId: client.id, title: `History ${index}`, projectType: "KITCHEN",
        createdAt: new Date(Date.UTC(2026, 0, index + 1)),
      } });
    }
    await prisma.project.create({ data: { companyId: company.id, clientId: other.id, title: "Not this client", projectType: "KITCHEN" } });
    const first = await history(company.id, client.id, { page_size: "2" });
    const second = await history(company.id, client.id, { page_size: "2", cursor: first.meta.pagination.next_cursor });
    expect(first.ok).toBe(true);
    expect(first.data.map((row: any) => row.title)).toEqual(["History 3", "History 2"]);
    expect(second.data.map((row: any) => row.title)).toEqual(["History 1", "History 0"]);
    expect(new Set([...first.data, ...second.data].map((row: any) => row.id)).size).toBe(4);
    expect(second.meta.pagination.next_cursor).toBeNull();
    for (const project of [...first.data, ...second.data]) {
      expect(project.client_id).toBe(client.id);
      expect(project.company_id).toBe(company.id);
    }
  });

  it("returns an honest empty history for a client with no linked work", async () => {
    const company = await prisma.company.create({ data: { name: "No history" } });
    const client = await prisma.client.create({ data: { companyId: company.id, name: "New client" } });
    expect((await history(company.id, client.id)).data).toEqual([]);
  });

  it("does not reveal another tenant's client or nonexistent client history", async () => {
    const company = await prisma.company.create({ data: { name: "Owner" } });
    const client = await prisma.client.create({ data: { companyId: company.id, name: "Private client" } });
    const other = await prisma.company.create({ data: { name: "Other" } });
    await expect(history(other.id, client.id)).rejects.toMatchObject({ statusCode: 404 });
    await expect(history(company.id, randomUUID())).rejects.toMatchObject({ statusCode: 404 });
  });
});
