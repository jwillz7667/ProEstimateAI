# Billing and database contract audit — October 30, 2026

## Result

The API and iOS contract had concrete gaps in purchase reconciliation, subscription expiry, feature authorization, usage limits, and failed-generation credit handling. The backend fixes are covered by automated regression tests with real disposable PostgreSQL. These tests do not establish successful real StoreKit purchases or App Store notification delivery.

## Corrected behavior

| Area | Resulting behavior |
| --- | --- |
| Signed purchase authority | Expiration, trial offers, and revocation come from the verified Apple transaction. Replaying an expired receipt cannot create a new paid period. |
| Ownership and renewal | Transaction-scoped subscription/account locks serialize competing claims. Known signed purchase tokens bind to their original account; completed attempts can reconcile legitimate renewals/product transitions. Historical unknown tokens can be restored after the approved fresh database start. |
| Apple notifications | Signed chronology prevents delayed notifications or refunds of earlier periods from replacing a newer paid period. Duplicate notifications are idempotent; transient processing failures return 503 so Apple can retry. |
| Effective access | Paid access ends at the signed deadline even when a notification is late. Grace access requires a live grace deadline; billing retry alone does not grant paid service. |
| Product tiers | Only Pro monthly/annual are sold. Retired Premium monthly/annual records are available for verified historical restores, with finite plan-specific limits. They remain unavailable for new purchase attempts. |
| Usage contract | Four canonical usage metrics are exposed to iOS. Real rolling counters replace misleading unlimited subscription buckets. Concurrent reservations serialize before checking capacity. Refunded quantity-zero audit events do not count toward caps/reset calculations. |
| Server feature gates | Approval links, custom branding, property maps, invoice creation, watermark removal, and server PDF exports check effective access on the API. Ordinary company details, unchanged branding values, and logo deletion remain editable. |
| Async generation refunds | Reservation, generation, and exact linkage commit together. Failed jobs and stale-job cleanup atomically mark failure and refund the linked bucket/event once. Late providers cannot revive refunded jobs. Text-only intent is persisted; legacy rows receive no guessed credit refund. |
| Connection pressure | Admin lookup inside a reservation uses the same transaction connection, avoiding a second-connection pool deadlock. |

## Validation

- 198 unit tests passed.
- The full 92-case integration suite passed; the subsequently added single-connection pool regression passed separately, for 93 distinct verified integration cases.
- Production build and integration TypeScript checks passed.
- Lint passed with zero errors and one existing unused-argument warning in lawn-care code; `git diff --check` passed.
- All database tests used `127.0.0.1:55439/proestimate_integration`, a disposable local PostgreSQL database. They did not inspect or modify production customer records.

Integration coverage includes signed expiry/trial/refund snapshots, ownership races, UUID token casing, renewals, out-of-order/replayed notifications, finite usage counters, quote reservations, dormant Premium restores, paid API gates, rollback fault injection, repeated refunds, concurrent reapers, late provider completion, retained refund metadata, and text-only/legacy safeguards.

## Remaining environment validation

Run real sandbox/TestFlight purchase, restore on a fresh account, renewal, cancellation, grace/retry, expiry, refund/revocation, and server notification delivery. The copied source configuration lacked App Store Server API issuer/key/private-key credentials, so authenticated Apple history cross-checks are not configured. Signed receipt verification remains the primary proof path.

The user approved a new empty application database; old users and purchase-attempt rows were not restored. Historical purchases therefore require an authenticated new account and verified restore. No promise of restored customer projects or historical invoices is made. Keep the old volume intact for optional future recovery.

Text AI still requires confirmed DeepSeek funding. APNs and outbound email require the missing provider credentials and delivery checks. See [railway-migration.md](railway-migration.md) and the separate iOS audit for deployment/runtime status.
