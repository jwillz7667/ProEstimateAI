/**
 * Geographic math utilities. Currently:
 *   - polygonAreaSqMeters: signed surface area of a closed lat/lng polygon
 *     using the spherical-excess formula (no API calls, sub-1% accurate
 *     up to a few hundred meters per side — far better than what a
 *     contractor's rangefinder would give).
 *
 * Lawn polygons are drawn on Apple MapKit on the iOS client; the
 * coordinates come back to the server via `POST /v1/maps/lawn-area` and
 * we compute the area here (not on the client) so the iOS code stays
 * thin and the math has one tested home.
 */

const EARTH_RADIUS_M = 6_378_137; // WGS-84 equatorial radius
const SQ_M_TO_SQ_FT = 10.7639;

export interface LatLng {
  latitude: number;
  longitude: number;
}

/**
 * Surface area in m² of a polygon described by an ordered ring of
 * lat/lng vertices. The ring may be open (last vertex != first); the
 * algorithm closes it implicitly. Returns the absolute value, so vertex
 * winding direction does not matter.
 *
 * Implementation: spherical excess via L'Huilier's theorem on a unit
 * sphere, scaled by Earth's radius squared. Exact on a sphere; the
 * Earth is an oblate spheroid, but for residential parcels the
 * deviation is far below contractor-relevant precision.
 *
 * Throws when the ring has fewer than 3 vertices since you can't bound
 * an area with a line.
 */
export function polygonAreaSqMeters(ring: LatLng[]): number {
  if (ring.length < 3) {
    throw new Error("Polygon ring must have at least 3 vertices");
  }

  let total = 0;
  const n = ring.length;
  for (let i = 0; i < n; i++) {
    const a = ring[i];
    const b = ring[(i + 1) % n];
    total +=
      toRadians(b.longitude - a.longitude) *
      (2 + Math.sin(toRadians(a.latitude)) + Math.sin(toRadians(b.latitude)));
  }
  return Math.abs((total * EARTH_RADIUS_M * EARTH_RADIUS_M) / 2);
}

/**
 * Convenience: polygon area in sq ft (used in DTOs / display).
 */
export function polygonAreaSqFt(ring: LatLng[]): number {
  return polygonAreaSqMeters(ring) * SQ_M_TO_SQ_FT;
}

/**
 * Centroid of a polygon ring, computed as the unweighted lat/lng mean.
 * For the small polygons we'll see (residential / commercial parcels)
 * this is indistinguishable from the proper geodesic centroid and a lot
 * cheaper to compute.
 */
export function polygonCentroid(ring: LatLng[]): LatLng {
  if (ring.length === 0) {
    throw new Error("Cannot take centroid of empty polygon");
  }
  let sumLat = 0;
  let sumLng = 0;
  for (const v of ring) {
    sumLat += v.latitude;
    sumLng += v.longitude;
  }
  return { latitude: sumLat / ring.length, longitude: sumLng / ring.length };
}

function toRadians(deg: number): number {
  return (deg * Math.PI) / 180;
}
