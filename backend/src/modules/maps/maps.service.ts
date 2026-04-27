import { prisma } from "../../config/database";
import { logger } from "../../config/logger";
import { NotFoundError, ValidationError } from "../../lib/errors";
import {
  buildingInsights,
  BuildingInsightsResult,
  geocodeAddress,
  GeocodeResult,
  GoogleMapsConfigError,
  GoogleMapsRequestError,
  staticMapBytes,
  StaticMapOptions,
} from "../../lib/google-maps";
import {
  polygonAreaSqFt,
  polygonAreaSqMeters,
  polygonCentroid,
} from "../../lib/geo";
import {
  GeocodeInput,
  LawnAreaInput,
  RoofScoutingInput,
  StaticMapQuery,
} from "./maps.validators";

/**
 * Wraps the Google Maps client. Each handler:
 *   1. Validates feature availability (config error → 503 from controller).
 *   2. Calls the Google API.
 *   3. Optionally writes the result back to a project (e.g. roof scouting
 *      saves the measured roof area + lat/lng so the next AI generation
 *      uses them automatically).
 */

export async function geocode(
  input: GeocodeInput,
): Promise<GeocodeResult | null> {
  return geocodeAddress(input.address);
}

export interface LawnAreaServiceResult {
  areaSqMeters: number;
  areaSqFt: number;
  centroidLatitude: number;
  centroidLongitude: number;
}

export async function measureLawn(
  input: LawnAreaInput,
  companyId: string,
): Promise<LawnAreaServiceResult> {
  const ring = input.polygon.map((p) => ({
    latitude: p.latitude,
    longitude: p.longitude,
  }));
  const areaSqMeters = polygonAreaSqMeters(ring);
  const areaSqFt = polygonAreaSqFt(ring);
  const centroid = polygonCentroid(ring);

  // Sanity check: anything > 1 sq mile is almost certainly a misdrawn
  // polygon (e.g. user crossed an ocean by accident). Refuse it so the
  // contractor sees an error instead of bidding a $40,000 mowing job.
  const oneSquareMileSqM = 2_589_988;
  if (areaSqMeters > oneSquareMileSqM) {
    throw new ValidationError(
      "Polygon spans more than one square mile — please redraw to bound just the lawn area",
    );
  }

  if (input.project_id) {
    await persistLawnMeasurement(
      input.project_id,
      companyId,
      areaSqFt,
      centroid.latitude,
      centroid.longitude,
    );
  }

  return {
    areaSqMeters,
    areaSqFt,
    centroidLatitude: centroid.latitude,
    centroidLongitude: centroid.longitude,
  };
}

export async function scoutRoof(
  input: RoofScoutingInput,
  companyId: string,
): Promise<{
  result: BuildingInsightsResult;
  resolvedAddress: string | null;
} | null> {
  let lat = input.latitude ?? null;
  let lng = input.longitude ?? null;
  let resolvedAddress: string | null = null;

  if (lat == null || lng == null) {
    if (!input.address) {
      throw new ValidationError(
        "Either address or latitude+longitude must be provided",
      );
    }
    const geocoded = await geocodeAddress(input.address);
    if (!geocoded) return null;
    lat = geocoded.latitude;
    lng = geocoded.longitude;
    resolvedAddress = geocoded.formattedAddress;
  }

  const result = await buildingInsights(lat, lng);
  if (!result) return null;

  if (input.project_id) {
    await persistRoofMeasurement(
      input.project_id,
      companyId,
      result.totalRoofAreaSqFt,
      result.buildingLatitude,
      result.buildingLongitude,
    );
  }

  return { result, resolvedAddress };
}

export async function staticMap(
  query: StaticMapQuery,
): Promise<{ data: Buffer; mimeType: string }> {
  const opts: StaticMapOptions = {
    latitude: query.latitude,
    longitude: query.longitude,
    zoom: query.zoom,
    widthPx: query.width,
    heightPx: query.height,
    mapType: query.maptype,
    retina: query.retina,
  };
  return staticMapBytes(opts);
}

async function persistLawnMeasurement(
  projectId: string,
  companyId: string,
  lawnAreaSqFt: number,
  latitude: number,
  longitude: number,
): Promise<void> {
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
    select: { id: true },
  });
  if (!project) {
    throw new NotFoundError("Project", projectId);
  }
  await prisma.project.update({
    where: { id: projectId },
    data: {
      lawnAreaSqFt: lawnAreaSqFt,
      propertyLatitude: latitude,
      propertyLongitude: longitude,
    },
  });
  logger.info(
    { projectId, lawnAreaSqFt, latitude, longitude },
    "Lawn measurement saved to project",
  );
}

async function persistRoofMeasurement(
  projectId: string,
  companyId: string,
  roofAreaSqFt: number,
  latitude: number,
  longitude: number,
): Promise<void> {
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
    select: { id: true },
  });
  if (!project) {
    throw new NotFoundError("Project", projectId);
  }
  await prisma.project.update({
    where: { id: projectId },
    data: {
      roofAreaSqFt: roofAreaSqFt,
      propertyLatitude: latitude,
      propertyLongitude: longitude,
    },
  });
  logger.info(
    { projectId, roofAreaSqFt, latitude, longitude },
    "Roof scouting saved to project",
  );
}

// Re-export so the controller can `instanceof`-check without re-importing
// from `lib/google-maps.ts`.
export { GoogleMapsConfigError, GoogleMapsRequestError };
