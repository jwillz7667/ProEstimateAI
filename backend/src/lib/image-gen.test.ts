import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import sharp from "sharp";

const mocks = vi.hoisted(() => ({
  env: { FAL_KEY: undefined as string | undefined, GOOGLE_AI_API_KEY: "google-test" as string | undefined, PIAPI_API_KEY: "piapi-test" as string | undefined },
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

function mockPiAPISuccess(options: { contentType?: string; singularOutput?: boolean } = {}) {
  const imageUrl = "https://assets.example.test/output.png";
  const fetchMock = vi.fn()
    .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { task_id: "test-task" } })))
    .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { status: "completed", output: options.singularOutput ? { image_url: imageUrl } : { image_urls: [imageUrl] } } })))
    .mockResolvedValueOnce(new Response(Buffer.from(source.base64Data, "base64"), { headers: { "content-type": options.contentType ?? "image/png" } }));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

beforeEach(async () => {
  vi.clearAllMocks();
  mocks.env.FAL_KEY = undefined;
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
    expect(request.model).toBe("gemini-nano-banana-2.1");
    expect(request.config.imageConfig).toEqual({ imageSize: "2K" });
    expect(request.contents.parts[0].inlineData).toEqual({ data: source.base64Data, mimeType: source.mimeType });
    expect(fetch).not.toHaveBeenCalled();
  });

  it.each([["EXTERIOR", "16:9"], ["BATHROOM", "3:4"], ["KITCHEN", "4:3"]])(
    "keeps %s text-only framing", async (projectType, aspectRatio) => {
      await generatePreviewImage("Create a concept", { ...context, projectType });
      const request = mocks.generateContent.mock.calls[0][0];
      expect(request.model).toBe("gemini-nano-banana-2.1");
      expect(request.config.imageConfig).toEqual({ imageSize: "2K", aspectRatio });
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
    expect(request.model).toBe("gemini");
    expect(request.task_type).toBe("nano-banana-2.1");
    expect(request.input.resolution).toBe("2K");
    expect(request.input.aspect_ratio).toBe("3:4");
    expect(request.input.image_urls).toEqual([sourceUrl]);
    expect(request.input.prompt).toContain("SAME photograph");
  });

  it("uses Nano Banana 2.1 through PiAPI when Google is not configured", async () => {
    mocks.env.GOOGLE_AI_API_KEY = undefined;
    const fetchMock = mockPiAPISuccess();
    expect(await generatePreviewImage("Create a concept", context)).not.toBeNull();
    expect(mocks.generateContent).not.toHaveBeenCalled();
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).task_type).toBe("nano-banana-2.1");
  });

  it("falls back to PiAPI when Google produces text without an image", async () => {
    mocks.generateContent.mockResolvedValue({ candidates: [{ content: { parts: [{ text: "Unable to generate an image" }] } }] });
    const fetchMock = mockPiAPISuccess();
    expect(await generatePreviewImage("Repaint", context, source, sourceUrl)).not.toBeNull();
    expect(mocks.generateContent).toHaveBeenCalledOnce();
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).task_type).toBe("nano-banana-2.1");
  });

  it("returns the final image instead of an intermediate thinking image", async () => {
    mocks.generateContent.mockResolvedValue({ candidates: [{ content: { parts: [
      { thought: true, inlineData: { data: "intermediate", mimeType: "image/png" } },
      { inlineData: { data: "final", mimeType: "image/png" } },
    ] } }] });
    const result = await generatePreviewImage("Repaint", context, source, sourceUrl);
    expect(result?.base64Data).toBe("final");
    expect(fetch).not.toHaveBeenCalled();
  });

  it.each([undefined, "", "   "])("falls back when Google's final image data is unusable (%s)", async (data) => {
    mocks.generateContent.mockResolvedValue({ candidates: [{ content: { parts: [{ inlineData: { data, mimeType: "image/png" } }] } }] });
    const fetchMock = mockPiAPISuccess();
    const result = await generatePreviewImage("Repaint", context, source, sourceUrl);
    expect(result?.base64Data).toBe(source.base64Data);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).task_type).toBe("nano-banana-2.1");
  });

  it("falls back when Google returns only intermediate thinking images", async () => {
    mocks.generateContent.mockResolvedValue({ candidates: [{ content: { parts: [{ thought: true, inlineData: { data: "intermediate", mimeType: "image/png" } }] } }] });
    const fetchMock = mockPiAPISuccess();
    const result = await generatePreviewImage("Repaint", context, source, sourceUrl);
    expect(result?.base64Data).toBe(source.base64Data);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).task_type).toBe("nano-banana-2.1");
  });

  it("rejects non-image inline data and uses the PiAPI fallback", async () => {
    mocks.generateContent.mockResolvedValue({ candidates: [{ content: { parts: [{ inlineData: { data: "not-an-image", mimeType: "text/plain" } }] } }] });
    const fetchMock = mockPiAPISuccess();
    const result = await generatePreviewImage("Repaint", context, source, sourceUrl);
    expect(result?.base64Data).toBe(source.base64Data);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).task_type).toBe("nano-banana-2.1");
  });

  it("retains PNG compatibility when Google omits the image MIME type", async () => {
    mocks.generateContent.mockResolvedValue({ candidates: [{ content: { parts: [{ inlineData: { data: "final" } }] } }] });
    const result = await generatePreviewImage("Repaint", context, source, sourceUrl);
    expect(result?.base64Data).toBe("final");
    expect(result?.mimeType).toBe("image/png");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("returns null without contacting providers when neither is configured", async () => {
    mocks.env.GOOGLE_AI_API_KEY = undefined;
    mocks.env.PIAPI_API_KEY = undefined;
    expect(await generatePreviewImage("Create a concept", context)).toBeNull();
    expect(mocks.generateContent).not.toHaveBeenCalled();
    expect(fetch).not.toHaveBeenCalled();
  });
});

