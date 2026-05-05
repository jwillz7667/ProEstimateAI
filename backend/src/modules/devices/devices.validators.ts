import { z } from "zod";

/**
 * APNs tokens are 64 hex chars (32 bytes). We accept any reasonable
 * hex string up to 200 chars to leave headroom if Apple ever extends
 * the format — a hard short upper bound is enough to filter out
 * obvious garbage without locking us to today's exact length.
 */
export const registerApnsTokenSchema = z.object({
  token: z
    .string()
    .min(32)
    .max(200)
    .regex(/^[0-9a-fA-F]+$/, "token must be hex-encoded"),
  bundle_id: z.string().min(1).max(200),
});

export type RegisterApnsTokenInput = z.infer<typeof registerApnsTokenSchema>;

export const deregisterApnsTokenSchema = z.object({
  token: z.string().min(32).max(200),
});

export type DeregisterApnsTokenInput = z.infer<typeof deregisterApnsTokenSchema>;
