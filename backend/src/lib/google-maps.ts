import { env } from "../config/env";
import { logger } from "../config/logger";

/**
 * Typed wrappers around the three Google Cloud APIs we depend on for
 * property scouting:
 *
 *   - Geocoding API          → `geocodeAddress`
 *   - Maps Static API        → `staticMapBytes` (proxied so the key stays server-side)
 *   - Solar API (Building   → `buildingInsights`
 *      Insights)
 *
 * All three live under the same `GOOGLE_MAPS_API_KEY` server-side env. The
 * iOS client never sees the key — it talks to our `/v1/maps/*` endpoints
 * which call out from here.
 */

const GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json";
const STATIC_MAP_URL = "https://maps.googleapis.com/maps/api/staticmap";
const SOLAR_BUILDING_INSIGHTS_URL =
  "https://solar.googleapis.com/v1/buildingInsights:findClosest";

const REQUEST_TIMEOUT_MS = 15_000;

export class GoogleMapsConfigError extends Error {
  constructor() {
    super("GOOGLE_MAPS_API_KEY is not configured");
    this.name = "GoogleMapsConfigError";
  }
}

export class GoogleMapsRequestError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly upstreamBody?: string,
  ) {
    super(message);
    this.name = "GoogleMapsRequestError";
  }
}

function requireKey(): string {
  if (!env.GOOGLE_MAPS_API_KEY) {
    throw new GoogleMapsConfigError();
  }
  return env.GOOGLE_MAPS_API_KEY;
}

async function fetchWithTimeout(
  url: string,
  init?: RequestInit,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

// ─── Geocoding API ──────────────────────────────────────────────────────────

export interface GeocodeResult {
  /** The formatted address Google decided on. May not match the input verbatim. */
  formattedAddress: string;
  latitude: number;
  longitude: number;
  /** Free-form ZIP / postal code component, when present. */
  postalCode: string | null;
  /** Free-form city / locality component, when present. */
  city: string | null;
  /** Free-form region (US state) component, when present. */
  region: string | null;
}

interface GeocodingResponse {
  status: string;
  error_message?: string;
  results?: Array<{
    formatted_address: string;
    geometry: { location: { lat: number; lng: number } };
    address_components: Array<{
      long_name: string;
      short_name: string;
      types: string[];
    }>;
  }>;
}

/**
 * Resolve a free-form street address to a canonical geocoded result.
 * Returns `null` when Google reports `ZERO_RESULTS` — that's a missing
 * address, not a server error, so callers can produce a 404 to the iOS
 * client without alarming logging.
 */
export async function geocodeAddress(
  address: string,
): Promise<GeocodeResult | null> {
  const key = requireKey();
  const url = `${GEOCODE_URL}?address=${encodeURIComponent(address)}&key=${key}`;
  const response = await fetchWithTimeout(url);
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new GoogleMapsRequestError(
      response.status,
      `Geocoding HTTP ${response.status}`,
      body.slice(0, 500),
    );
  }
  const payload = (await response.json()) as GeocodingResponse;
  if (payload.status === "ZERO_RESULTS") {
    return null;
  }
  if (payload.status !== "OK" || !payload.results?.length) {
    logger.warn(
      { status: payload.status, error: payload.error_message },
      "Geocoding non-OK response",
    );
    throw new GoogleMapsRequestError(
      502,
      `Geocoding status ${payload.status}: ${payload.error_message ?? "unknown"}`,
    );
  }

  const top = payload.results[0];
  const components = top.address_components;
  const find = (type: string) =>
    components.find((c) => c.types.includes(type))?.long_name ?? null;

  return {
    formattedAddress: top.formatted_address,
    latitude: top.geometry.location.lat,
    longitude: top.geometry.location.lng,
    postalCode: find("postal_code"),
    city: find("locality") ?? find("postal_town") ?? find("sublocality"),
    region: find("administrative_area_level_1"),
  };
}

// ─── Maps Static API ────────────────────────────────────────────────────────

export interface StaticMapOptions {
  latitude: number;
  longitude: number;
  /** Zoom 1 (world) – 21 (close-up). Roof scouting wants 19–20. */
  zoom: number;
  /** Width / height in pixels. Capped at 640 in the URL signing tier. */
  widthPx: number;
  heightPx: number;
  /** Map type — `satellite` for property scouting; `roadmap` for context. */
  mapType: "satellite" | "roadmap" | "hybrid" | "terrain";
  /** When true, request 2x pixel density for retina rendering on iOS. */
  retina: boolean;
}

/**
 * Fetch a static map image. Returns the raw bytes so we can proxy them to
 * the iOS client without leaking the API key. The Static Maps API caps
 * images at 640x640 unless you pay for premium signing — we stay within
 * that cap and use `scale=2` for retina.
 */
export async function staticMapBytes(
  opts: StaticMapOptions,
): Promise<{ data: Buffer; mimeType: string }> {
  const key = requireKey();
  const params = new URLSearchParams({
    center: `${opts.latitude},${opts.longitude}`,
    zoom: String(opts.zoom),
    size: `${opts.widthPx}x${opts.heightPx}`,
    maptype: opts.mapType,
    scale: opts.retina ? "2" : "1",
    key,
  });
  const url = `${STATIC_MAP_URL}?${params.toString()}`;
  const response = await fetchWithTimeout(url);
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new GoogleMapsRequestError(
      response.status,
      `Static Maps HTTP ${response.status}`,
      body.slice(0, 500),
    );
  }
  const contentType = response.headers.get("content-type") ?? "image/png";
  const arrayBuffer = await response.arrayBuffer();
  return {
    data: Buffer.from(arrayBuffer),
    mimeType: contentType.split(";")[0].trim(),
  };
}

