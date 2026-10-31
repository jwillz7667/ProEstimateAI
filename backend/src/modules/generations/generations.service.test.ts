import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import sharp from "sharp";

const mocks = vi.hoisted(() => ({
  env: {
    FAL_KEY: "fal-test" as string | undefined,
    GOOGLE_AI_API_KEY: undefined,
    PIAPI_API_KEY: undefined,
    API_BASE_URL: "https://api.example.test",
  },
  db: {
    project: { findFirst: vi.fn() },
    company: { findUnique: vi.fn() },
    asset: { findFirst: vi.fn() },
    aIGeneration: { create: vi.fn(), update: vi.fn(), updateMany: vi.fn() },
    activityLogEntry: { create: vi.fn() },
    $transaction: vi.fn(),
  },
  gateAIAction: vi.fn(),
  recordUsage: vi.fn(),
  materials: vi.fn(),
  labor: vi.fn(),
  push: vi.fn(),
  failGeneration: vi.fn(),
}));
vi.mock("../../config/env", () => ({ env: mocks.env }));
vi.mock("../../config/database", () => ({ prisma: mocks.db }));
vi.mock("../../config/logger", () => ({ logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() } }));
vi.mock("../../lib/project-quality-tier", () => ({ readProjectQualityTier: vi.fn().mockResolvedValue("STANDARD") }));
vi.mock('../../lib/generation-usage', () => ({ failGenerationAndRefund: mocks.failGeneration, linkGenerationReservation: vi.fn() }));
vi.mock("../../lib/usage-limits", () => ({ recordUsage: mocks.recordUsage }));
vi.mock("../commerce/entitlement-gate", () => ({
  gateAIAction: mocks.gateAIAction,
  runReservedAction: (_reservation: unknown, action: () => Promise<unknown>) => action(),
}));
vi.mock("../../lib/material-gen", () => ({ generateMaterialSuggestions: mocks.materials, generateLaborEstimates: mocks.labor }));
vi.mock("../../lib/apns", () => ({ sendGenerationReady: mocks.push }));
vi.mock("../estimates/estimates.service", () => ({}));
vi.mock("../estimate-line-items/estimate-line-items.service", () => ({}));

import { create } from "./generations.service";

const generation = { id: "generation", projectId: "project", status: "QUEUED" };
const taskBase = "https://queue.fal.run/fal-ai/flux-2/requests/service-task";

beforeEach(() => {
  vi.clearAllMocks();
  mocks.env.FAL_KEY = "fal-test";
  mocks.db.project.findFirst.mockResolvedValue({
    projectType: "EXTERIOR", title: "Repaint siding", description: null,
    squareFootage: null, dimensions: null, aiPreviewEnabled: true,
  });
  mocks.db.company.findUnique.mockResolvedValue({ zip: "60601" });
  mocks.db.asset.findFirst.mockResolvedValue(null);
  mocks.db.$transaction.mockImplementation((action: (tx: typeof mocks.db) => Promise<unknown>) => action(mocks.db));
  mocks.db.aIGeneration.create.mockResolvedValue(generation);
  mocks.db.aIGeneration.update.mockResolvedValue(generation);
  mocks.db.aIGeneration.updateMany.mockResolvedValue({ count: 1 });
  mocks.failGeneration.mockResolvedValue(true);
  mocks.db.activityLogEntry.create.mockResolvedValue({});
  mocks.gateAIAction.mockResolvedValue(undefined);
  mocks.recordUsage.mockResolvedValue(undefined);
  mocks.materials.mockResolvedValue([]);
  mocks.labor.mockResolvedValue([]);
  mocks.push.mockResolvedValue(undefined);
  vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Unexpected provider call")));
});

afterEach(() => { vi.unstubAllGlobals(); });

describe("generation service provider configuration", () => {
  it("enqueues and completes a photo preview with fal as the only configured provider", async () => {
    const source = await sharp({ create: { width: 768, height: 1024, channels: 3, background: "white" } }).png().toBuffer();
    mocks.db.asset.findFirst.mockResolvedValue({ id: "asset", imageData: source.toString("base64"), imageMimeType: "image/png" });
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ request_id: "service-task", status_url: `${taskBase}/status`, response_url: taskBase, cancel_url: `${taskBase}/cancel` })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ status: "COMPLETED" })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ images: [{ url: "https://v3.fal.media/files/service.png" }], has_nsfw_concepts: [false] })))
      .mockResolvedValueOnce(new Response(source));
    vi.stubGlobal("fetch", fetchMock);

    expect(await create("project", "company", "user", { prompt: "Paint only the siding", generate_preview: true })).toEqual(generation);
    await vi.waitFor(() => expect(mocks.db.aIGeneration.updateMany).toHaveBeenCalledWith({
      where: { id: "generation", status: 'PROCESSING' },
      data: expect.objectContaining({ status: "COMPLETED", imageMimeType: "image/png", imageData: expect.any(String), previewUrl: "https://api.example.test/v1/generations/generation/preview" }),
    }));
    expect(mocks.gateAIAction).toHaveBeenCalledWith({ userId: "user", companyId: "company", metric: "AI_GENERATION" }, mocks.db);
    expect(mocks.recordUsage).toHaveBeenCalledOnce();
    expect(mocks.db.aIGeneration.create).toHaveBeenCalledWith({ data: expect.objectContaining({ status: "QUEUED", projectId: "project" }) });
    expect(fetchMock.mock.calls[0][0]).toBe("https://queue.fal.run/fal-ai/flux-2/flash/edit");
    const providerInput = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(providerInput.prompt).toContain("Paint only the siding");
    expect(providerInput.prompt).toContain("SAME photograph");
    expect(providerInput.image_urls[0]).toMatch(/^data:image\/png;base64,/);
    expect(providerInput.image_size.width / providerInput.image_size.height).toBeCloseTo(0.75, 2);
    expect(fetchMock).toHaveBeenCalledTimes(4);
    expect(mocks.db.aIGeneration.update.mock.calls.some(([call]) => call.data.status === "FAILED")).toBe(false);
  });

  it("marks a preview failed without contacting providers when no key exists", async () => {
    mocks.env.FAL_KEY = undefined;
    await create("project", "company", "user", { prompt: "Repaint siding", generate_preview: true });
    await vi.waitFor(() => expect(mocks.failGeneration).toHaveBeenCalledWith('generation', 'Image generation service is not configured. Contact support.'));
    expect(fetch).not.toHaveBeenCalled();
  });
});
