import { Router } from 'express';
import { handleAppStoreNotification } from './commerce-webhook.controller';

const router = Router();

// POST /v1/commerce/webhooks/app-store
// No auth — Apple sends directly. Verification is via JWS signature.
router.post('/app-store', handleAppStoreNotification);

export default router;
