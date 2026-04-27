import { createRemoteJWKSet, jwtVerify } from "jose";
import { env } from "../config/env";
import { AuthenticationError } from "./errors";

/**
 * Verifies Google ID tokens (the JWT iOS receives after a user completes
 * Google sign-in) against Google's public JWKS. Mirrors the apple-auth
 * lib's shape so the auth route layer can call them interchangeably.
 *
 * Token validation rules:
 *   - Signature must verify against Google's published JWKS.
 *   - `iss` must be Google's accounts issuer (with or without scheme).
 *   - `aud` must match one of our configured Client IDs (iOS or Web).
 *   - `sub` must be present — that's the stable Google user ID we
 *     persist as `User.googleId`.
 *
 * The pair of accepted audiences exists because:
 *   1. Native iOS sign-in uses the iOS Client ID.
 *   2. A future Next.js web app will use the Web Client ID.
 *   3. Server-side ID-token verification in some Google libraries also
 *      issues tokens audienced for the Web Client ID even when triggered
 *      from iOS.
 */

const GOOGLE_JWKS_URL = new URL("https://www.googleapis.com/oauth2/v3/certs");
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

const googleJWKS = createRemoteJWKSet(GOOGLE_JWKS_URL);

export interface GoogleTokenClaims {
  /** Stable Google user ID — persisted as `User.googleId`. */
  sub: string;
  email?: string;
  emailVerified: boolean;
  name?: string;
  givenName?: string;
  familyName?: string;
  picture?: string;
}

export class GoogleAuthNotConfiguredError extends Error {
  constructor() {
    super("Google OAuth client IDs are not configured on this server");
    this.name = "GoogleAuthNotConfiguredError";
  }
}

function configuredAudiences(): string[] {
  const auds: string[] = [];
  if (env.GOOGLE_OAUTH_IOS_CLIENT_ID) auds.push(env.GOOGLE_OAUTH_IOS_CLIENT_ID);
  if (env.GOOGLE_OAUTH_WEB_CLIENT_ID) auds.push(env.GOOGLE_OAUTH_WEB_CLIENT_ID);
  return auds;
}

/**
 * Verify a Google ID token. Throws `GoogleAuthNotConfiguredError` when
 * neither client ID is set on the server (lets the route surface a 503
 * instead of a confusing 401), or `AuthenticationError` for any other
 * verification failure.
 */
export async function verifyGoogleIdentityToken(
  identityToken: string,
): Promise<GoogleTokenClaims> {
  const audiences = configuredAudiences();
  if (audiences.length === 0) {
    throw new GoogleAuthNotConfiguredError();
  }

  try {
    const { payload } = await jwtVerify(identityToken, googleJWKS, {
      issuer: GOOGLE_ISSUERS,
      // jose accepts an array of acceptable audiences out of the box.
      audience: audiences,
    });

    const sub = payload.sub;
    if (!sub) {
      throw new AuthenticationError("Google identity token missing subject");
    }

    // `email_verified` is a boolean in Google's payload, but be defensive
    // since the JWT spec allows it as a string ("true") in some flows.
    const rawVerified = payload["email_verified"];
    const emailVerified =
      rawVerified === true ||
      rawVerified === "true" ||
      rawVerified === 1 ||
      rawVerified === "1";

    return {
      sub,
      email: payload["email"] as string | undefined,
      emailVerified,
      name: payload["name"] as string | undefined,
      givenName: payload["given_name"] as string | undefined,
      familyName: payload["family_name"] as string | undefined,
      picture: payload["picture"] as string | undefined,
    };
  } catch (error) {
    if (error instanceof AuthenticationError) throw error;
    if (error instanceof GoogleAuthNotConfiguredError) throw error;
    throw new AuthenticationError("Invalid Google identity token");
  }
}
