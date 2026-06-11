import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import { reapGenerations } from "../../src/modules/admin/admin.service";

const TWO_HOURS_AGO = new Date(Date.now() - 2 * 60 * 60 * 1000);

async function resetTables() {
  await prisma.$executeRawUnsafe(
    `TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE;`,
  );
}

interface SeededIds {
  stuckQueued: string;
  stuckProcessing: string;
  imageless: string;
  healthy: string;
  recentQueued: string;
  recentImageless: string;
}

async function seedGenerations(): Promise<SeededIds> {
  const company = await prisma.company.create({ data: { name: "Reap Co" } });
  const project = await prisma.project.create({
    data: { companyId: company.id, title: "Reap Project" },
  });
  const pid = project.id;

  // Eligible: stale QUEUED / PROCESSING (older than the 10-min stuck threshold).
  const stuckQueued = await prisma.aIGeneration.create({
    data: { projectId: pid, prompt: "p", status: "QUEUED", createdAt: TWO_HOURS_AGO },
  });
  const stuckProcessing = await prisma.aIGeneration.create({
    data: { projectId: pid, prompt: "p", status: "PROCESSING", createdAt: TWO_HOURS_AGO },
  });

  // Eligible: COMPLETED but no image bytes (older than the 1-hr imageless threshold).
  const imageless = await prisma.aIGeneration.create({
    data: { projectId: pid, prompt: "p", status: "COMPLETED", imageData: null, createdAt: TWO_HOURS_AGO },
  });

  // NOT eligible: COMPLETED with real bytes.
  const healthy = await prisma.aIGeneration.create({
    data: { projectId: pid, prompt: "p", status: "COMPLETED", imageData: "abc123", createdAt: TWO_HOURS_AGO },
  });

  // NOT eligible: too recent to be considered orphaned.
  const recentQueued = await prisma.aIGeneration.create({
    data: { projectId: pid, prompt: "p", status: "QUEUED" },
  });
  const recentImageless = await prisma.aIGeneration.create({
    data: { projectId: pid, prompt: "p", status: "COMPLETED", imageData: null },
  });

  return {
    stuckQueued: stuckQueued.id,
    stuckProcessing: stuckProcessing.id,
    imageless: imageless.id,
    healthy: healthy.id,
    recentQueued: recentQueued.id,
    recentImageless: recentImageless.id,
  };
}

async function statusOf(id: string): Promise<string> {
  const row = await prisma.aIGeneration.findUniqueOrThrow({ where: { id } });
  return row.status;
}

describe("admin.reapGenerations", () => {
  beforeEach(async () => {
    await resetTables();
  });

  it("dry-run counts eligible rows without mutating anything", async () => {
    const ids = await seedGenerations();

    const result = await reapGenerations({ dry_run: true, scope: "all" });

    expect(result.dry_run).toBe(true);
    expect(result.stuck).toBe(2);
    expect(result.imageless).toBe(1);

    // Nothing changed.
    expect(await statusOf(ids.stuckQueued)).toBe("QUEUED");
    expect(await statusOf(ids.stuckProcessing)).toBe("PROCESSING");
    expect(await statusOf(ids.imageless)).toBe("COMPLETED");
  });

  it("flips only the eligible rows on a real run and leaves the rest intact", async () => {
    const ids = await seedGenerations();

    const result = await reapGenerations({ dry_run: false, scope: "all" });

    expect(result.stuck).toBe(2);
    expect(result.imageless).toBe(1);

    expect(await statusOf(ids.stuckQueued)).toBe("FAILED");
    expect(await statusOf(ids.stuckProcessing)).toBe("FAILED");
    expect(await statusOf(ids.imageless)).toBe("FAILED");

    // Untouched: healthy completed, and both too-recent rows.
    expect(await statusOf(ids.healthy)).toBe("COMPLETED");
    expect(await statusOf(ids.recentQueued)).toBe("QUEUED");
    expect(await statusOf(ids.recentImageless)).toBe("COMPLETED");

    const healthy = await prisma.aIGeneration.findUniqueOrThrow({ where: { id: ids.healthy } });
    expect(healthy.imageData).toBe("abc123");
  });

  it("scopes the sweep: 'stuck' leaves imageless null and untouched", async () => {
    const ids = await seedGenerations();

    const result = await reapGenerations({ dry_run: false, scope: "stuck" });

    expect(result.stuck).toBe(2);
    expect(result.imageless).toBeNull();
    expect(await statusOf(ids.imageless)).toBe("COMPLETED");
  });

  it("scopes the sweep: 'imageless' leaves stuck null and untouched", async () => {
    const ids = await seedGenerations();

    const result = await reapGenerations({ dry_run: false, scope: "imageless" });

    expect(result.stuck).toBeNull();
    expect(result.imageless).toBe(1);
    expect(await statusOf(ids.stuckQueued)).toBe("QUEUED");
    expect(await statusOf(ids.imageless)).toBe("FAILED");
  });
});