// ─── Solar API: Building Insights ───────────────────────────────────────────

export interface RoofSegment {
  /** 1-based segment number for display. */
  index: number;
  /** Pitch in degrees (0 = flat, 90 = vertical). */
  pitchDegrees: number;
  /** Compass azimuth in degrees (0 = N, 90 = E, 180 = S, 270 = W). */
  azimuthDegrees: number;
  /** Plane area in m² as Google measured it. */
  planeAreaSqMeters: number;
  /** Plane area in sq ft for display + estimating. */
  planeAreaSqFt: number;
  /** Center latitude of the segment. */
  centerLatitude: number;
  /** Center longitude of the segment. */
  centerLongitude: number;
}

export interface BuildingInsightsResult {
  /** The address Google snapped to (may differ slightly from input). */
  postalCode: string | null;
  /** Center of the building footprint. */
  buildingLatitude: number;
  buildingLongitude: number;
  /** Total roof area summed across all segments, in sq ft. */
  totalRoofAreaSqFt: number;
  /** Per-segment breakdown sorted largest → smallest. */
  segments: RoofSegment[];
  /** ISO 8601 of when Google's imagery for this lookup was captured. */
  imageryDate: string | null;
  /** Google's coverage quality flag — informs whether estimates are trustworthy. */
  imageryQuality: "HIGH" | "MEDIUM" | "LOW" | null;
}

interface BuildingInsightsResponse {
  name?: string;
  center?: { latitude: number; longitude: number };
  postalCode?: string;
  imageryDate?: { year: number; month: number; day: number };
  imageryQuality?: "HIGH" | "MEDIUM" | "LOW";
  solarPotential?: {
    roofSegmentStats?: Array<{
      pitchDegrees?: number;
      azimuthDegrees?: number;
      stats?: { areaMeters2?: number };
      center?: { latitude: number; longitude: number };
    }>;
  };
  error?: { code: number; message: string; status: string };
}

const SQ_M_TO_SQ_FT = 10.7639;

/**
 * Look up the closest building footprint to a given lat/lng and return its
 * roof segments. Used by the iOS roof-scouting screen to populate accurate
 * roof area before the contractor sends a quote.
 *
 * Returns `null` when the API responds 404 (no building data for the
 * coordinate). Throws `GoogleMapsRequestError` for transport / API
 * errors so the controller can map to a 502.
 */
export async function buildingInsights(
  latitude: number,
  longitude: number,
): Promise<BuildingInsightsResult | null> {
  const key = requireKey();
  const params = new URLSearchParams({
    "location.latitude": String(latitude),
    "location.longitude": String(longitude),
    requiredQuality: "LOW",
    key,
  });
  const url = `${SOLAR_BUILDING_INSIGHTS_URL}?${params.toString()}`;
  const response = await fetchWithTimeout(url);

  if (response.status === 404) {
    return null;
  }
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new GoogleMapsRequestError(
      response.status,
      `Solar API HTTP ${response.status}`,
      body.slice(0, 500),
    );
  }

  const payload = (await response.json()) as BuildingInsightsResponse;
  if (payload.error) {
    throw new GoogleMapsRequestError(
      502,
      `Solar API ${payload.error.status}: ${payload.error.message}`,
    );
  }

  const rawSegments = payload.solarPotential?.roofSegmentStats ?? [];
  const segments: RoofSegment[] = rawSegments
    .map((s, idx) => {
      const sqM = s.stats?.areaMeters2 ?? 0;
      return {
        index: idx + 1,
        pitchDegrees: s.pitchDegrees ?? 0,
        azimuthDegrees: s.azimuthDegrees ?? 0,
        planeAreaSqMeters: sqM,
        planeAreaSqFt: sqM * SQ_M_TO_SQ_FT,
        centerLatitude: s.center?.latitude ?? 0,
        centerLongitude: s.center?.longitude ?? 0,
      };
    })
    .filter((s) => s.planeAreaSqMeters > 0)
    .sort((a, b) => b.planeAreaSqFt - a.planeAreaSqFt)
    .map((s, idx) => ({ ...s, index: idx + 1 }));

  const totalSqFt = segments.reduce((acc, s) => acc + s.planeAreaSqFt, 0);

  const imageryDateIso = payload.imageryDate
    ? new Date(
        Date.UTC(
          payload.imageryDate.year,
          payload.imageryDate.month - 1,
          payload.imageryDate.day,
        ),
      ).toISOString()
    : null;

  return {
    postalCode: payload.postalCode ?? null,
    buildingLatitude: payload.center?.latitude ?? latitude,
    buildingLongitude: payload.center?.longitude ?? longitude,
    totalRoofAreaSqFt: totalSqFt,
    segments,
    imageryDate: imageryDateIso,
    imageryQuality: payload.imageryQuality ?? null,
  };
}
