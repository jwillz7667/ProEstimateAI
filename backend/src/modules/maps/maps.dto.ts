import {
  BuildingInsightsResult,
  GeocodeResult,
  RoofSegment,
} from "../../lib/google-maps";

export interface GeocodeDto {
  formatted_address: string;
  latitude: number;
  longitude: number;
  postal_code: string | null;
  city: string | null;
  region: string | null;
}

export function toGeocodeDto(r: GeocodeResult): GeocodeDto {
  return {
    formatted_address: r.formattedAddress,
    latitude: r.latitude,
    longitude: r.longitude,
    postal_code: r.postalCode,
    city: r.city,
    region: r.region,
  };
}

export interface LawnAreaDto {
  area_sq_meters: number;
  area_sq_ft: number;
  /** Polygon centroid — also persisted on the project as property_latitude/longitude. */
  centroid_latitude: number;
  centroid_longitude: number;
}

export interface RoofSegmentDto {
  index: number;
  pitch_degrees: number;
  azimuth_degrees: number;
  area_sq_meters: number;
  area_sq_ft: number;
  center_latitude: number;
  center_longitude: number;
}

export interface RoofScoutingDto {
  building_latitude: number;
  building_longitude: number;
  postal_code: string | null;
  total_roof_area_sq_ft: number;
  segments: RoofSegmentDto[];
  imagery_date: string | null;
  imagery_quality: "HIGH" | "MEDIUM" | "LOW" | null;
}

export function toRoofScoutingDto(r: BuildingInsightsResult): RoofScoutingDto {
  return {
    building_latitude: r.buildingLatitude,
    building_longitude: r.buildingLongitude,
    postal_code: r.postalCode,
    total_roof_area_sq_ft: r.totalRoofAreaSqFt,
    segments: r.segments.map(toRoofSegmentDto),
    imagery_date: r.imageryDate,
    imagery_quality: r.imageryQuality,
  };
}

function toRoofSegmentDto(s: RoofSegment): RoofSegmentDto {
  return {
    index: s.index,
    pitch_degrees: s.pitchDegrees,
    azimuth_degrees: s.azimuthDegrees,
    area_sq_meters: s.planeAreaSqMeters,
    area_sq_ft: s.planeAreaSqFt,
    center_latitude: s.centerLatitude,
    center_longitude: s.centerLongitude,
  };
}
