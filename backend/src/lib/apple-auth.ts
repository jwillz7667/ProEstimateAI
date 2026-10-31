import { createRemoteJWKSet, jwtVerify } from 'jose';
import { AuthenticationError } from './errors';
import { verifyIdentityNonce } from './identity-nonce';

const APPLE_JWKS_URL = new URL('https://appleid.apple.com/auth/keys');
const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_AUDIENCE = 'Res.ProEstimate-AI';

const appleJWKS = createRemoteJWKSet(APPLE_JWKS_URL);

export interface AppleTokenClaims {
  sub: string; // Stable Apple user ID
  email?: string;
  email_verified?: string | boolean;
}

/**
 * Verify an Apple identity token JWT against Apple's JWKS endpoint.
 * Validates issuer, audience, and signature.
 * Returns the decoded claims with the stable `sub` (Apple user ID) and optional email.
 */
export async function verifyAppleIdentityToken(
  identityToken: string,
  rawNonce?: string,
): Promise<AppleTokenClaims> {
  try {
    const { payload } = await jwtVerify(identityToken, appleJWKS, {
      issuer: APPLE_ISSUER,
      audience: APPLE_AUDIENCE,
      algorithms: ['RS256'],
      requiredClaims: ['sub', 'iat', 'exp'],
    });
    verifyIdentityNonce(payload.nonce, rawNonce);

    const sub = payload.sub;
    if (typeof sub !== 'string' || !sub.trim()) {
      throw new AuthenticationError('Apple identity token missing subject');
    }

    return {
      sub,
      email: typeof payload.email === 'string' ? payload.email : undefined,
      email_verified: payload.email_verified === true || payload.email_verified === 'true',
    };
  } catch (error) {
    if (error instanceof AuthenticationError) {
      throw error;
    }
    throw new AuthenticationError('Invalid Apple identity token');
  }
}
