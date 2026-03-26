import { Router } from 'express';

// Activity has no top-level routes. All activity access is through
// the nested route at /projects/:projectId/activity.
// This empty router is exported to satisfy the app.ts import.
const router = Router();

export default router;
