import { X509Certificate } from "node:crypto";
import { decodeProtectedHeader, importX509, jwtVerify } from "jose";
import { logger } from "../config/logger";
import { APPLE_ROOT_CA_G3 } from "./apple-root-cert";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const EXPECTED_BUNDLE_ID = "Res.ProEstimate-AI";

/** JWS signing algorithms Apple uses for App Store JWS payloads. */
const ALLOWED_JWS_ALGS = new Set(["ES256", "ES384", "PS256", "RS256"]);

// ---------------------------------------------------------------------------
// Types — Apple App Store Server Notifications V2
// ---------------------------------------------------------------------------

export interface AppleNotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data: {
    signedTransactionInfo: string;
    signedRenewalInfo?: string;
    bundleId: string;
    environment: string;
  };
  version: string;
  signedDate: number;
}

export interface AppleTransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  purchaseDate: number;
  expiresDate?: number;
  type: string;
  appAccountToken?: string;
  environment: string;
}

export interface AppleRenewalInfo {
  originalTransactionId: string;
  productId: string;
  autoRenewStatus: number;
  renewalDate?: number;
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

export interface DecodedAppleNotification {
  payload: AppleNotificationPayload;
  transactionInfo: AppleTransactionInfo;
  renewalInfo: AppleRenewalInfo | null;
}

// ---------------------------------------------------------------------------
// Notification type constants for convenience
// ---------------------------------------------------------------------------

export const AppleNotificationType = {
  SUBSCRIBED: "SUBSCRIBED",
  DID_RENEW: "DID_RENEW",
  DID_CHANGE_RENEWAL_PREF: "DID_CHANGE_RENEWAL_PREF",
  DID_CHANGE_RENEWAL_STATUS: "DID_CHANGE_RENEWAL_STATUS",
  DID_FAIL_TO_RENEW: "DID_FAIL_TO_RENEW",
  EXPIRED: "EXPIRED",
  GRACE_PERIOD_EXPIRED: "GRACE_PERIOD_EXPIRED",
  OFFER_REDEEMED: "OFFER_REDEEMED",
  REFUND: "REFUND",
  REFUND_DECLINED: "REFUND_DECLINED",
  REFUND_REVERSED: "REFUND_REVERSED",
  RENEWAL_EXTENDED: "RENEWAL_EXTENDED",
  REVOKE: "REVOKE",
  TEST: "TEST",
  CONSUMPTION_REQUEST: "CONSUMPTION_REQUEST",
  RENEWAL_EXTENSION: "RENEWAL_EXTENSION",
  PRICE_INCREASE: "PRICE_INCREASE",
} as const;

export const AppleNotificationSubtype = {
  INITIAL_BUY: "INITIAL_BUY",
  RESUBSCRIBE: "RESUBSCRIBE",
  DOWNGRADE: "DOWNGRADE",
  UPGRADE: "UPGRADE",
  AUTO_RENEW_ENABLED: "AUTO_RENEW_ENABLED",
  AUTO_RENEW_DISABLED: "AUTO_RENEW_DISABLED",
  VOLUNTARY: "VOLUNTARY",
  BILLING_RETRY_PERIOD: "BILLING_RETRY_PERIOD",
  PRICE_INCREASE: "PRICE_INCREASE",
  GRACE_PERIOD: "GRACE_PERIOD",
  PENDING: "PENDING",
  ACCEPTED: "ACCEPTED",
  BILLING_RECOVERY: "BILLING_RECOVERY",
  PRODUCT_NOT_FOR_SALE: "PRODUCT_NOT_FOR_SALE",
  SUMMARY: "SUMMARY",
  FAILURE: "FAILURE",
} as const;

// ---------------------------------------------------------------------------
// JWS verification
// ---------------------------------------------------------------------------

export class AppleJWSVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AppleJWSVerificationError";
  }
}

/**
 * Verify an Apple-signed JWS and return its decoded payload.
 *
 * The JWS protected header carries an `x5c` certificate chain whose
 * leaf signs the payload, intermediates link toward Apple's
 * publicly-pinned Root CA G3. This routine:
 *
 *   1. Parses every x5c entry as an X.509 certificate.
 *   2. Walks the chain from leaf to root, asserting that each cert is
 *      signed by the next and that none are outside their validity
 *      window.
 *   3. Anchors the last cert to Apple Root CA G3 (either by SHA-256
 *      fingerprint match if the chain includes the root, or by
 *      verifying the last cert's signature against the embedded root).
 *   4. Verifies the JWS signature itself using the leaf cert's public
 *      key, restricting `alg` to the algorithms Apple actually uses.
 *
 * Anything else throws `AppleJWSVerificationError`. The payload is
 * never returned unverified.
 */
