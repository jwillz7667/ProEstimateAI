# Contractor workflow implementation

The user authorized implementing the competitive research recommendations, beginning with sent-quote protection, direct estimate creation and actionable Home. **Keep simulators closed.** Validation uses Foundation executables, isolated PostgreSQL integration tests, web tests and compile-only iOS builds. Existing localization edits and local browser/Xcode user state are unrelated and must remain untouched.

## Delivery order and status

- Implemented: immutable sent-quote snapshots, lifecycle edit locks, safe resumable draft revisions, frozen private recipient and stale-review protection.
- Implemented: one-screen manual/AI/template estimate creation, early client selection, backing project creation and visible review/send action. Manual work does not call an AI provider or consume AI quota.
- Implemented: tenant-scoped Home attention queue with full-company counts, separate currency totals and navigation to the exact document.
- Implemented: complete paginated client project history and client-detail navigation.
- Implemented: estimate duplication, reusable saved line items and templates, with durable request replay protection and native selection/import flows.
- Implemented: editable draft scope, terms, assumptions/exclusions, validity and discount. Contingency remains explicitly labelled reference metadata.
- Implemented: public invoice page, append-only receipts, manual cash/check/bank recording, deposits and milestone schedules.
- Implemented, online activation pending: optional Stripe connected merchant onboarding, direct contractor checkout, verified/idempotent payment and refund reconciliation. Live collection remains off without the intended Stripe account and validated configuration.
- Implemented: customer request-changes responses and typed acceptance of a hashed frozen document; identity is explicitly self-attested.
- Implemented: explicit change orders with customer-approved old/new/delta comparison, separate delta invoices and distinct credit-note allocations. Approved changes before the first invoice are included in a single full invoice; the original agreed financial basis is protected.
- Implemented: manual follow-up actions and contact history, configurable state-aware reminders, unsubscribe controls and a durable delivery queue. Automatic reminders are off by default; provider acceptance is not labelled delivery.
- Implemented: internal price origin, source/check dates and measured-quantity basis. Contractor checks are not represented as independent supplier verification; changed prices/quantities invalidate affected checks.
- Implemented: account-scoped protected draft preservation, frozen pending operations and restart/retry reconciliation. This preserves work in progress; it does not promise arbitrary offline API operations.
- Implemented: actual material/labor costs, hours/rates, private receipt attachments, void history and estimated-versus-recorded comparisons separated by currency.
- Implemented: current server-role checks on business mutations, read-only native controls and log redaction for public bearer document/image URLs and query contents.

Scheduling/crew management and LiDAR were identified as later opportunities after the core journey; do not represent them as delivered by this workflow change.

## Payment decisions

Apple StoreKit continues to handle the ProEstimate digital subscription. Customer payments for contractor work are a separate optional collection flow. Recommended architecture is direct charges to each contractor's connected merchant account; ProEstimate does not hold job funds. Manual cash/check/bank-transfer recording remains supported.

The user selected **Viral Ventures LLC** as the intended Stripe business. After initially returning reauthentication errors, all three connections successfully identified that same live account. Read-only provider inspection returned no connected merchants and no ProEstimate webhook destination. Neither local backend configuration nor Railway contains a Stripe variable. No live onboarding, charges, refunds or money movement were performed. Production activation requires a deployable restricted key, the ProEstimate webhook/signing secret and isolated sandbox verification. The chat connection does not supply a backend API key. Do not claim live collection works until provider verification succeeds.

Payment return URLs never mark an invoice paid. Credits are separate from cash received. Open checkout amounts stay frozen; manual balance changes require safe cancellation first. Destructive erasure must not remove reconciliation records while an active customer payment can still succeed.

## Validation boundaries

Foundation model regression runners and generic iOS SDK builds do not boot a simulator. Browser verification uses synthetic localhost documents. PostgreSQL tests run on disposable local databases, with third-party email/payment adapters injected. Runtime iPhone/iPad touch and visual verification remains unperformed because simulators must stay closed. No new App Store binary or production deployment is implied by local implementation checks.

## Integration boundaries

Sent quote agent owns Estimate/Proposal schema changes and mutation/snapshot/revision services. Direct creation agent owns creation views and editor/preview delivery actions. Home agent owns dashboard API/state/view and route highlighting. Root owns client history and cross-feature integration. Add subsequent schema migrations separately and coordinate Prisma generation/test databases.

Tests must never use Railway production data. Local disposable PostgreSQL is on loopback port 55439, with a separate database per agent to avoid shared TRUNCATE interference.

## Final combined verification

Validated the completed code at `8cfd29d` with all agents' changes integrated:

| Check | Result |
| --- | --- |
| Backend source and integration-test TypeScript checks, production build | Passed |
| Backend unit tests | 245 passed in 29 files |
| Complete PostgreSQL integration suite | 270 passed in 32 files |
| Migration bootstrap | All 33 migrations applied to a new disposable local database; subsequent complete suite passed against the same schema |
| Native Foundation regressions | 647 checks across all 15 runners passed |
| iOS app compilation | Generic arm64 simulator SDK build passed; no simulator boot or app launch |
| Website unit tests | 26 passed |
| Website browser regressions | All 8 synthetic localhost cases passed in headless Chrome, including mobile customer approval/change-order comparison and print recovery |
| Website production build and lint | Passed; two existing lint warnings |
| Backend lint | Passed; one existing warning in the lawn-care prompt |

Final review corrections include frozen request identity before the first awaited journal write, expired-trial confirmation of an already committed change order, duplicate legacy full-invoice detection, protected estimate-derived invoice prices, recipient validation before conversion, and deterministic Home actions for the latest amendment. Test-only catalog state is explicitly isolated so a prior billing test cannot change checkout fixture permissions.

The workflow code is prepared for review; no new Railway deployment or App Store binary was created in this implementation phase. The existing Railway environment was inspected read-only and had no staged changes. API, website, PostgreSQL and Redis reported successful deployments. API and website have no Git source attached, so pushing the development branch does not deploy them.
