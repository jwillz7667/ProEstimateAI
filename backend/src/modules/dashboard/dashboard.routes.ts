import { Router } from 'express';
import { getSummaryHandler } from './dashboard.controller';

const router = Router();

// GET /v1/dashboard/summary
router.get('/summary', getSummaryHandler);

export default router;
