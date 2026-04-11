import { z } from 'zod';

// ─── App Store Server Notifications V2 ───────────────────

export const appStoreNotificationSchema = z.object({
  signedPayload: z.string().min(1, 'Signed payload is required'),
});

export type AppStoreNotificationInput = z.infer<typeof appStoreNotificationSchema>;
