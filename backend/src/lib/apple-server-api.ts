import { SignJWT, importPKCS8 } from "jose";
import { env } from "../config/env";
import { logger } from "../config/logger";
import { EXPECTED_BUNDLE_ID, verifyAppleJWS, AppleTransactionInfo } from "./apple-storekit";

// ─── Constants ──────────────────────────────────────────

/**
 * App Store Server API hosts. The two environments are isolated —
 * a transaction signed in Sandbox cannot be queried against Production
 * and vice versa, so we may need to retry on the other host before
 * declaring a transaction missing.
 */
const APP_STORE_API_HOSTS = {
  Production: "https://api.storekit.itunes.apple.com",
  Sandbox: "https://api.storekit-sandbox.itunes.apple.com",
} as const;

/** Apple requires JWTs ≤ 1 hour. We mint short-lived ones — 5 minutes
 * is plenty for the synchronous request/response window and tightens
 * the blast radius if a token leaks. */
const JWT_TTL_SECONDS = 5 * 60;

/** Apple's audience claim for App Store Server API JWTs. Fixed string. */
const JWT_AUDIENCE = "appstoreconnect-v1";

// ─── Errors ─────────────────────────────────────────────

export class AppStoreServerApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode?: number,
    public readonly body?: unknown,
  ) {
    super(message);
    this.name = "AppStoreServerApiError";
  }
}

/**
 * Thrown when Apple confirms (via 404 on both hosts) that the
 * transaction we just JWS-verified does not exist in their server-side
 * history. Distinct from generic API errors so callers can decide
 * whether to fail closed (reject the claim) or fail open (treat the
 * check as advisory and continue).
 */
export class AppStoreTransactionNotFoundError extends Error {
  constructor(public readonly originalTransactionId: string) {
    super(
      `Transaction ${originalTransactionId} not found in Apple's server-side history`,
    );
    this.name = "AppStoreTransactionNotFoundError";
  }
}

// ─── JWT minting ────────────────────────────────────────

/**
 * Build a short-lived ES256 JWT that authenticates this backend to the
 * App Store Server API. Apple verifies the signature against the public
 * key paired with our App Store Connect API key (identified by `kid`).
 *
 * The PEM is loaded from env on every call. That's intentional — keys
 * are small, the signing operation dwarfs the parse cost, and rotating
 * the env var doesn't require a process restart.
 */
async function mintBearerToken(): Promise<string> {
  const issuerId = env.APP_STORE_ISSUER_ID;
  const keyId = env.APP_STORE_API_KEY_ID;
  const privateKeyPem = env.APP_STORE_API_PRIVATE_KEY;

  if (!issuerId || !keyId || !privateKeyPem) {
    throw new AppStoreServerApiError(
      "App Store Server API credentials missing — refusing to mint token",
    );
  }

  // Apple's API keys are downloaded as PKCS#8 PEMs. Newlines may have
  // been escaped (`\n`) by whatever process injected the env var; restore
  // them so jose can parse the document.
  const normalizedPem = privateKeyPem.includes("\\n")
    ? privateKeyPem.replace(/\\n/g, "\n")
    : privateKeyPem;

  const privateKey = await importPKCS8(normalizedPem, "ES256");

  const now = Math.floor(Date.now() / 1000);
  return new SignJWT({ bid: EXPECTED_BUNDLE_ID })
    .setProtectedHeader({ alg: "ES256", kid: keyId, typ: "JWT" })
    .setIssuer(issuerId)
    .setIssuedAt(now)
    .setExpirationTime(now + JWT_TTL_SECONDS)
    .setAudience(JWT_AUDIENCE)
    .sign(privateKey);
}

// ─── Public API ─────────────────────────────────────────

/**
 * True when the env is fully configured for App Store Server API calls.
 * Callers use this to gate the optional truth-check without throwing.
 */
export function isAppStoreServerApiConfigured(): boolean {
  return Boolean(
    env.APP_STORE_ISSUER_ID &&
      env.APP_STORE_API_KEY_ID &&
      env.APP_STORE_API_PRIVATE_KEY,
  );
}

interface TransactionHistoryResponse {
  revision: string | null;
  bundleId: string;
  appAppleId?: number;
  environment: "Production" | "Sandbox";
  hasMore: boolean;
  signedTransactions: string[];
}

