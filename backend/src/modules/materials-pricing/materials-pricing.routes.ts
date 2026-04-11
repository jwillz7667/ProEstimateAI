import { Router, Request, Response, NextFunction } from 'express';
import { searchHandler, projectMaterialsHandler } from './materials-pricing.controller';
import { validate } from '../../middleware/validate.middleware';
import { searchMaterialsSchema, projectMaterialsSchema } from './materials-pricing.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/materials-pricing/search?query=granite+countertop&zip_code=90210&sort=price_low_to_high
router.get('/search', validate(searchMaterialsSchema, 'query'), asyncHandler(searchHandler));

// GET /v1/materials-pricing/project?project_type=kitchen&zip_code=90210
router.get('/project', validate(projectMaterialsSchema, 'query'), asyncHandler(projectMaterialsHandler));

export default router;
