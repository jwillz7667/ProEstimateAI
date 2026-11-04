import { Router } from 'express';
import { getAttentionHandler, getSummaryHandler } from './dashboard.controller';

const router = Router();

// GET /v1/dashboard/summary
router.get('/summary', getSummaryHandler);
router.get('/attention', getAttentionHandler);

export default router;
