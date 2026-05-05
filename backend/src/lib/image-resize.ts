import sharp from "sharp";
import { logger } from "../config/logger";

/**
 * On-the-fly thumbnail resizer for the public image endpoints.
 *
 * Two layers of protection keep this from blowing up under load:
 *
 *   1. Width snapping. Arbitrary `?w=` values are snapped to one of three
 *      canonical buckets (240 / 480 / 960). That bounds the cache key
 *      space — without it, every distinct DPR / device pixel width would
 *      generate a unique buffer in the LRU.
 *
 *   2. In-flight dedup. Concurrent requests for the same `(id, width,
 *      mimeType)` tuple wait on the same Promise instead of each spawning
 *      its own sharp pipeline. Without this, a dashboard with N visible
 *      cards would trigger N parallel sharp invocations on first load.
 *
 * The LRU itself is intentionally tiny (~200 entries, one mid-size JPEG
 * each — ~20MB upper bound). Behind it sits the immutable HTTP cache
 * (`Cache-Control: public, max-age=31536000`), so a cold buffer is the
 * exception once the CDN / client caches warm up.
 */

export const ALLOWED_WIDTHS = [240, 480, 960] as const;
export type ThumbnailWidth = (typeof ALLOWED_WIDTHS)[number];

const MAX_CACHE_ENTRIES = 200;

interface CacheEntry {
  data: Buffer;
  mimeType: string;
}

const cache = new Map<string, CacheEntry>();
const inflight = new Map<string, Promise<CacheEntry>>();

function snapWidth(requested: number): ThumbnailWidth {
  // Pick the smallest bucket that is >= the requested width. Falling back
  // to the largest bucket on overshoot keeps the contract predictable
  // (the caller gets at least the resolution they asked for, modulo the
  // source asset being smaller — which `withoutEnlargement` handles).
  for (const w of ALLOWED_WIDTHS) {
    if (w >= requested) return w;
  }
  return ALLOWED_WIDTHS[ALLOWED_WIDTHS.length - 1];
}

function cacheKey(id: string, width: ThumbnailWidth): string {
  return `${id}:${width}`;
}

function touch(key: string, entry: CacheEntry) {
  // Map preserves insertion order — re-set bumps the entry to the tail,
  // turning the Map into a hand-rolled LRU without an extra structure.
  cache.delete(key);
  cache.set(key, entry);
  while (cache.size > MAX_CACHE_ENTRIES) {
    const oldest = cache.keys().next().value;
    if (oldest === undefined) break;
    cache.delete(oldest);
  }
}

/**
 * Resize `source` to the given snapped width, encoded as a progressive
 * mozjpeg buffer. Used as the inner work for the cache; not safe to call
 * directly because it doesn't dedup concurrent invocations.
 */
async function runResize(
  source: Buffer,
  width: ThumbnailWidth,
): Promise<CacheEntry> {
  // Flatten any alpha channel against white before JPEG encoding —
  // company logos arrive as transparent PNGs and sharp's default
  // flatten color is black, which would render them as a black square
  // on the (light) settings background.
  const data = await sharp(source, { failOn: "none" })
    .rotate() // honor EXIF orientation so portrait photos don't render sideways
    .resize({
      width,
      withoutEnlargement: true,
      fit: "inside",
    })
    .flatten({ background: { r: 255, g: 255, b: 255 } })
    .jpeg({ quality: 82, progressive: true, mozjpeg: true })
    .toBuffer();

  return { data, mimeType: "image/jpeg" };
}

/**
 * Resolve a thumbnail variant for a public image. Cached on `(id, width)`.
 *
 * The caller passes `id` purely as a cache discriminator — it must be
 * stable per source buffer. For our public handlers that's the
 * generation/asset/logo CUID, which is stable for the life of the record.
 */
export async function resizeImage(
  id: string,
  source: Buffer,
  requestedWidth: number,
): Promise<CacheEntry> {
  const width = snapWidth(requestedWidth);
  const key = cacheKey(id, width);

  const cached = cache.get(key);
  if (cached) {
    touch(key, cached);
    return cached;
  }

  const existing = inflight.get(key);
  if (existing) return existing;

  const promise = (async () => {
    try {
      const entry = await runResize(source, width);
      touch(key, entry);
      return entry;
    } catch (err) {
      logger.warn(
        { id, width, err },
        "image-resize failed; caller will fall back to original buffer",
      );
      throw err;
    } finally {
      inflight.delete(key);
    }
  })();

  inflight.set(key, promise);
  return promise;
}

/**
 * Parse a `?w=…` query string into a positive integer width, or `null`
 * when absent / malformed. Caller is responsible for clamping (delegates
 * to `snapWidth` once a valid integer is in hand).
 */
export function parseWidthParam(raw: unknown): number | null {
  if (typeof raw !== "string" || raw.length === 0) return null;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n) || n <= 0) return null;
  // Hard ceiling — anything above the largest allowed bucket would only
  // round back down anyway, but rejecting absurd values up front keeps
  // log noise low and stops parameter pollution attacks from filling the
  // request log with garbage values.
  if (n > 4096) return null;
  return n;
}
