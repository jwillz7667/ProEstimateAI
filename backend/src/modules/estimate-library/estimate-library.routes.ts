import { Router, Request, Response, NextFunction } from 'express';
import { validate } from '../../middleware/validate.middleware';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import { toEstimateDto } from '../estimates/estimates.dto';
import { toEstimateLineItemDto } from '../estimate-line-items/estimate-line-items.dto';
import { applyItemSchema, duplicateEstimateSchema, instantiateTemplateSchema, librarySearchSchema, saveItemSchema, saveTemplateSchema } from './estimate-library.validators';
import * as library from './estimate-library.service';

const router = Router();
const handler = (fn: (req: Request, res: Response) => Promise<void>) =>
  (req: Request, res: Response, next: NextFunction) => { fn(req, res).catch(next); };

router.get('/templates', validate(librarySearchSchema, 'query'), handler(async (req, res) => {
  const result = await library.listTemplates(req.companyId!, librarySearchSchema.parse(req.query));
  sendSuccess(res, result.items.map(library.templateDto), { pagination: { next_cursor: result.nextCursor } });
}));
router.post('/templates/from-estimate', validate(saveTemplateSchema), handler(async (req, res) => {
  sendSuccess(res, library.templateDto(await library.saveTemplate(req.companyId!, req.userId!, req.body)), { statusCode: 201 });
}));
router.post('/templates/:id/instantiate', validate(instantiateTemplateSchema), handler(async (req, res) => {
  sendSuccess(res, toEstimateDto(await library.instantiateTemplate(req.companyId!, req.userId!, param(req.params.id), req.body)), { statusCode: 201 });
}));
router.delete('/templates/:id', handler(async (req, res) => {
  await library.removeTemplate(req.companyId!, param(req.params.id)); sendSuccess(res, {});
}));
router.post('/estimates/:id/duplicate', validate(duplicateEstimateSchema), handler(async (req, res) => {
  sendSuccess(res, toEstimateDto(await library.duplicateEstimate(req.companyId!, req.userId!, param(req.params.id), req.body)), { statusCode: 201 });
}));
router.get('/items', validate(librarySearchSchema, 'query'), handler(async (req, res) => {
  const result = await library.listItems(req.companyId!, librarySearchSchema.parse(req.query));
  sendSuccess(res, result.items.map(library.savedItemDto), { pagination: { next_cursor: result.nextCursor } });
}));
router.post('/items', validate(saveItemSchema), handler(async (req, res) => {
  sendSuccess(res, library.savedItemDto(await library.saveItem(req.companyId!, req.body)), { statusCode: 201 });
}));
router.patch('/items/:id', validate(saveItemSchema), handler(async (req, res) => {
  sendSuccess(res, library.savedItemDto(await library.saveItem(req.companyId!, req.body, param(req.params.id))));
}));
router.post('/items/:id/apply', validate(applyItemSchema), handler(async (req, res) => {
  sendSuccess(res, toEstimateLineItemDto(await library.applyItem(req.companyId!, param(req.params.id), req.body)), { statusCode: 201 });
}));
router.delete('/items/:id', handler(async (req, res) => {
  await library.removeItem(req.companyId!, param(req.params.id)); sendSuccess(res, {});
}));
export default router;
