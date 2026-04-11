import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { searchHomeDepot, searchMaterialsForProject } from '../../lib/home-depot';
import { toMaterialPricingDto } from './materials-pricing.dto';
import type { SearchMaterialsInput, ProjectMaterialsInput } from './materials-pricing.validators';

/**
 * GET /v1/materials-pricing/search
 * Search Home Depot for materials by keyword.
 */
export async function searchHandler(req: Request, res: Response) {
  const query = req.query as unknown as SearchMaterialsInput;

  const result = await searchHomeDepot({
    query: query.query,
    zipCode: query.zip_code,
    storeId: query.store_id,
    sort: query.sort,
    page: query.page,
    maxResults: query.max_results,
  });

  sendSuccess(res, {
    products: result.products.map(toMaterialPricingDto),
    total_results: result.total_results,
    store_name: result.store_name,
    query: result.query,
  });
}

/**
 * GET /v1/materials-pricing/project
 * Get categorized materials for a project type with real prices.
 */
export async function projectMaterialsHandler(req: Request, res: Response) {
  const query = req.query as unknown as ProjectMaterialsInput;

  const categorized = await searchMaterialsForProject(
    query.project_type,
    query.zip_code,
  );

  // Transform products to DTOs
  const categories: Record<string, ReturnType<typeof toMaterialPricingDto>[]> = {};
  for (const [category, products] of Object.entries(categorized)) {
    categories[category] = products.map(toMaterialPricingDto);
  }

  sendSuccess(res, {
    categories,
    project_type: query.project_type,
    zip_code: query.zip_code ?? null,
  });
}
