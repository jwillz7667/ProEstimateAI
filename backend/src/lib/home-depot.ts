import { env } from '../config/env';
import { logger } from '../config/logger';

// ---------------------------------------------------------------------------
// Types — SerpApi Home Depot Response
// ---------------------------------------------------------------------------

export interface HomeDepotProduct {
  position: number;
  product_id: string;
  title: string;
  brand: string;
  price: number | null;
  price_was: number | null;
  price_saving: string | null;
  percentage_off: number | null;
  rating: number | null;
  reviews: number | null;
  model_number: string | null;
  link: string;
  thumbnails: string[];
  delivery: {
    free: boolean;
    scheduled?: boolean;
  } | null;
  pickup: {
    free: boolean;
  } | null;
  badges: string[];
}

interface SerpApiSearchResponse {
  search_metadata: {
    status: string;
    id: string;
    total_time_taken: number;
  };
  search_information?: {
    total_results: number;
    query_displayed: string;
    store_name?: string;
  };
  products?: HomeDepotProduct[];
  error?: string;
}

export interface HomeDepotSearchParams {
  query: string;
  zipCode?: string;
  storeId?: string;
  sort?: 'top_sellers' | 'price_low_to_high' | 'price_high_to_low' | 'top_rated' | 'best_match';
  page?: number;
  maxResults?: number;
}

export interface HomeDepotSearchResult {
  products: HomeDepotProduct[];
  total_results: number;
  store_name: string | null;
  query: string;
}

// ---------------------------------------------------------------------------
// API Client
// ---------------------------------------------------------------------------

const SERPAPI_BASE = 'https://serpapi.com/search';

/**
 * Search Home Depot products via SerpApi.
 * Returns real-time retail prices, availability, and product details.
 */
export async function searchHomeDepot(
  params: HomeDepotSearchParams,
): Promise<HomeDepotSearchResult> {
  if (!env.SERPAPI_API_KEY) {
    logger.warn('SERPAPI_API_KEY not configured — Home Depot search unavailable');
    return { products: [], total_results: 0, store_name: null, query: params.query };
  }

  const searchParams = new URLSearchParams({
    engine: 'home_depot',
    q: params.query,
    api_key: env.SERPAPI_API_KEY,
    output: 'json',
  });

  if (params.zipCode) {
    searchParams.set('delivery_zip', params.zipCode);
  }
  if (params.storeId) {
    searchParams.set('store_id', params.storeId);
  }
  if (params.sort) {
    searchParams.set('hd_sort', params.sort);
  }
  if (params.page && params.page > 1) {
    // Home Depot uses offset-based pagination, 24 per page
    searchParams.set('nao', String((params.page - 1) * 24));
  }
  if (params.maxResults) {
    searchParams.set('ps', String(Math.min(params.maxResults, 48)));
  }

  const url = `${SERPAPI_BASE}?${searchParams.toString()}`;

  logger.info(
    { query: params.query, zipCode: params.zipCode, sort: params.sort },
    'Searching Home Depot via SerpApi',
  );

  const response = await fetch(url);

  if (!response.ok) {
    const text = await response.text();
    logger.error({ status: response.status, body: text }, 'SerpApi Home Depot request failed');
    throw new Error(`SerpApi request failed: ${response.status}`);
  }

  const data = (await response.json()) as SerpApiSearchResponse;

  if (data.error) {
    logger.error({ error: data.error }, 'SerpApi returned error');
    throw new Error(`SerpApi error: ${data.error}`);
  }

  const products = data.products ?? [];

  logger.info(
    { resultCount: products.length, totalResults: data.search_information?.total_results },
    'Home Depot search completed',
  );

  return {
    products,
    total_results: data.search_information?.total_results ?? products.length,
    store_name: data.search_information?.store_name ?? null,
    query: params.query,
  };
}

/**
 * Search for construction materials by project type.
 * Returns categorized results for common materials.
 */
export async function searchMaterialsForProject(
  projectType: string,
  zipCode?: string,
): Promise<Record<string, HomeDepotProduct[]>> {
  const materialQueries = getMaterialQueriesForProjectType(projectType);
  const results: Record<string, HomeDepotProduct[]> = {};

  // Run searches in parallel (max 3 concurrent to respect rate limits)
  const batchSize = 3;
  for (let i = 0; i < materialQueries.length; i += batchSize) {
    const batch = materialQueries.slice(i, i + batchSize);
    const batchResults = await Promise.all(
      batch.map(async ({ category, query }) => {
        try {
          const result = await searchHomeDepot({
            query,
            zipCode,
            sort: 'top_sellers',
            maxResults: 12,
          });
          return { category, products: result.products };
        } catch (error) {
          logger.warn({ category, query, error }, 'Failed to search Home Depot for category');
          return { category, products: [] };
        }
      }),
    );
    for (const { category, products } of batchResults) {
      results[category] = products;
    }
  }

  return results;
}

