import { Router, Request, Response, NextFunction } from 'express';
import {
  getProducts,
  getEntitlement,
  createPurchaseAttempt,
  syncTransaction,
  restorePurchases,
} from './commerce.controller';
import { validate } from '../../middleware/validate.middleware';
import {
  createPurchaseAttemptSchema,
  syncTransactionSchema,
  restorePurchasesSchema,
} from './commerce.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /commerce/products - list all available subscription products
router.get('/products', asyncHandler(getProducts));

// GET /commerce/entitlement - get current user entitlement snapshot
router.get('/entitlement', asyncHandler(getEntitlement));

// POST /commerce/purchase-attempt - create a purchase attempt before StoreKit purchase
router.post(
  '/purchase-attempt',
  validate(createPurchaseAttemptSchema),
  asyncHandler(createPurchaseAttempt),
);

// POST /commerce/transactions/sync - sync a completed StoreKit transaction
router.post(
  '/transactions/sync',
  validate(syncTransactionSchema),
  asyncHandler(syncTransaction),
);

// POST /commerce/restore - restore purchases from StoreKit transaction history
router.post(
  '/restore',
  validate(restorePurchasesSchema),
  asyncHandler(restorePurchases),
);

export default router;
