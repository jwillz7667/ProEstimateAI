import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import * as commerceService from './commerce.service';

export async function getProducts(req: Request, res: Response) {
  const products = await commerceService.getProducts();
  sendSuccess(res, products);
}

export async function getEntitlement(req: Request, res: Response) {
  const snapshot = await commerceService.getEffectiveEntitlement(
    req.userId!,
    req.companyId!,
  );
  sendSuccess(res, snapshot);
}

export async function createPurchaseAttempt(req: Request, res: Response) {
  const result = await commerceService.createPurchaseAttempt(
    req.userId!,
    req.companyId!,
    req.body.product_id,
    req.body.placement,
  );
  sendSuccess(res, result, { statusCode: 201 });
}

export async function syncTransaction(req: Request, res: Response) {
  const snapshot = await commerceService.syncTransaction(
    req.userId!,
    req.companyId!,
    req.body,
  );
  sendSuccess(res, snapshot);
}

export async function restorePurchases(req: Request, res: Response) {
  const snapshot = await commerceService.restorePurchases(
    req.userId!,
    req.companyId!,
    req.body.transactions,
  );
  sendSuccess(res, snapshot);
}
