import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import sharp from "sharp";

const mocks = vi.hoisted(() => ({
  env: { GOOGLE_AI_API_KEY: "google-test" as string | undefined, PIAPI_API_KEY: "piapi-test" as string | undefined },
  generateContent: vi.fn(),
}));
vi.mock("../config/env", () => ({ env: mocks.env }));
vi.mock("../config/logger", () => ({ logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() } }));
vi.mock("@google/genai", () => ({
  GoogleGenAI: class { models = { generateContent: mocks.generateContent }; },
  HarmBlockThreshold: { OFF: "OFF" },
  HarmCategory: {},
  createPartFromBase64: (data: string, mimeType: string) => ({ inlineData: { data, mimeType } }),
  createPartFromText: (text: string) => ({ text }),
  createUserContent: (parts: unknown[]) => ({ role: "user", parts }),
}));

import { generatePreviewImage, type ImageGenContext, type ReferencePhoto } from "./image-gen";
import { generatePreviewImagePiAPI } from "./piapi-image-gen";

const context: ImageGenContext = { projectType: "EXTERIOR", qualityTier: "STANDARD", projectTitle: "Repaint siding" };
const sourceUrl = "https://assets.example.test/source.png";
let source: ReferencePhoto;

function mockPiAPISuccess() {
  const fetchMock = vi.fn()
    .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { task_id: "test-task" } })))
    .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { status: "completed", output: { image_url: "https://assets.example.test/output.png" } } })))
    .mockResolvedValueOnce(new Response(Buffer.from(source.base64Data, "base64"), { headers: { "content-type": "image/png" } }));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

beforeEach(async () => {
  vi.clearAllMocks();
  mocks.env.GOOGLE_AI_API_KEY = "google-test";
  mocks.env.PIAPI_API_KEY = "piapi-test";
  const data = await sharp({ create: { width: 30, height: 40, channels: 3, background: "white" } }).png().toBuffer();
  source = { base64Data: data.toString("base64"), mimeType: "image/png" };
  mocks.generateContent.mockResolvedValue({ candidates: [{ content: { parts: [{ inlineData: { data: "result", mimeType: "image/png" } }] } }] });
  // No test can reach a real provider, even on an unexpected fallback.
  vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Unexpected provider call")));
});

afterEach(() => { vi.unstubAllGlobals(); });

describe("Google reference framing", () => {
  it.each(["EXTERIOR", "BATHROOM", "KITCHEN"])("does not impose %s framing on a reference", async (projectType) => {
    const result = await generatePreviewImage("Paint only the siding", { ...context, projectType }, source, sourceUrl);
    expect(result?.base64Data).toBe("result");
    const request = mocks.generateContent.mock.calls[0][0];
    expect(request.config.imageConfig).toEqual({ imageSize: "2K" });
    expect(request.contents.parts[0].inlineData).toEqual({ data: source.base64Data, mimeType: source.mimeType });
    expect(fetch).not.toHaveBeenCalled();
  });

  it.each([["EXTERIOR", "16:9"], ["BATHROOM", "3:4"], ["KITCHEN", "4:3"]])(
    "keeps %s text-only framing", async (projectType, aspectRatio) => {
      await generatePreviewImage("Create a concept", { ...context, projectType });
      expect(mocks.generateContent.mock.calls[0][0].config.imageConfig).toEqual({ imageSize: "2K", aspectRatio });
    },
  );

  it("refuses a URL-only reference before Google can generate text-only", async () => {
    expect(await generatePreviewImage("Repaint", context, undefined, sourceUrl)).toBeNull();
    expect(mocks.generateContent).not.toHaveBeenCalled();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not lose the photo when Google fails and PiAPI has no source URL", async () => {
    mocks.generateContent.mockRejectedValue(new Error("Provider unavailable"));
    expect(await generatePreviewImage("Repaint", context, source)).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("preserves source framing and image URL across Google to PiAPI fallback", async () => {
    mocks.generateContent.mockRejectedValue(new Error("Provider unavailable"));
    const fetchMock = mockPiAPISuccess();
    expect(await generatePreviewImage("Repaint", context, source, sourceUrl)).not.toBeNull();
    const request = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(request.input.aspect_ratio).toBe("3:4");
    expect(request.input.image_urls).toEqual([sourceUrl]);
    expect(request.input.prompt).toContain("SAME photograph");
  });
});

describe("PiAPI reference safety", () => {
  it("rejects reference bytes without a usable URL before creating a task", async () => {
    for (const referenceAssetUrl of [undefined, "", "   "]) {
      expect(await generatePreviewImagePiAPI({ userPrompt: "Repaint", context, referencePhoto: source, referenceAssetUrl })).toBeNull();
    }
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects URL-only references whose framing cannot be read", async () => {
    expect(await generatePreviewImagePiAPI({ userPrompt: "Repaint", context, referenceAssetUrl: sourceUrl })).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects unreadable source bytes before creating a task", async () => {
    expect(await generatePreviewImagePiAPI({ userPrompt: "Repaint", context, referencePhoto: { ...source, base64Data: "invalid" }, referenceAssetUrl: sourceUrl })).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("keeps category framing for genuine text-only generation", async () => {
    const fetchMock = mockPiAPISuccess();
    expect(await generatePreviewImagePiAPI({ userPrompt: "Create a concept", context })).not.toBeNull();
    const request = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(request.input.aspect_ratio).toBe("16:9");
    expect(request.input).not.toHaveProperty("image_urls");
  });

  it("keeps reference inputs when falling back from Pro to Nano Banana 2", async () => {
    const fetchMock = mockPiAPISuccess();
    fetchMock.mockReset()
      .mockResolvedValueOnce(new Response("Unavailable", { status: 503 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { task_id: "test-task" } })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { status: "completed", output: { image_url: "https://assets.example.test/output.png" } } })))
      .mockResolvedValueOnce(new Response("output", { headers: { "content-type": "image/png" } }));
    expect(await generatePreviewImagePiAPI({ userPrompt: "Repaint", context, referencePhoto: source, referenceAssetUrl: sourceUrl })).not.toBeNull();
    for (const index of [0, 1]) {
      const request = JSON.parse(fetchMock.mock.calls[index][1].body);
      expect(request.input.aspect_ratio).toBe("3:4");
      expect(request.input.image_urls).toEqual([sourceUrl]);
    }
    expect(JSON.parse(fetchMock.mock.calls[1][1].body).task_type).toBe("nano-banana-2");
  });
});
