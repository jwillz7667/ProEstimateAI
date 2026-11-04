# Apple and Google sign-in audit — October 30, 2026

## Status

Both native sign-in paths are implemented and their source/configuration checks pass. A real interactive Apple or Google sign-in on the signed release app has **not** been demonstrated in this session; do not report either provider as fully verified end to end.

## Configuration checked

- The app includes the Sign in with Apple entitlement. The API Apple identity-token audience matches bundle identifier `Res.ProEstimate-AI`.
- Google uses authorization code + PKCE, checks callback state, and has its reversed client-ID URL scheme registered in `Info.plist`.
- A read-only comparison confirmed that the deployed API's Google iOS client ID exactly matches the app's `GIDClientID`. A Google web client ID is also configured. Values were compared in memory; provider secrets were not printed.
- Apple and Google tokens are verified against provider JWKS with issuer, audience, signature, and required subject/issued-at/expiration claims. Unverified client email cannot authorize account linking.

## Fixes

- Added cryptographically random state and nonce to the Apple request, callback state validation, and SHA-256 nonce requests for both providers. The raw nonce is sent only to the app API, which verifies the provider-signed nonce.
- Missing/incorrect nonce proof is rejected for nonce-bearing tokens. Older released clients whose tokens and requests both omit a nonce remain compatible; this is an explicit compatibility limit.
- Restricted identity-token algorithms to RS256, required `sub`, `iat`, and `exp`, bounded request token lengths, and validated optional claim types.
- Reproduced a concurrent first-login race where only one of six identical sign-ins succeeded. A bounded reconciliation retry now resolves all six to one user/company/credit allocation for each provider.
- Preserved existing verified-email/account-linking protections and inactive-account checks.

## Evidence

- Backend production build and integration TypeScript checks passed.
- 221 backend unit tests passed, including the new JWT verification cases.
- Nine focused PostgreSQL OAuth/auth cases passed, including first login and concurrent account creation. Provider-proof boundaries are mocked in account-persistence integration tests; separate JWT tests use signed fixtures. These are not live provider logins.
- 110 standalone Swift behavior regressions and a Build iOS Apps simulator compilation passed after the client nonce/state and purchase recovery changes. Subsequent frontend changes must retain their own final build evidence.

## Remaining lifecycle and release checks

1. Complete real Apple and Google sign-in on a properly signed device/TestFlight build. Verify first login, returning login, callback/cancel behavior, private-relay Apple email, and linking to an existing verified-email account. Provider console bundle/capability and consent configuration cannot be proven by matching local files alone.
2. Apple authorization codes are collected but not exchanged for server tokens. Account deletion removes application data but does not call Apple's token-revocation endpoint. No Apple Sign in server key/client-secret configuration exists in the copied environment. Full revocation needs those credentials and a deliberate server-token storage/revocation implementation. See [Apple's account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
3. The client does not yet persist the Apple provider subject for `getCredentialState` checks or observe Apple credential-revocation notifications. That lifecycle enhancement remains separate from successful JWT-based login.

The signed-in simulator checks completed in this session used email/password and an isolated disposable QA account. They do not substitute for either provider's interactive flow.
