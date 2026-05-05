import http2 from "http2";
import jwt from "jsonwebtoken";
import { prisma } from "../config/database";
import { logger } from "../config/logger";

/**
 * Apple Push Notification service (APNs) HTTP/2 client.
 *
 * Why a hand-rolled client and not `node-apn`? Apple's APNs API is
 * stable HTTP/2 + JWT — node-apn is a thick wrapper around it that
 * hasn't been actively maintained in years and pulls in a tree of
 * deps we don't otherwise use. The native `http2` module + the
 * `jsonwebtoken` we already have for our own auth flow is ~150 lines
 * end to end and gives us direct control of error handling.
 *
 * Lifecycle:
 *
 *   - **Configuration** is read once from env on first call. Missing
 *     vars → push silently no-ops (warns once) so a deploy without
 *     APNs configured does NOT block generation completions; the
 *     in-app UI still updates fine, the user just doesn't get a
 *     push when the app is killed.
 *   - **JWT** is signed with ES256 against the .p8 key, cached for
 *     ~50 min (Apple's max is 60 min). Refreshed lazily on next send.
 *   - **HTTP/2 session** is opened lazily on first send and kept
 *     warm for subsequent pushes. Dead sessions are detected via the
 *     `error` / `close` events and replaced on next send. We keep one
 *     session per process — Apple's docs say multiple connections
 *     per gateway are fine but unnecessary at our volume.
 *   - **Token failures** (410 Unregistered, 400 BadDeviceToken) prune
 *     the offending row from `DeviceToken` so the next generation
 *     doesn't re-try a known-dead token.
 *
 * Env vars required to activate:
 *
 *   - `APNS_KEY_ID`        — 10-char Apple key ID
 *   - `APNS_TEAM_ID`       — 10-char Apple team ID
 *   - `APNS_BUNDLE_ID`     — bundle ID of the iOS app (`Res.ProEstimate-AI`)
 *   - `APNS_PRIVATE_KEY`   — full PEM contents of the .p8 file. Newlines
 *                            can be escaped as `\n` for env-var transport;
 *                            we normalize back to real newlines on read.
 *   - `APNS_PRODUCTION`    — optional `"true"`/`"false"` to override
 *                            gateway selection. Defaults to production
 *                            when `NODE_ENV === "production"`.
 */

interface ApnsConfig {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKey: string;
  isProduction: boolean;
}

function readConfig(): ApnsConfig | null {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const bundleId = process.env.APNS_BUNDLE_ID;
  const privateKeyRaw = process.env.APNS_PRIVATE_KEY;

  if (!keyId || !teamId || !bundleId || !privateKeyRaw) {
    return null;
  }

  // Allow the .p8 contents to be stored with literal `\n` (the standard
  // Railway / Vercel convention for multi-line secrets); convert back to
  // real newlines so jsonwebtoken's PEM parser recognizes the key.
  const privateKey = privateKeyRaw.includes("\\n")
    ? privateKeyRaw.replace(/\\n/g, "\n")
    : privateKeyRaw;

  const productionOverride = process.env.APNS_PRODUCTION;
  const isProduction =
    productionOverride === "true"
      ? true
      : productionOverride === "false"
        ? false
        : process.env.NODE_ENV === "production";

  return { keyId, teamId, bundleId, privateKey, isProduction };
}

let cachedConfig: ApnsConfig | null = null;
let configLoaded = false;
let warnedMissing = false;

function getConfig(): ApnsConfig | null {
  if (!configLoaded) {
    cachedConfig = readConfig();
    configLoaded = true;
    if (!cachedConfig && !warnedMissing) {
      logger.warn(
        "APNs env vars not set — push notifications disabled. Set APNS_KEY_ID / APNS_TEAM_ID / APNS_BUNDLE_ID / APNS_PRIVATE_KEY to enable.",
      );
      warnedMissing = true;
    }
  }
  return cachedConfig;
}

export function isApnsConfigured(): boolean {
  return getConfig() !== null;
}

// ─── JWT cache ─────────────────────────────────────────────────────────────

const JWT_TTL_MS = 50 * 60 * 1000; // 50 min — Apple's max is 60 min
let cachedJwt: { token: string; signedAt: number } | null = null;

