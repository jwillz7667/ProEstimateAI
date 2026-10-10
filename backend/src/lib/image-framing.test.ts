import sharp from "sharp";
import { describe, expect, it } from "vitest";
import { aspectRatioForReferencePhoto, nearestEditAspectRatio } from "./image-framing";

describe("reference photo framing", () => {
  it.each([
    [4032, 3024, "4:3"], [3024, 4032, "3:4"], [1080, 1920, "9:16"],
    [1920, 1080, "16:9"], [1000, 1000, "1:1"], [1500, 1000, "3:2"],
    [1000, 1250, "4:5"], [2390, 1024, "21:9"], [1300, 1000, "4:3"],
  ])("maps %i x %i to %s", (width, height, expected) => {
    expect(nearestEditAspectRatio(width, height)).toBe(expected);
  });

  it.each([[0, 1], [1, 0], [-1, 1], [NaN, 1], [Infinity, 1]])(
    "rejects invalid dimensions %s x %s", (width, height) => {
      expect(() => nearestEditAspectRatio(width, height)).toThrow("valid dimensions");
    },
  );

  it.each([5, 6, 7, 8])("uses displayed dimensions for EXIF orientation %i", async (orientation) => {
    const bytes = await sharp({ create: { width: 120, height: 80, channels: 3, background: "white" } })
      .jpeg().withMetadata({ orientation }).toBuffer();
    expect(await aspectRatioForReferencePhoto({ base64Data: bytes.toString("base64"), mimeType: "image/jpeg" }))
      .toBe("2:3");
  });

  it("rejects unreadable image bytes", async () => {
    await expect(aspectRatioForReferencePhoto({ base64Data: "invalid", mimeType: "image/png" }))
      .rejects.toThrow();
  });
});
