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

The user selected **Viral Ventures LLC** as the intended Stripe business. The connected account and matching dashboard identity were verified. After the user explicitly approved the Connect agreement and restricted backend credentials, the platform configuration was submitted and the user completed Stripe's identity-document/selfie verification. Stripe subsequently displayed **Review in progress**, with live account creation unavailable while its review continues.

A dedicated restricted live key was created and saved privately in `backend/.env` with mode 0600. A GET-only SDK probe successfully listed Accounts v2 and returned zero connected merchants. The runtime key and ProEstimate webhook signing secret were installed only on the destination Railway API, with collection explicitly disabled. A private before/after comparison confirmed every other variable remained unchanged. Credential deployment `ddc0ee94-29d5-4d71-8766-509962cd7f58` is healthy and rejects unsigned webhooks with `400 INVALID_WEBHOOK_SIGNATURE`. Railway rebuilt its retained `d9aab6f` source for this redeploy, producing a different image digest; no new source was uploaded. No live connected merchant, charge, refund or money movement was created. Remaining activation work includes isolated sandbox verification of merchant creation/onboarding, Checkout, exact payment/refund reconciliation, and the selected webhook event version. Do not claim live collection works until provider verification and Stripe's platform approval both succeed.

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

The completed workflow is in draft [PR 56](https://github.com/jwillz7667/ProEstimateAI/pull/56). Xcode 26.3 CI exposed a SwiftUI type-checking timeout in the project-detail presentation expression; `d9aab6f` splits that expression without changing its behavior. All four remote workflows subsequently passed at that commit: iOS generic build/Foundation regressions, backend, website and release safety. No simulator was booted. The subsequent production rollout and signed App Store Connect upload are recorded below.

## Production rollout

The Railway API deployment `c80d1f69-80af-4967-b3f0-32fd03590e5d` successfully deployed the reviewed `d9aab6f` source in the destination account. Startup applied the ten new migrations, bringing the database to all 33 migrations. Public health checks reported connected PostgreSQL and Redis; protected new routes rejected unauthenticated requests and invalid public document tokens returned 404.

The Railway website deployment `514e30ab-bd46-4c00-9136-d55398fb41de` successfully deployed the same reviewed source. Initial source uploads failed with TLS `BadRecordMac` before a build started. A web-only archive containing every tracked website file uploaded successfully over a verified IPv4 connection limited to 512 KiB/s; no assets were removed and certificate verification remained enabled. Public checks passed on the Railway hostname, `proestimateai.com` and `www.proestimateai.com`. All 23 deployed PNG/JPG files matched the reviewed source by SHA-256, and invalid invoice/reminder tokens returned 404 without a server error. Existing root directories, Dockerfile builders, startup/migration commands, variables and domains were preserved. API and website have no Git source attached, so pushing the development branch alone does not deploy them.

Stripe collection remains disabled. The approved configuration uses direct seller payments, Stripe-hosted onboarding, full Stripe Dashboard access and Stripe-managed seller loss liability. The connected-account webhook `we_1UXqKnDLaRoyLG9fTzMto0Xt` was created for the deployed API route with all nine required payment/refund/dispute event types. Stripe rejected a new Endive destination because this shared business has reached its limit of three unique live event versions. The destination therefore reuses the business's existing `2026-08-26.dahlia` version; unrelated event destinations were not changed. Its signing secret was saved privately locally and in Railway. The backend still makes fresh resource API calls through Node SDK 23.1.0 (`2026-10-28.endive`); compatibility of the older snapshot-event envelope must be established in the real sandbox before collection is enabled.

A separate blank private sandbox, **ProEstimate payments verification** (`acct_1UXqZxDo45VzCokA`), was created under Viral Ventures LLC without copying live data or settings. An equivalent restricted backend test key was created and saved only in the private temporary verification directory. The sandbox Connect agreement review is prepared with the same configuration and awaits its separate action-time approval. Disposable local database setup and connected-event forwarding are being prepared independently; no provider merchant/payment/refund test has yet completed.

The signed iOS upload workflow [41731062569](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41731062569) archived and uploaded **1.0.9 (15)** from `d9aab6f` under the earlier upload instruction. Read-only [status verification](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41732389464) confirmed the new build is **VALID**, unexpired, and its upload **COMPLETE**, with no errors or warnings. The workflow archived for a physical iOS target using existing signing credentials; no simulator was launched. Build **14** remains selected for the App Store version and has since been approved, **PENDING_DEVELOPER_RELEASE** with manual release. Build **15** has not been selected or submitted for review, and the older build was not released or withdrawn. See `operations/validation-2026-11-03/app-store-upload-d9aab6f.json` for exact evidence.