export async function verifyAppleJWS<T>(
  jws: string,
  label: string,
): Promise<T> {
  const header = decodeProtectedHeader(jws);

  if (typeof header.alg !== "string" || !ALLOWED_JWS_ALGS.has(header.alg)) {
    throw new AppleJWSVerificationError(
      `Unsupported JWS algorithm: ${header.alg ?? "missing"}`,
    );
  }

  if (!Array.isArray(header.x5c) || header.x5c.length === 0) {
    throw new AppleJWSVerificationError(
      "JWS protected header missing x5c certificate chain",
    );
  }

  const chain: X509Certificate[] = header.x5c.map((b64, idx) => {
    try {
      return new X509Certificate(Buffer.from(b64, "base64"));
    } catch (err) {
      throw new AppleJWSVerificationError(
        `Failed to parse x5c[${idx}] as X.509: ${(err as Error).message}`,
      );
    }
  });

  const now = new Date();
  for (let i = 0; i < chain.length; i++) {
    const cert = chain[i];
    if (now < new Date(cert.validFrom) || now > new Date(cert.validTo)) {
      throw new AppleJWSVerificationError(
        `x5c[${i}] certificate is outside its validity window`,
      );
    }
  }

  // Each cert must be signed by the next one in the chain.
  for (let i = 0; i < chain.length - 1; i++) {
    if (!chain[i].verify(chain[i + 1].publicKey)) {
      throw new AppleJWSVerificationError(
        `x5c chain link ${i} → ${i + 1} signature verification failed`,
      );
    }
  }

  // Anchor: the last cert must be Apple Root CA G3, or be signed by it.
  const last = chain[chain.length - 1];
  const anchoredAtRoot =
    last.fingerprint256 === APPLE_ROOT_CA_G3.fingerprint256;
  const signedByRoot =
    !anchoredAtRoot && last.verify(APPLE_ROOT_CA_G3.publicKey);
  if (!anchoredAtRoot && !signedByRoot) {
    throw new AppleJWSVerificationError(
      "x5c chain does not terminate at Apple Root CA G3",
    );
  }

  // Verify the JWS signature using the leaf cert's public key.
  const leafKey = await importX509(chain[0].toString(), header.alg);
  const { payload } = await jwtVerify(jws, leafKey, {
    algorithms: Array.from(ALLOWED_JWS_ALGS),
  });

  logger.debug({ alg: header.alg, label }, "Apple JWS verified");
  return payload as T;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Verify and decode an Apple App Store Server Notification V2 signed
 * payload. Every JWS in the notification (the outer envelope, the
 * `signedTransactionInfo`, and the optional `signedRenewalInfo`) is
 * fully verified against Apple Root CA G3 — no decode-without-verify
 * paths remain. Bundle IDs are cross-checked against this app's
 * expected identifier on both the outer envelope and the inner
 * transaction.
 *
 * @throws {AppleJWSVerificationError} if signature or bundleId checks fail.
 */
export async function verifyAndDecodeNotification(
  signedPayload: string,
): Promise<DecodedAppleNotification> {
  const payload = await verifyAppleJWS<AppleNotificationPayload>(
    signedPayload,
    "notificationPayload",
  );

  logger.info(
    {
      type: payload.notificationType,
      subtype: payload.subtype,
      uuid: payload.notificationUUID,
      environment: payload.data?.environment,
    },
    "Received Apple App Store notification",
  );

  if (!payload.data) {
    throw new AppleJWSVerificationError(
      "Apple notification missing data field",
    );
  }

  if (payload.data.bundleId !== EXPECTED_BUNDLE_ID) {
    throw new AppleJWSVerificationError(
      `Bundle ID mismatch: expected ${EXPECTED_BUNDLE_ID}, got ${payload.data.bundleId}`,
    );
  }

  if (!payload.data.signedTransactionInfo) {
    throw new AppleJWSVerificationError(
      "Apple notification missing signedTransactionInfo",
    );
  }

  const transactionInfo = await verifyAppleJWS<AppleTransactionInfo>(
    payload.data.signedTransactionInfo,
    "signedTransactionInfo",
  );

  if (transactionInfo.bundleId !== EXPECTED_BUNDLE_ID) {
    throw new AppleJWSVerificationError(
      `Transaction bundle ID mismatch: expected ${EXPECTED_BUNDLE_ID}, got ${transactionInfo.bundleId}`,
    );
  }

  let renewalInfo: AppleRenewalInfo | null = null;
  if (payload.data.signedRenewalInfo) {
    renewalInfo = await verifyAppleJWS<AppleRenewalInfo>(
      payload.data.signedRenewalInfo,
      "signedRenewalInfo",
    );
  }

  return {
    payload,
    transactionInfo,
    renewalInfo,
  };
}
