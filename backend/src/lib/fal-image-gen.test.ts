import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import sharp from "sharp";

const mocks = vi.hoisted(() => ({
  env: { FAL_KEY: "fal-test" as string | undefined },
  logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));
vi.mock("../config/env", () => ({ env: mocks.env }));
vi.mock("../config/logger", () => ({ logger: mocks.logger }));

import { generatePreviewImageFal, ImageSafetyError } from "./fal-image-gen";

const requestBase = "https://queue.fal.run/fal-ai/flux-2/requests/test-task";
const task = { request_id: "test-task", status_url: `${requestBase}/status`, response_url: requestBase, cancel_url: `${requestBase}/cancel` };
const outputUrl = "https://v3.fal.media/files/test/output.png";
const prompt = "Preserve the SAME photograph. Change the siding color.";
let source: { base64Data: string; mimeType: string };

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });
}

function mockSuccess(output: Buffer, result: Record<string, unknown> = {}) {
  const fetchMock = vi.fn()
    .mockResolvedValueOnce(json(task))
    .mockResolvedValueOnce(json({ status: "COMPLETED" }))
    .mockResolvedValueOnce(json({ images: [{ url: outputUrl }], has_nsfw_concepts: [false], ...result }))
    .mockResolvedValueOnce(new Response(output, { headers: { "content-type": "image/png" } }));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

async function image(width: number, height: number): Promise<Buffer> {
  return sharp({ create: { width, height, channels: 3, background: "white" } }).png().toBuffer();
}

beforeEach(async () => {
  vi.clearAllMocks();
  mocks.env.FAL_KEY = "fal-test";
  source = { base64Data: (await image(1200, 1600)).toString("base64"), mimeType: "image/png" };
  vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Unexpected provider call")));
});

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

describe("fal FLUX.2 Flash", () => {
  it("sends a camera-preserving reference edit with an oriented, bounded data URI", async () => {
    const fetchMock = mockSuccess(await image(886, 1181));
    const result = await generatePreviewImageFal({ prompt, projectType: "EXTERIOR", referencePhoto: source });
    expect(result?.mimeType).toBe("image/png");
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://queue.fal.run/fal-ai/flux-2/flash/edit");
    expect(init.headers.Authorization).toBe("Key fal-test");
    expect(init.headers["X-Fal-Store-IO"]).toBe("0");
    const body = JSON.parse(init.body);
    expect(body).toMatchObject({ prompt, num_images: 1, enable_prompt_expansion: false, enable_safety_checker: true, output_format: "png" });
    expect(body.image_size.width / body.image_size.height).toBeCloseTo(0.75, 2);
    expect(body.image_size.width * body.image_size.height).toBeLessThanOrEqual(1024 * 1024);
    expect(body.image_urls[0]).toMatch(/^data:image\/png;base64,/);
    const input = await sharp(Buffer.from(body.image_urls[0].split(",")[1], "base64")).metadata();
    expect(input).toMatchObject(body.image_size);
    expect(fetchMock.mock.calls[1][0]).toBe(task.status_url);
    expect(fetchMock.mock.calls[2][0]).toBe(task.response_url);
    expect(fetchMock.mock.calls[3][1]).not.toHaveProperty("headers");
    const output = await sharp(Buffer.from(result!.base64Data, "base64")).metadata();
    expect(output).toMatchObject(body.image_size);
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });

  it("honors EXIF rotation without changing the displayed photo framing", async () => {
    const bytes = await sharp(await image(1600, 1200)).jpeg().withMetadata({ orientation: 6 }).toBuffer();
    const fetchMock = mockSuccess(await image(886, 1181));
    expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR", referencePhoto: { base64Data: bytes.toString("base64"), mimeType: "image/jpeg" } })).not.toBeNull();
    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(body.image_size.width / body.image_size.height).toBeCloseTo(0.75, 2);
  });

  it.each([["EXTERIOR", 16 / 9], ["BATHROOM", 3 / 4], ["KITCHEN", 4 / 3]])("keeps %s category framing for text-only concepts", async (projectType, ratio) => {
    const sizeWidth = Math.floor(Math.sqrt(1024 * 1024 * ratio));
    const sizeHeight = Math.floor(sizeWidth / ratio);
    const fetchMock = mockSuccess(await image(sizeWidth, sizeHeight));
    expect(await generatePreviewImageFal({ prompt, projectType })).not.toBeNull();
    expect(fetchMock.mock.calls[0][0]).toBe("https://queue.fal.run/fal-ai/flux-2/flash");
    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(body).not.toHaveProperty("image_urls");
    expect(body.image_size.width / body.image_size.height).toBeCloseTo(ratio, 2);
  });

  it("does not contact the API when the key is absent", async () => {
    mocks.env.FAL_KEY = undefined;
    expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR" })).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects unreadable or extreme references before billing a task", async () => {
    for (const bytes of [Buffer.from("invalid"), await image(5000, 500)]) {
      expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR", referencePhoto: { base64Data: bytes.toString("base64"), mimeType: "image/png" } })).toBeNull();
    }
    expect(fetch).not.toHaveBeenCalled();
  });

  it("polls a queued request and treats a completed failure as a failure", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(json(task))
      .mockResolvedValueOnce(json({ status: "IN_QUEUE" }))
      .mockResolvedValueOnce(json({ status: "COMPLETED", error_type: "generation_error", error: "Provider unavailable" }));
    vi.stubGlobal("fetch", fetchMock);
    vi.useFakeTimers();
    const pending = generatePreviewImageFal({ prompt, projectType: "EXTERIOR" });
    await vi.advanceTimersByTimeAsync(1_100);
    expect(await pending).toBeNull();
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it.each([
    "https://evil.example/fal-ai/flux-2/requests/test-task/status",
    "http://queue.fal.run/fal-ai/flux-2/requests/test-task/status",
    "https://secret@queue.fal.run/fal-ai/flux-2/requests/test-task/status",
    "https://queue.fal.run/unrelated",
  ])("never forwards credentials to invalid queue URLs: %s", async (status_url) => {
    const fetchMock = vi.fn().mockResolvedValueOnce(json({ ...task, status_url, cancel_url: "https://evil.example/cancel" }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR" })).toBeNull();
    expect(fetchMock).toHaveBeenCalledOnce();
  });

  it.each(["http://127.0.0.1/image.png", "https://evil.example/image.png", "https://v3.fal.media.evil.example/image.png"]) ("rejects untrusted image URLs: %s", async (url) => {
    const fetchMock = mockSuccess(await image(886, 1181), { images: [{ url }] });
    expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR", referencePhoto: source })).toBeNull();
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it.each([Buffer.from("not an image"), null])("rejects invalid images or altered camera framing", async (invalid) => {
    mockSuccess(invalid ?? await image(1024, 1024));
    expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR", referencePhoto: source })).toBeNull();
  });

  it("bounds streamed image downloads even without Content-Length", async () => {
    const fetchMock = mockSuccess(await image(886, 1181));
    fetchMock.mockReset().mockResolvedValueOnce(json(task))
      .mockResolvedValueOnce(json({ status: "COMPLETED" }))
      .mockResolvedValueOnce(json({ images: [{ url: outputUrl }] }))
      .mockResolvedValueOnce(new Response(new ReadableStream({ start(controller) {
        controller.enqueue(new Uint8Array(20 * 1024 * 1024));
        controller.enqueue(new Uint8Array(1));
        controller.close();
      } })));
    expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR" })).toBeNull();
  });

  it.each(["http", "submit", "status", "result"]) ("propagates terminal safety rejection from %s", async (stage) => {
    const fetchMock = vi.fn();
    if (stage === "http") fetchMock.mockResolvedValueOnce(json({ detail: [{ type: "content_policy_violation" }] }, 422));
    if (stage === "submit") fetchMock.mockResolvedValueOnce(json({ error: "content_policy_violation" }));
    if (stage === "status") fetchMock.mockResolvedValueOnce(json(task)).mockResolvedValueOnce(json({ status: "COMPLETED", error_type: "content_policy_violation" }));
    if (stage === "result") fetchMock.mockResolvedValueOnce(json(task)).mockResolvedValueOnce(json({ status: "COMPLETED" })).mockResolvedValueOnce(json({ images: [{ url: outputUrl }], has_nsfw_concepts: [true] }));
    vi.stubGlobal("fetch", fetchMock);
    await expect(generatePreviewImageFal({ prompt, projectType: "EXTERIOR" })).rejects.toBeInstanceOf(ImageSafetyError);
    expect(fetchMock.mock.calls.some(([url]) => url === outputUrl)).toBe(false);
  });

  it("times out the entire lifecycle and cancels the outstanding task", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(json(task))
      .mockImplementationOnce((_url, init) => new Promise((_resolve, reject) => {
        init.signal.addEventListener("abort", () => reject(init.signal.reason), { once: true });
      }))
      .mockResolvedValueOnce(new Response(null, { status: 202 }));
    vi.stubGlobal("fetch", fetchMock);
    vi.useFakeTimers();
    const pending = generatePreviewImageFal({ prompt, projectType: "EXTERIOR" });
    await vi.advanceTimersByTimeAsync(150_100);
    expect(await pending).toBeNull();
    expect(fetchMock.mock.calls[2][0]).toBe(task.cancel_url);
    expect(fetchMock.mock.calls[2][1].method).toBe("PUT");
  });

  it("does not log prompts, API keys, response bodies or source URLs", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(json({ detail: `${prompt} fal-test private-source-url` }, 503)));
    expect(await generatePreviewImageFal({ prompt, projectType: "EXTERIOR" })).toBeNull();
    const logs = JSON.stringify([mocks.logger.info.mock.calls, mocks.logger.warn.mock.calls, mocks.logger.error.mock.calls]);
    expect(logs).not.toContain(prompt);
    expect(logs).not.toContain("fal-test");
    expect(logs).not.toContain("private-source-url");
  });
});
