import { Request, Response } from "express";
import { logger } from "../../config/logger";
import { AppleJWSVerificationError, verifyAndDecodeNotification } from "../../lib/apple-storekit";
import { appStoreNotificationSchema } from "./commerce-webhook.validators";

export async function handleAppStoreNotification(
  req: Request,
  res: Response,
): Promise<void> {
  try {
    // 1. Validate the request body shape
    const parseResult = appStoreNotificationSchema.safeParse(req.body);

    if (!parseResult.success) {
      logger.warn(
        { errors: parseResult.error.flatten().fieldErrors },
        "App Store webhook received invalid payload",
      );
      // Return 200 so Apple does not retry for malformed requests
      res.status(200).json({ ok: true });
      return;
    }

    const { signedPayload } = parseResult.data;

    // 2. Verify and decode the JWS notification (full chain validation
    // against Apple Root CA G3; throws on any signature, anchor, or
    // bundle-ID mismatch).
    const decoded = await verifyAndDecodeNotification(signedPayload);

    logger.info(
      {
        notificationType: decoded.payload.notificationType,
        subtype: decoded.payload.subtype,
        notificationUUID: decoded.payload.notificationUUID,
        transactionId: decoded.transactionInfo.transactionId,
        originalTransactionId: decoded.transactionInfo.originalTransactionId,
        productId: decoded.transactionInfo.productId,
        environment: decoded.payload.data.environment,
      },
      "App Store webhook decoded successfully",
    );

    // 3. Delegate to commerce service for entitlement state updates
    const { handleAppStoreWebhook } = await import("./commerce.service");
    await handleAppStoreWebhook(decoded);

    // 4. Acknowledge the notification — Apple expects 200 for success
    res.status(200).json({ ok: true });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";

    logger.error(
      { err: error, message },
      "App Store webhook processing failed",
    );

    // A verified delivery is acknowledged only after its transaction commits.
    // Let Apple retry transient database/network failures instead of losing it.
    if (error instanceof AppleJWSVerificationError) {
      res.status(200).json({ ok: true });
    } else {
      res.status(503).json({ ok: false });
    }
  }
}
