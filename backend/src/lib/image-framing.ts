import sharp from "sharp";
import type { ReferencePhoto } from "./image-gen";

// Ratios shared by Nano Banana Pro and Nano Banana 2. Do not send arbitrary
// ratios (or an undocumented "auto" value) to the PiAPI task endpoint.
const EDIT_ASPECT_RATIOS = [
  "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9",
] as const;

/** Category framing is appropriate only when there is no source photograph. */
export function aspectRatioForProjectType(projectType: string): string {
  switch (projectType.toUpperCase()) {
    case "EXTERIOR":
    case "ROOFING":
    case "SIDING":
    case "LANDSCAPING":
    case "LAWN_CARE":
      return "16:9";
    case "BATHROOM":
      return "3:4";
    default:
      return "4:3";
  }
}

export function nearestEditAspectRatio(width: number, height: number): string {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    throw new Error("Reference photo must have valid dimensions");
  }

  const inputRatio = width / height;
  return EDIT_ASPECT_RATIOS.reduce((nearest, candidate) => {
    const distance = (ratio: string) => {
      const [w, h] = ratio.split(":").map(Number);
      // Log distance treats equivalent portrait/landscape mismatches equally.
      return Math.abs(Math.log(inputRatio / (w / h)));
    };
    return distance(candidate) < distance(nearest) ? candidate : nearest;
  });
}

/** Read the displayed dimensions, accounting for phone-camera EXIF rotation. */
export async function aspectRatioForReferencePhoto(photo: ReferencePhoto): Promise<string> {
  const metadata = await sharp(Buffer.from(photo.base64Data, "base64")).metadata();
  if (!metadata.width || !metadata.height) {
    throw new Error("Unable to read reference photo dimensions");
  }

  const swapsAxes = metadata.orientation !== undefined
    && metadata.orientation >= 5 && metadata.orientation <= 8;
  return nearestEditAspectRatio(
    swapsAxes ? metadata.height : metadata.width,
    swapsAxes ? metadata.width : metadata.height,
  );
}