// ---------------------------------------------------------------------------
// Project Type → Material Queries Mapping
// ---------------------------------------------------------------------------

interface MaterialQuery {
  category: string;
  query: string;
}

function getMaterialQueriesForProjectType(projectType: string): MaterialQuery[] {
  const type = projectType.toLowerCase();

  switch (type) {
    case 'kitchen':
      return [
        { category: 'Cabinets', query: 'kitchen cabinets' },
        { category: 'Countertops', query: 'granite countertop kitchen' },
        { category: 'Flooring', query: 'kitchen floor tile' },
        { category: 'Backsplash', query: 'kitchen backsplash tile' },
        { category: 'Fixtures', query: 'kitchen sink faucet' },
        { category: 'Lighting', query: 'kitchen recessed lighting' },
        { category: 'Hardware', query: 'cabinet hardware pulls handles' },
        { category: 'Appliances', query: 'kitchen appliance package' },
      ];

    case 'bathroom':
      return [
        { category: 'Vanity', query: 'bathroom vanity with sink' },
        { category: 'Tile', query: 'bathroom floor tile' },
        { category: 'Shower', query: 'shower surround kit' },
        { category: 'Toilet', query: 'toilet' },
        { category: 'Fixtures', query: 'bathroom faucet' },
        { category: 'Lighting', query: 'bathroom vanity light' },
        { category: 'Hardware', query: 'towel bar bathroom accessories' },
      ];

    case 'flooring':
      return [
        { category: 'Hardwood', query: 'hardwood flooring' },
        { category: 'Laminate', query: 'laminate flooring' },
        { category: 'Vinyl', query: 'luxury vinyl plank flooring' },
        { category: 'Tile', query: 'porcelain floor tile' },
        { category: 'Underlayment', query: 'flooring underlayment' },
        { category: 'Trim', query: 'floor transition trim molding' },
      ];

    case 'roofing':
      return [
        { category: 'Shingles', query: 'architectural roof shingles' },
        { category: 'Underlayment', query: 'roof underlayment' },
        { category: 'Flashing', query: 'roof flashing' },
        { category: 'Ventilation', query: 'roof vent' },
        { category: 'Gutters', query: 'rain gutter' },
      ];

    case 'painting':
      return [
        { category: 'Interior Paint', query: 'interior wall paint gallon' },
        { category: 'Exterior Paint', query: 'exterior house paint' },
        { category: 'Primer', query: 'paint primer' },
        { category: 'Supplies', query: 'paint roller brush kit' },
        { category: 'Tape', query: 'painters tape' },
        { category: 'Caulk', query: 'paintable caulk' },
      ];

    case 'siding':
      return [
        { category: 'Vinyl Siding', query: 'vinyl siding' },
        { category: 'Fiber Cement', query: 'fiber cement siding HardiePlank' },
        { category: 'Trim', query: 'exterior trim board' },
        { category: 'Wrap', query: 'house wrap' },
        { category: 'Fasteners', query: 'siding nails fasteners' },
      ];

    case 'exterior':
      return [
        { category: 'Decking', query: 'composite decking board' },
        { category: 'Fencing', query: 'privacy fence panel' },
        { category: 'Pavers', query: 'patio paver stone' },
        { category: 'Landscaping', query: 'landscape edging' },
        { category: 'Lighting', query: 'outdoor landscape lighting' },
      ];

    default: // ROOM_REMODEL or CUSTOM
      return [
        { category: 'Drywall', query: 'drywall sheet 4x8' },
        { category: 'Lumber', query: '2x4 lumber stud' },
        { category: 'Insulation', query: 'fiberglass insulation batt' },
        { category: 'Paint', query: 'interior wall paint gallon' },
        { category: 'Flooring', query: 'luxury vinyl plank flooring' },
        { category: 'Electrical', query: 'electrical outlet switch' },
        { category: 'Plumbing', query: 'PEX pipe fitting' },
      ];
  }
}
