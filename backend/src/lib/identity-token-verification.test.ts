import { createHash } from 'node:crypto';
import { generateKeyPair, exportJWK, SignJWT, type JWTPayload } from 'jose';
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const configuration = vi.hoisted(() => ({ GOOGLE_OAUTH_IOS_CLIENT_ID: 'ios-client.apps.googleusercontent.com' as string | undefined,
  GOOGLE_OAUTH_WEB_CLIENT_ID: 'web-client.apps.googleusercontent.com' as string | undefined }));
vi.mock('../config/env', () => ({ env: configuration }));
import { verifyAppleIdentityToken } from './apple-auth';
import { verifyGoogleIdentityToken, GoogleAuthNotConfiguredError } from './google-auth';

let signingKey: Awaited<ReturnType<typeof generateKeyPair>>;
let unrelatedKey: Awaited<ReturnType<typeof generateKeyPair>>;
let jwks: object;
const rawNonce = 'random-client-nonce-at-least-32-characters';
const digest = createHash('sha256').update(rawNonce).digest('hex');
const providers = [
  { name: 'Apple', verify: verifyAppleIdentityToken, issuer: 'https://appleid.apple.com', audience: 'Res.ProEstimate-AI' },
  { name: 'Google', verify: verifyGoogleIdentityToken, issuer: 'https://accounts.google.com', audience: 'ios-client.apps.googleusercontent.com' },
];
beforeAll(async () => {
  signingKey = await generateKeyPair('RS256');
  unrelatedKey = await generateKeyPair('RS256');
  jwks = { keys: [{ ...await exportJWK(signingKey.publicKey), kid: 'local-test-key', use: 'sig', alg: 'RS256' }] };
});
beforeEach(() => {
  configuration.GOOGLE_OAUTH_IOS_CLIENT_ID = 'ios-client.apps.googleusercontent.com';
  configuration.GOOGLE_OAUTH_WEB_CLIENT_ID = 'web-client.apps.googleusercontent.com';
  // Only the published JWKS fetch is replaced. JOSE still verifies real RSA
  // signatures/claims; these test keys are never configured in production.
  vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => {
    expect(String(input)).toMatch(/^https:\/\/(appleid\.apple\.com\/auth\/keys|www\.googleapis\.com\/oauth2\/v3\/certs)$/);
    return new Response(JSON.stringify(jwks), { headers: { 'Content-Type': 'application/json' } });
  }));
});
afterEach(() => vi.unstubAllGlobals());

async function token(provider: typeof providers[number], overrides: JWTPayload = {}, omit: string[] = [], wrongKey = false) {
  const now = Math.floor(Date.now() / 1000);
  const claims: JWTPayload = { sub: 'stable-provider-subject', iss: provider.issuer, aud: provider.audience,
    iat: now, exp: now + 3600, email: 'owner@gmail.com', email_verified: true, ...overrides };
  for (const key of omit) delete claims[key];
  return new SignJWT(claims).setProtectedHeader({ alg: 'RS256', kid: 'local-test-key' })
    .sign(wrongKey ? unrelatedKey.privateKey : signingKey.privateKey);
}

for (const provider of providers) describe(`${provider.name} identity JWT verification`, () => {
  it('accepts a correctly signed audience/issuer/expiry and matching raw nonce proof', async () => {
    const result = await provider.verify(await token(provider, { nonce: digest }), rawNonce);
    expect(result.sub).toBe('stable-provider-subject');
    expect(result.email).toBe('owner@gmail.com');
  });
  it('preserves the legacy no-nonce token contract', async () => {
    await expect(provider.verify(await token(provider))).resolves.toMatchObject({ sub: 'stable-provider-subject' });
  });
  it.each([
    { claims: { aud: 'different-client' } }, { claims: { iss: 'https://untrusted.example' } },
    { claims: { exp: 1 } }, { claims: { sub: '' } }, { omit: ['exp'] }, { omit: ['iat'] },
  ])('rejects an invalid or missing required provider claim: %j', async ({ claims, omit }) => {
    await expect(provider.verify(await token(provider, claims, omit))).rejects.toMatchObject({ statusCode: 401 });
  });
  it('rejects a signature made with an unrelated private key', async () => {
    await expect(provider.verify(await token(provider, {}, [], true))).rejects.toMatchObject({ statusCode: 401 });
  });
  it('rejects a missing/wrong nonce proof and a proof whose signed nonce is absent', async () => {
    const nonceToken = await token(provider, { nonce: digest });
    await expect(provider.verify(nonceToken)).rejects.toMatchObject({ statusCode: 401 });
    await expect(provider.verify(nonceToken, 'a-different-random-client-nonce')).rejects.toMatchObject({ statusCode: 401 });
    await expect(provider.verify(await token(provider), rawNonce)).rejects.toMatchObject({ statusCode: 401 });
  });
  it('does not expose malformed optional profile claims as trusted strings', async () => {
    const result = await provider.verify(await token(provider, { email: { malformed: true }, name: ['bad'] }));
    expect(result.email).toBeUndefined();
  });
});

it('reports Google configuration missing before trying to authenticate a token', async () => {
  configuration.GOOGLE_OAUTH_IOS_CLIENT_ID = undefined;
  configuration.GOOGLE_OAUTH_WEB_CLIENT_ID = undefined;
  await expect(verifyGoogleIdentityToken('not-a-token')).rejects.toBeInstanceOf(GoogleAuthNotConfiguredError);
});
