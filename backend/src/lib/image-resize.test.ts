import sharp from "sharp";
import { describe, expect, it, vi } from "vitest";
vi.mock("../config/logger", () => ({ logger: { warn: vi.fn() } }));
import { resizeImage } from "./image-resize";
async function fixture(format: "png" | "jpeg" | "webp", color = "red", width = 320, height = 160) {
  return sharp({ create: { width, height, channels: 4, background: color } }).toFormat(format).toBuffer();
}
describe("native image processing compatibility", () => {
  it.each(["png", "jpeg", "webp"] as const)("decodes %s and emits correctly sized progressive JPEG", async (format) => {
    const result = await resizeImage(`format-${format}`, await fixture(format), 200);
    const metadata = await sharp(result.data).metadata();
    expect(result.mimeType).toBe("image/jpeg");
    expect(metadata).toMatchObject({ format: "jpeg", width: 240, height: 120, isProgressive: true });
  });
  it("does not enlarge a small source", async () => {
    const result = await resizeImage("small", await fixture("png", "blue", 20, 10), 960);
    expect(await sharp(result.data).metadata()).toMatchObject({ width: 20, height: 10 });
  });
  it("flattens transparency against white", async () => {
    const input = await sharp({ create: { width: 10, height: 10, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).png().toBuffer();
    const result = await resizeImage("transparent", input, 240);
    const pixels = await sharp(result.data).raw().toBuffer();
    expect([...pixels.subarray(0, 3)]).toEqual([255, 255, 255]);
  });
  it("replaces a mutable logo even with the same record ID and width", async () => {
    const oldImage = await resizeImage("mutable-logo", await fixture("png", "red"), 240);
    const newImage = await resizeImage("mutable-logo", await fixture("png", "blue"), 240);
    expect(newImage.data.equals(oldImage.data)).toBe(false);
    const pixels = await sharp(newImage.data).raw().toBuffer();
    expect(pixels[2]).toBeGreaterThan(240);
    expect(pixels[0]).toBeLessThan(15);
  });
  it("deduplicates identical concurrent input without mixing changed content", async () => {
    const source = await fixture("webp");
    const [a, b] = await Promise.all([resizeImage("concurrent", source, 240), resizeImage("concurrent", source, 240)]);
    expect(a).toBe(b);
  });
  it("rejects invalid data and permits a later valid source", async () => {
    await expect(resizeImage("invalid-then-valid", Buffer.from("not an image"), 240)).rejects.toThrow();
    await expect(resizeImage("invalid-then-valid", await fixture("png"), 240)).resolves.toMatchObject({ mimeType: "image/jpeg" });
  });
});