function getProviderToken(config: ApnsConfig): string {
  const now = Date.now();
  if (cachedJwt && now - cachedJwt.signedAt < JWT_TTL_MS) {
    return cachedJwt.token;
  }
  const token = jwt.sign(
    { iss: config.teamId, iat: Math.floor(now / 1000) },
    config.privateKey,
    {
      algorithm: "ES256",
      header: { alg: "ES256", kid: config.keyId },
    },
  );
  cachedJwt = { token, signedAt: now };
  return token;
}

// ─── HTTP/2 session ────────────────────────────────────────────────────────

let session: http2.ClientHttp2Session | null = null;

function getSession(config: ApnsConfig): http2.ClientHttp2Session {
  if (session && !session.destroyed && !session.closed) {
    return session;
  }
  const host = config.isProduction
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const next = http2.connect(host);
  next.on("error", (err) => {
    logger.warn({ err }, "APNs HTTP/2 session error — will reconnect on next send");
    if (session === next) session = null;
  });
  next.on("close", () => {
    if (session === next) session = null;
  });
  session = next;
  return next;
}

// ─── Push payload ──────────────────────────────────────────────────────────

export interface GenerationReadyPayload {
  generationId: string;
  projectId: string;
  projectTitle: string | null;
}

interface ApnsResponse {
  status: number;
  reason?: string;
  apnsId?: string;
}

function sendOne(
  config: ApnsConfig,
  deviceToken: string,
  payload: GenerationReadyPayload,
): Promise<ApnsResponse> {
  return new Promise((resolve, reject) => {
    const sess = getSession(config);
    const body = JSON.stringify({
      aps: {
        alert: {
          title: "Preview ready",
          body: payload.projectTitle
            ? `Your ${payload.projectTitle} AI preview is ready to review.`
            : "Your AI preview is ready to review.",
        },
        sound: "default",
        // `mutable-content`/`content-available` left at default; the
        // alert key is enough to wake the device and surface the
        // notification when the app is killed.
      },
      // userInfo for the iOS tap handler.
      project_id: payload.projectId,
      generation_id: payload.generationId,
      project_title: payload.projectTitle ?? "",
    });

    const req = sess.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${getProviderToken(config)}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      // Group same-project notifications visually in Notification
      // Center on the device.
      "apns-collapse-id": `gen:${payload.generationId}`,
      "content-type": "application/json",
      "content-length": Buffer.byteLength(body),
    });

    let status = 0;
    let responseBody = "";
    let apnsId = "";

    req.on("response", (headers) => {
      status = Number(headers[":status"]) || 0;
      apnsId = (headers["apns-id"] as string) || "";
    });
    req.on("data", (chunk) => {
      responseBody += chunk.toString();
    });
    req.on("end", () => {
      let reason: string | undefined;
      if (responseBody) {
        try {
          reason = (JSON.parse(responseBody) as { reason?: string }).reason;
        } catch {
          // body wasn't JSON — leave reason undefined
        }
      }
      resolve({ status, reason, apnsId });
    });
    req.on("error", reject);

    req.setEncoding("utf8");
    req.write(body);
    req.end();
  });
}

// ─── Public API ────────────────────────────────────────────────────────────

/**
 * Fan out a "preview ready" push to every registered device for `userId`.
 * Returns the number of devices that successfully received the push.
 *
 * Failures are swallowed but logged — push delivery is a best-effort
 * channel and must never block the calling generation pipeline.
 */
export async function sendGenerationReady(
  userId: string,
  payload: GenerationReadyPayload,
): Promise<number> {
  const config = getConfig();
  if (!config) return 0;

  const tokens = await prisma.deviceToken.findMany({
    where: { userId, platform: "APNS" },
    select: { id: true, token: true },
  });
  if (tokens.length === 0) return 0;

  let delivered = 0;
  // Sequential so one bad token can't slow the rest, but no need to
  // fan out concurrently — at our volume each user has 1–2 devices.
  for (const { id, token } of tokens) {
    try {
      const result = await sendOne(config, token, payload);
      if (result.status === 200) {
        delivered++;
      } else if (
        result.status === 410 ||
        (result.status === 400 && result.reason === "BadDeviceToken")
      ) {
        // Token is invalid — delete so the next push skips it.
        await prisma.deviceToken
          .delete({ where: { id } })
          .catch((err) => logger.warn({ err, id }, "failed to prune dead APNs token"));
      } else {
        logger.warn(
          { status: result.status, reason: result.reason, apnsId: result.apnsId },
          "APNs push returned non-200",
        );
      }
    } catch (err) {
      logger.warn({ err, userId }, "APNs send failed for one device");
    }
  }

  return delivered;
}