/**
 * Fetch the transaction history for an `originalTransactionId` from
 * Apple's App Store Server API.
 *
 * Tries the configured environment first and falls back to the other
 * host on 404 — this matters when a Sandbox build calls a Production
 * server (or vice versa) during local testing or when a TestFlight
 * environment differs from the deployed default.
 */
export async function fetchTransactionHistory(
  originalTransactionId: string,
): Promise<TransactionHistoryResponse> {
  const token = await mintBearerToken();
  const tryOrder: Array<"Production" | "Sandbox"> =
    env.APP_STORE_ENVIRONMENT === "Production"
      ? ["Production", "Sandbox"]
      : ["Sandbox", "Production"];

  let lastError: AppStoreServerApiError | null = null;
  for (const envName of tryOrder) {
    const host = APP_STORE_API_HOSTS[envName];
    const url = `${host}/inApps/v1/history/${encodeURIComponent(originalTransactionId)}`;
    let response: Response;
    try {
      response = await fetch(url, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
        },
      });
    } catch (err) {
      // Network-level failure — don't try the other host, just bail.
      // The caller treats this as "couldn't reach Apple" and decides
      // whether to fail open or fail closed.
      throw new AppStoreServerApiError(
        `Network error calling App Store Server API: ${(err as Error).message}`,
      );
    }

    if (response.status === 404) {
      // Try the alternate environment before declaring NotFound — see
      // top-of-function rationale.
      lastError = new AppStoreServerApiError(
        `Transaction ${originalTransactionId} not in ${envName} history`,
        404,
      );
      continue;
    }

    if (!response.ok) {
      let body: unknown;
      try {
        body = await response.json();
      } catch {
        body = await response.text().catch(() => undefined);
      }
      throw new AppStoreServerApiError(
        `App Store Server API ${response.status}`,
        response.status,
        body,
      );
    }

    const json = (await response.json()) as TransactionHistoryResponse;
    return json;
  }

  throw new AppStoreTransactionNotFoundError(originalTransactionId);
}

/**
 * Verify each `signedTransactions` JWS in a history response and return
 * the decoded payloads. Apple's history endpoint returns signed JWTs —
 * we don't trust the wrapper alone, we re-verify each entry against
 * Root CA G3 the same way we verify iOS-supplied transactions.
 */
async function decodeHistoryEntries(
  history: TransactionHistoryResponse,
): Promise<AppleTransactionInfo[]> {
  const decoded: AppleTransactionInfo[] = [];
  for (const jws of history.signedTransactions) {
    const payload = await verifyAppleJWS<AppleTransactionInfo>(
      jws,
      "appStoreServerApi.history",
    );
    if (payload.bundleId !== EXPECTED_BUNDLE_ID) {
      throw new AppStoreServerApiError(
        `History entry bundleId mismatch: expected ${EXPECTED_BUNDLE_ID}, got ${payload.bundleId}`,
      );
    }
    decoded.push(payload);
  }
  return decoded;
}

/**
 * Defense-in-depth: assert that the iOS-supplied transactionId actually
 * appears in Apple's server-side history for the given
 * `originalTransactionId`. Catches attacks where an attacker forges a
 * JWS that verifies cleanly against the static x5c chain (e.g. by
 * replaying a leaked-but-valid signed transaction) — Apple's server
 * history is the only thing that knows about revoked, refunded, or
 * never-existed transactions in real time.
 *
 * Throws `AppStoreTransactionNotFoundError` when the transaction is
 * absent from history; throws `AppStoreServerApiError` for any other
 * failure (network, auth, malformed response). Callers decide whether
 * those are fatal.
 */
export async function assertTransactionInHistory(args: {
  originalTransactionId: string;
  transactionId: string;
}): Promise<void> {
  const history = await fetchTransactionHistory(args.originalTransactionId);
  const entries = await decodeHistoryEntries(history);

  const match = entries.some(
    (entry) => entry.transactionId === args.transactionId,
  );
  if (!match) {
    logger.warn(
      {
        originalTransactionId: args.originalTransactionId,
        transactionId: args.transactionId,
        entriesCount: entries.length,
      },
      "App Store Server API: transactionId not present in Apple history",
    );
    throw new AppStoreTransactionNotFoundError(args.originalTransactionId);
  }

  logger.debug(
    {
      originalTransactionId: args.originalTransactionId,
      transactionId: args.transactionId,
    },
    "App Store Server API: transaction confirmed against Apple history",
  );
}
