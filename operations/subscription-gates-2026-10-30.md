# Subscription access corrections — October 30, 2026

The confirmed policy is: new AI previews, AI material/labor pipelines and AI-generated estimates require an active verified Apple subscription or introductory trial. Basic sign-in, reading projects, manual project/photo saves and manual estimates remain available without upgrading. Monthly and annual introductory offers are three days for eligible subscribers; Apple governs eligibility. Previously signed seven-day trials retain their actual signed expiry.

## Backend behavior

- Removed implicit unlimited Pro and AI-limit bypasses based on `ADMIN_EMAILS`. Operational admin permissions remain separate. Only the explicitly provisioned `APP_REVIEW_DEMO` administrative grant is treated as a purchase exception, using ordinary finite Pro limits.
- Historical starter/custom credit rows remain stored, but do not unlock new AI or exports. New email/Apple/Google accounts receive no starter AI allowance. Unpaid snapshots have no spendable usage buckets and no paid feature flags.
- Image and text-only generation share the same subscription gate before job/provider work. Direct AI-estimate generation uses its separate paid metric. Reading/editing existing generated results is not a new paid compute request.
- Manual project creation does not call the AI gate, does not reserve quota and no longer has the old two-project paid cap. Historical project events are preserved but excluded from current billable usage.
- Legacy users with a missing entitlement receive a Free row through conflict-safe create-only backfill. Concurrent requests cannot overwrite a purchase or fail on duplicate insert. Expired/revoked/retrying accounts can still use manual tools.
- Restoring a valid historical signed transaction with an unknown pre-migration app-account token can establish its first destination owner. Existing ownership cannot be reassigned to another destination account, including after expiration/refund. Known signed purchase-attempt owners remain protected.
- Apple-signed Sandbox and Production transaction environments are accepted. Local Xcode transaction data is rejected; the cryptographic boundary still requires the pinned Apple certificate chain. Environment acceptance tests mock that signature boundary and are not real sandbox purchases.
- The catalog migration changes offer text/flags and removes manual-project limits only. It does not change prices, customer subscription state, signed dates, purchase history or credit balances. A versioned catalog cache key prevents a deployment from reusing old seven-day offer metadata.

## Verification

226 unit tests and 112 real-PostgreSQL integration cases passed. Production compilation and integration typechecking passed. Lint has zero errors and one pre-existing unused-parameter warning in `prompts/lawn-care.ts`. Real PostgreSQL tests use the disposable loopback database on port 55440; no production database was used. Decisive regression cases cover:

- HTTP 402 for unpaid image, text-only and direct AI-estimate requests before provider invocation, even with large historical/custom balances.
- Three manual project saves plus manual estimates for Free, expired, revoked, billing-retry, paid and trial states without any quota event.
- Concurrent legacy entitlement backfill, email-admin denial, finite reviewer override and preserved signed trial/credit data through the actual SQL migration.
- A migrated unknown signed UUID restore, concurrent first ownership, permanent existing-owner protection, and signed environment handling.
- Existing async refund/reaper guarantees, including recovery of historical starter-backed jobs, remain covered.

Deployment, App Store offer writes and real device purchase/restore checks are coordinated separately by the primary agent. Test output must distinguish mocked Apple/provider boundaries from real StoreKit evidence.

## Stored PDFs and the existing upload contract

Existing saved PDF metadata/binary reads remain ungated by subscription, with ownership checks for metadata and the existing unguessable file URL for binary access. The new upload endpoint now requires effective paid export access after verifying estimate ownership. Free/expired new uploads return 402 without a PDF record or quota charge.

iOS renders locally, consumes `QUOTE_EXPORT` through `/usage/check`, then separately uploads the saved PDF. Storage does not charge the event again. A paid client that directly uploads while skipping its existing pre-approval can still omit that counter; full atomic cap enforcement for this path requires a receipt-bound render/upload contract. That redesign is intentionally separate from this paid-access correction, avoiding double charges for current clients.
