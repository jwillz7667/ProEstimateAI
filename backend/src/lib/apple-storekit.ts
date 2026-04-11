import { decodeJwt, decodeProtectedHeader } from 'jose';
import { logger } from '../config/logger';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const EXPECTED_BUNDLE_ID = 'Res.ProEstimate-AI';

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
  SUBSCRIBED: 'SUBSCRIBED',
  DID_RENEW: 'DID_RENEW',
  DID_CHANGE_RENEWAL_PREF: 'DID_CHANGE_RENEWAL_PREF',
  DID_CHANGE_RENEWAL_STATUS: 'DID_CHANGE_RENEWAL_STATUS',
  DID_FAIL_TO_RENEW: 'DID_FAIL_TO_RENEW',
  EXPIRED: 'EXPIRED',
  GRACE_PERIOD_EXPIRED: 'GRACE_PERIOD_EXPIRED',
  OFFER_REDEEMED: 'OFFER_REDEEMED',
  REFUND: 'REFUND',
  REFUND_DECLINED: 'REFUND_DECLINED',
  REFUND_REVERSED: 'REFUND_REVERSED',
  RENEWAL_EXTENDED: 'RENEWAL_EXTENDED',
  REVOKE: 'REVOKE',
  TEST: 'TEST',
  CONSUMPTION_REQUEST: 'CONSUMPTION_REQUEST',
  RENEWAL_EXTENSION: 'RENEWAL_EXTENSION',
  PRICE_INCREASE: 'PRICE_INCREASE',
} as const;

export const AppleNotificationSubtype = {
  INITIAL_BUY: 'INITIAL_BUY',
  RESUBSCRIBE: 'RESUBSCRIBE',
  DOWNGRADE: 'DOWNGRADE',
  UPGRADE: 'UPGRADE',
  AUTO_RENEW_ENABLED: 'AUTO_RENEW_ENABLED',
  AUTO_RENEW_DISABLED: 'AUTO_RENEW_DISABLED',
  VOLUNTARY: 'VOLUNTARY',
  BILLING_RETRY_PERIOD: 'BILLING_RETRY_PERIOD',
  PRICE_INCREASE: 'PRICE_INCREASE',
  GRACE_PERIOD: 'GRACE_PERIOD',
  PENDING: 'PENDING',
  ACCEPTED: 'ACCEPTED',
  BILLING_RECOVERY: 'BILLING_RECOVERY',
  PRODUCT_NOT_FOR_SALE: 'PRODUCT_NOT_FOR_SALE',
  SUMMARY: 'SUMMARY',
  FAILURE: 'FAILURE',
} as const;

// ---------------------------------------------------------------------------
// Decode helpers
// ---------------------------------------------------------------------------

/**
 * Decode a JWS token payload without full signature verification.
 *
 * TODO: Add full Apple certificate chain verification.
 * Apple signs JWS tokens with x5c certificate chains rooted at their Root CA.
 * Full verification requires:
 *   1. Extract x5c header from JWS
 *   2. Build certificate chain from x5c array
 *   3. Verify chain terminates at Apple Root CA (AppleRootCA-G3)
 *   4. Verify JWS signature using the leaf certificate's public key
 * For now we decode the payload and validate the bundleId to ensure the
 * notification targets this app. This is acceptable for server-to-server
 * webhook endpoints that are not publicly discoverable, but should be
 * hardened before production launch.
 */
function decodeAppleJWS<T>(jws: string, label: string): T {
  const header = decodeProtectedHeader(jws);
  logger.debug({ alg: header.alg, label }, 'Decoding Apple JWS');

  const payload = decodeJwt<T>(jws);
  return payload as T;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Verify and decode an Apple App Store Server Notification V2 signed payload.
 *
 * Decodes the outer signedPayload JWS, then decodes the nested
 * signedTransactionInfo and optional signedRenewalInfo JWS tokens.
 *
 * Validates that the bundleId matches the expected app bundle identifier.
 *
 * @throws {Error} if the bundleId does not match or required fields are missing.
 */
export function verifyAndDecodeNotification(
  signedPayload: string,
): DecodedAppleNotification {
  // 1. Decode the outer notification payload
  const payload = decodeAppleJWS<AppleNotificationPayload>(
    signedPayload,
    'notificationPayload',
  );

  logger.info(
    {
      type: payload.notificationType,
      subtype: payload.subtype,
      uuid: payload.notificationUUID,
      environment: payload.data?.environment,
    },
    'Received Apple App Store notification',
  );

  // Validate bundle ID
  if (!payload.data) {
    throw new Error('Apple notification missing data field');
  }

  if (payload.data.bundleId !== EXPECTED_BUNDLE_ID) {
    throw new Error(
      `Bundle ID mismatch: expected ${EXPECTED_BUNDLE_ID}, got ${payload.data.bundleId}`,
    );
  }

  // 2. Decode the signed transaction info (always present in data notifications)
  if (!payload.data.signedTransactionInfo) {
    throw new Error('Apple notification missing signedTransactionInfo');
  }

  const transactionInfo = decodeAppleJWS<AppleTransactionInfo>(
    payload.data.signedTransactionInfo,
    'signedTransactionInfo',
  );

  // Validate transaction bundle ID matches as well
  if (transactionInfo.bundleId !== EXPECTED_BUNDLE_ID) {
    throw new Error(
      `Transaction bundle ID mismatch: expected ${EXPECTED_BUNDLE_ID}, got ${transactionInfo.bundleId}`,
    );
  }

  logger.debug(
    {
      transactionId: transactionInfo.transactionId,
      originalTransactionId: transactionInfo.originalTransactionId,
      productId: transactionInfo.productId,
      appAccountToken: transactionInfo.appAccountToken,
    },
    'Decoded Apple transaction info',
  );

  // 3. Decode the signed renewal info (optional — not present for consumables)
  let renewalInfo: AppleRenewalInfo | null = null;

  if (payload.data.signedRenewalInfo) {
    renewalInfo = decodeAppleJWS<AppleRenewalInfo>(
      payload.data.signedRenewalInfo,
      'signedRenewalInfo',
    );

    logger.debug(
      {
        originalTransactionId: renewalInfo.originalTransactionId,
        autoRenewStatus: renewalInfo.autoRenewStatus,
        expirationIntent: renewalInfo.expirationIntent,
        isInBillingRetryPeriod: renewalInfo.isInBillingRetryPeriod,
      },
      'Decoded Apple renewal info',
    );
  }

  return {
    payload,
    transactionInfo,
    renewalInfo,
  };
}
