import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.middleware';
import { shareRateLimit } from '../../middleware/rate-limit.middleware';
import { sendSuccess } from '../../lib/envelope';
import * as checkout from './invoice-checkout.service';

const wrap = (fn: (req: Request, res: Response) => Promise<void>) =>
  (req: Request, res: Response, next: NextFunction) => { fn(req, res).catch(next); };
const empty = z.object({}).strict();

export const stripePaymentWebhookHandler = wrap(async (req, res) => {
  await checkout.receiveStripeWebhook(req.body as Buffer, req.get('stripe-signature') ?? '');
  res.status(200).json({ received: true });
});

export const merchantPaymentRoutes = Router();
merchantPaymentRoutes.get('/', wrap(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  sendSuccess(res, await checkout.merchantStatus(req.companyId!, req.userId!));
}));
merchantPaymentRoutes.post('/onboarding', validate(z.object({ country: z.string().regex(/^[A-Za-z]{2}$/) }).strict()), wrap(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  sendSuccess(res, await checkout.startMerchantOnboarding(req.companyId!, req.userId!, req.body.country));
}));

export const invoiceCheckoutPrivateRoutes = Router({ mergeParams: true });
invoiceCheckoutPrivateRoutes.post('/cancel', validate(empty), wrap(async (req, res) => {
  await checkout.cancelCheckout(req.params.invoiceId as string, req.companyId!, req.userId!);
  sendSuccess(res, {});
}));
invoiceCheckoutPrivateRoutes.post('/refund-review', validate(z.object({
  expected_amount_paid: z.number().finite().min(0).max(9999999999.99), expected_amount_due: z.number().finite().min(0).max(9999999999.99),
}).strict()), wrap(async (req, res) => {
  await checkout.acknowledgeRefundReview(req.params.invoiceId as string, req.companyId!, req.userId!, req.body.expected_amount_paid, req.body.expected_amount_due);
  sendSuccess(res, {});
}));

export const invoiceCheckoutPublicRoutes = Router();
invoiceCheckoutPublicRoutes.use(shareRateLimit);
invoiceCheckoutPublicRoutes.post('/:token/checkout', validate(z.object({ payment_scope: z.enum(['next_installment', 'balance']).default('next_installment') }).strict()), wrap(async (req, res) => {
  res.set('Cache-Control', 'no-store'); res.set('Referrer-Policy', 'no-referrer');
  sendSuccess(res, await checkout.createCheckout(req.params.token as string, req.body.payment_scope));
}));
