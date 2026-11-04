import { createHash, timingSafeEqual } from 'node:crypto';
import { AuthenticationError } from './errors';

/** New clients prove possession of the raw nonce sent as a hash to the provider. */
export function verifyIdentityNonce(signedNonce: unknown, rawNonce?: string): void {
  // Older released clients did not request a nonce. Retain that token contract.
  if (signedNonce === undefined && rawNonce === undefined) return;
  if (typeof signedNonce !== 'string' || !rawNonce) {
    throw new AuthenticationError('Identity token nonce proof is missing');
  }
  const expected = Buffer.from(createHash('sha256').update(rawNonce, 'utf8').digest('hex'));
  const actual = Buffer.from(signedNonce);
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new AuthenticationError('Identity token nonce does not match this sign-in request');
  }
}