describe("low-cost primary provider", () => {
  it("uses fal before existing providers and preserves the shared edit prompt", async () => {
    mocks.env.FAL_KEY = "fal-test";
    const taskBase = "https://queue.fal.run/fal-ai/flux-2/requests/primary-task";
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ request_id: "primary-task", status_url: `${taskBase}/status`, response_url: taskBase, cancel_url: `${taskBase}/cancel` })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ status: "COMPLETED" })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ images: [{ url: "https://v3.fal.media/files/test.png" }], has_nsfw_concepts: [false] })))
      .mockResolvedValueOnce(new Response(Buffer.from(source.base64Data, "base64")));
    vi.stubGlobal("fetch", fetchMock);
    expect(await generatePreviewImage("Paint only siding", context, source, sourceUrl)).not.toBeNull();
    expect(fetchMock.mock.calls[0][0]).toBe("https://queue.fal.run/fal-ai/flux-2/flash/edit");
    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(body.prompt).toContain("SAME photograph");
    expect(body.prompt).toContain("Paint only siding");
    expect(mocks.generateContent).not.toHaveBeenCalled();
  });

  it("generates with fal as the only configured image provider", async () => {
    mocks.env.FAL_KEY = "fal-test";
    mocks.env.GOOGLE_AI_API_KEY = undefined;
    mocks.env.PIAPI_API_KEY = undefined;
    const taskBase = "https://queue.fal.run/fal-ai/flux-2/requests/only-fal";
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ request_id: "only-fal", status_url: `${taskBase}/status`, response_url: taskBase, cancel_url: `${taskBase}/cancel` })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ status: "COMPLETED" })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ images: [{ url: "https://v3.fal.media/files/test.png" }], has_nsfw_concepts: [false] })))
      .mockResolvedValueOnce(new Response(Buffer.from(source.base64Data, "base64")));
    vi.stubGlobal("fetch", fetchMock);
    expect(await generatePreviewImage("Paint siding", context, source)).not.toBeNull();
    expect(mocks.generateContent).not.toHaveBeenCalled();
  });

  it("falls back to Google after an operational fal failure", async () => {
    mocks.env.FAL_KEY = "fal-test";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(new Response("{}", { status: 503 })));
    expect((await generatePreviewImage("Repaint", context, source))?.base64Data).toBe("result");
    expect(mocks.generateContent).toHaveBeenCalledOnce();
  });

  it("stops on fal moderation rejection without trying Google or PiAPI", async () => {
    mocks.env.FAL_KEY = "fal-test";
    const fetchMock = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify({ detail: [{ type: "content_policy_violation" }] }), { status: 422 }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await generatePreviewImage("Repaint", context, source, sourceUrl)).toBeNull();
    expect(mocks.generateContent).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledOnce();
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
    expect(request.model).toBe("gemini");
    expect(request.task_type).toBe("nano-banana-2.1");
    expect(request.input.aspect_ratio).toBe("16:9");
    expect(request.input.output_format).toBe("png");
    expect(request.input.resolution).toBe("2K");
    expect(request.input).not.toHaveProperty("image_urls");
    expect(request.input).not.toHaveProperty("safety_level");
  });

  it("keeps reference inputs when falling back from Nano Banana 2.1 to Nano Banana 2", async () => {
    const fetchMock = mockPiAPISuccess();
    fetchMock.mockReset()
      .mockResolvedValueOnce(new Response("Unavailable", { status: 503 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { task_id: "test-task" } })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { status: "completed", output: { image_url: "https://assets.example.test/output.png" } } })))
      .mockResolvedValueOnce(new Response(Buffer.from(source.base64Data, "base64"), { headers: { "content-type": "image/png" } }));
    expect(await generatePreviewImagePiAPI({ userPrompt: "Repaint", context, referencePhoto: source, referenceAssetUrl: sourceUrl })).not.toBeNull();
    for (const index of [0, 1]) {
      const request = JSON.parse(fetchMock.mock.calls[index][1].body);
      expect(request.input.aspect_ratio).toBe("3:4");
      expect(request.input.image_urls).toEqual([sourceUrl]);
      expect(request.input.resolution).toBe("2K");
      expect(request.input.output_format).toBe("png");
      expect(request.input.prompt).toContain("SAME photograph");
      expect(request.input).not.toHaveProperty("safety_level");
    }
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).task_type).toBe("nano-banana-2.1");
    expect(JSON.parse(fetchMock.mock.calls[1][1].body).task_type).toBe("nano-banana-2");
  });

  it("accepts the actual downloaded format even when PNG was requested", async () => {
    mockPiAPISuccess({ contentType: "image/webp; charset=binary" });
    const result = await generatePreviewImagePiAPI({ userPrompt: "Create a concept", context });
    expect(result?.mimeType).toBe("image/webp");
    expect(result?.base64Data).toBe(source.base64Data);
  });

  it("retains compatibility with a singular output image URL", async () => {
    mockPiAPISuccess({ singularOutput: true });
    expect(await generatePreviewImagePiAPI({ userPrompt: "Create a concept", context })).not.toBeNull();
  });

  it("tries the compatibility model when Nano Banana 2.1 finishes without an image", async () => {
    const fetchMock = mockPiAPISuccess();
    fetchMock.mockReset()
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { task_id: "empty-task" } })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { status: "completed", output: null } })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { task_id: "fallback-task" } })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 200, data: { status: "completed", output: { image_urls: ["https://assets.example.test/output.png"] } } })))
      .mockResolvedValueOnce(new Response(Buffer.from(source.base64Data, "base64"), { headers: { "content-type": "image/png" } }));
    expect(await generatePreviewImagePiAPI({ userPrompt: "Create a concept", context })).not.toBeNull();
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).task_type).toBe("nano-banana-2.1");
    expect(JSON.parse(fetchMock.mock.calls[2][1].body).task_type).toBe("nano-banana-2");
  });

  it("returns null when both Nano Banana versions are unavailable", async () => {
    const fetchMock = vi.fn().mockImplementation(async () => new Response("Unavailable", { status: 503 }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await generatePreviewImagePiAPI({ userPrompt: "Repaint", context, referencePhoto: source, referenceAssetUrl: sourceUrl })).toBeNull();
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls.map((call) => JSON.parse(call[1].body).task_type)).toEqual(["nano-banana-2.1", "nano-banana-2"]);
  });
});
