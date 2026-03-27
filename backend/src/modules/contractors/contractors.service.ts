import { logger } from '../../config/logger';
import { env } from '../../config/env';

export interface ContractorResult {
  name: string;
  address: string;
  rating: number | null;
  totalRatings: number;
  phone: string | null;
  website: string | null;
  placeId: string;
  latitude: number;
  longitude: number;
  openNow: boolean | null;
  priceLevel: number | null;
  types: string[];
}

/**
 * Map project types to Google Places search terms.
 */
function searchTermForProjectType(projectType: string): string {
  const type = projectType.toUpperCase();
  switch (type) {
    case 'KITCHEN': return 'kitchen remodeling contractor';
    case 'BATHROOM': return 'bathroom remodeling contractor';
    case 'FLOORING': return 'flooring installation contractor';
    case 'ROOFING': return 'roofing contractor';
    case 'PAINTING': return 'painting contractor';
    case 'SIDING': return 'siding contractor';
    case 'ROOM_REMODEL': return 'home remodeling contractor';
    case 'EXTERIOR': return 'exterior renovation contractor';
    default: return 'general contractor remodeling';
  }
}

/**
 * Search for contractors near a location using Google Places API (Text Search).
 *
 * Requires GOOGLE_PLACES_API_KEY env var.
 */
export async function searchContractors(
  projectType: string,
  latitude: number,
  longitude: number,
  radiusMiles: number = 25
): Promise<ContractorResult[]> {
  const apiKey = env.GOOGLE_PLACES_API_KEY;
  if (!apiKey) {
    logger.warn('GOOGLE_PLACES_API_KEY not configured — returning empty contractor list');
    return [];
  }

  const searchTerm = searchTermForProjectType(projectType);
  const radiusMeters = Math.round(radiusMiles * 1609.34);

  try {
    const url = 'https://places.googleapis.com/v1/places:searchText';
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.rating,places.userRatingCount,places.nationalPhoneNumber,places.websiteUri,places.id,places.location,places.currentOpeningHours,places.priceLevel,places.types',
      },
      body: JSON.stringify({
        textQuery: searchTerm,
        locationBias: {
          circle: {
            center: { latitude, longitude },
            radius: radiusMeters,
          },
        },
        maxResultCount: 20,
        languageCode: 'en',
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      logger.error({ status: response.status, body: errText }, 'Google Places API error');
      return [];
    }

    const data: any = await response.json();
    const places: any[] = data.places || [];

    const results: ContractorResult[] = places.map((place: any) => ({
      name: place.displayName?.text || 'Unknown',
      address: place.formattedAddress || '',
      rating: place.rating ?? null,
      totalRatings: place.userRatingCount ?? 0,
      phone: place.nationalPhoneNumber ?? null,
      website: place.websiteUri ?? null,
      placeId: place.id || '',
      latitude: place.location?.latitude ?? 0,
      longitude: place.location?.longitude ?? 0,
      openNow: place.currentOpeningHours?.openNow ?? null,
      priceLevel: place.priceLevel ?? null,
      types: place.types || [],
    }));

    // Sort by rating (highest first), then by number of ratings
    results.sort((a, b) => {
      const ratingA = a.rating ?? 0;
      const ratingB = b.rating ?? 0;
      if (ratingB !== ratingA) return ratingB - ratingA;
      return b.totalRatings - a.totalRatings;
    });

    logger.info({ count: results.length, searchTerm }, 'Contractor search completed');
    return results;
  } catch (err) {
    logger.error({ err }, 'Contractor search failed');
    return [];
  }
}
