import { z } from "zod";

// ─── Create Purchase Attempt ───────────────────────────

export const createPurchaseAttemptSchema = z.object({
  product_id: z.string().min(1, "Product ID is required"),
  placement: z.string().optional(),
});

export type CreatePurchaseAttemptInput = z.infer<
  typeof createPurchaseAttemptSchema
>;

// ─── Sync Transaction ──────────────────────────────────

/**
 * Verified StoreKit transactions arrive with a `jwsRepresentation`
 * string — a JWS whose signature chains up to Apple Root CA G3 and
 * whose payload duplicates `transactionId`, `productId`, `bundleId`,
 * `appAccountToken` and friends. The backend authenticates the
 * subscription against the JWS, not the loose iOS-supplied scalars,
 * so a missing or malformed JWS here is a hard failure.
 */
export const syncTransactionSchema = z.object({
  purchase_attempt_id: z.string().min(1, "Purchase attempt ID is required"),
  store_product_id: z.string().min(1, "Store product ID is required"),
  transaction_id: z.string().min(1, "Transaction ID is required"),
  original_transaction_id: z
    .string()
    .min(1, "Original transaction ID is required"),
  app_account_token: z.string().uuid("App account token must be a valid UUID"),
  environment: z.string().min(1, "Environment is required"),
  signed_transaction: z.string().min(1, "Signed transaction JWS is required"),
});

export type SyncTransactionInput = z.infer<typeof syncTransactionSchema>;

// ─── Restore Purchases ─────────────────────────────────

/**
 * Restore items mirror sync items but the `app_account_token` is
 * optional — Family-Sharing or out-of-band transactions that were
 * never created by our PurchaseAttempt flow legitimately arrive
 * without it. The signed JWS is still required so we can authenticate
 * each restored entitlement.
 */
const restoreTransactionSchema = z.object({
  store_product_id: z.string().min(1),
  transaction_id: z.string().min(1),
  original_transaction_id: z.string().min(1),
  app_account_token: z.string().uuid().nullable().optional(),
  environment: z.string().min(1),
  signed_transaction: z.string().min(1, "Signed transaction JWS is required"),
});

export const restorePurchasesSchema = z.object({
  transactions: z
    .array(restoreTransactionSchema)
    .min(1, "At least one transaction is required"),
});

export type RestorePurchasesInput = z.infer<typeof restorePurchasesSchema>;
export type RestoreTransactionInput = z.infer<typeof restoreTransactionSchema>;
