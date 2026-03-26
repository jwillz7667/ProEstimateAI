import { z } from 'zod';

// ─── Create Purchase Attempt ───────────────────────────

export const createPurchaseAttemptSchema = z.object({
  product_id: z.string().min(1, 'Product ID is required'),
  placement: z.string().optional(),
});

export type CreatePurchaseAttemptInput = z.infer<typeof createPurchaseAttemptSchema>;

// ─── Sync Transaction ──────────────────────────────────

export const syncTransactionSchema = z.object({
  purchase_attempt_id: z.string().min(1, 'Purchase attempt ID is required'),
  store_product_id: z.string().min(1, 'Store product ID is required'),
  transaction_id: z.string().min(1, 'Transaction ID is required'),
  original_transaction_id: z.string().min(1, 'Original transaction ID is required'),
  app_account_token: z.string().uuid('App account token must be a valid UUID'),
  environment: z.string().min(1, 'Environment is required'),
});

export type SyncTransactionInput = z.infer<typeof syncTransactionSchema>;

// ─── Restore Purchases ─────────────────────────────────

const restoreTransactionSchema = z.object({
  store_product_id: z.string().min(1),
  transaction_id: z.string().min(1),
  original_transaction_id: z.string().min(1),
  app_account_token: z.string().uuid(),
  environment: z.string().min(1),
});

export const restorePurchasesSchema = z.object({
  transactions: z
    .array(restoreTransactionSchema)
    .min(1, 'At least one transaction is required'),
});

export type RestorePurchasesInput = z.infer<typeof restorePurchasesSchema>;
export type RestoreTransactionInput = z.infer<typeof restoreTransactionSchema>;
