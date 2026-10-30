# Changelog

All notable changes to ProEstimate AI are recorded in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Dates are in `YYYY-MM-DD` format.

---

## [1.0.8] - 2026-10-13

### Added
- Assign or create a client from project editing, enabling estimate-to-invoice conversion.
- Record partial invoice payments and show the remaining balance in the iOS app.
- Print or save public proposals as PDF from the browser.
- Read-only App Store release status inspection through the metadata workflow.

### Fixed
- Load all cursor pages of projects, clients, estimates and invoices rather than hiding records after page one.
- Clear nullable project metadata correctly and validate budget and measurement input.
- Surface project-list and material-selection failures; keep generation monitoring active when deletion fails.
- Check invoice proposal references against the current company, project and estimate.
- Preserve agreed invoice tax rates through payment and line-item updates, with an additive historical tax snapshot migration.
- Serialize estimate/invoice line edits and proposal responses; invalidate public proposal data after changes.
- Use client-facing proposal URLs in outbound proposal emails.
- Show completed proposal statuses accurately after expiration; isolate private proposal responses from caches and search indexing.
- Align website plan limits with the enforced backend catalog and remove retired Premium claims.
- Handle malformed support requests and API responses, with targeted dependency security updates.

### Changed
- Run backend and CI on supported Node.js 24 LTS.
- Reuse existing distribution credentials and read-only provisioning profiles for TestFlight; stop releases on App Store access failures and preserve reviews already in progress.

## [Unreleased]

### Fixed
- Reconcile signed App Store expiry, renewals, revocations and ownership atomically; preserve historical Premium restores without reopening retired sales.
- Enforce finite server usage and paid feature gates; refund failed asynchronous image generations exactly once while preserving audit history.
- Keep StoreKit receipts unfinished until backend acknowledgement, recover migrated purchase attempts through verified restore, and align iOS paywalls with server states and actual StoreKit offers.
- Validate Apple/Google nonce proofs and required token claims; reconcile concurrent first sign-ins without duplicate users or credit grants.
- Prevent failed line-item reads or PDF rendering from consuming export quota or producing misleading empty estimates.
- Improve signup validation, keyboard access, search targets, comparison accessibility, reduced motion and tablet dashboard sizing.
- Patch backend and website dependencies, including Zod collection validation and Next.js security fixes.
- Bootstrap fresh backend databases before creating online indexes, and resolve indexes in the configured database schema.
- Make auth UI initialization main-actor isolated and select Xcode 26 for simulator CI.
- Drain in-flight HTTP requests before disconnecting backend dependencies during shutdown, with a bounded timeout.
- Replace retired API URLs in iOS, web, backend-generated links, and active setup documentation.

### Added
- Cohesive App Store campaign concepts with 18 exact-dimension RGB PNG exports across iPhone and iPad families, editable SVG panoramas and actual tablet captures.
- Backend billing, OAuth, iOS and migration audit reports with deployment evidence and explicit remaining integration checks.
- Low-cost fal.ai FLUX.2 Flash previews with reference-photo editing, bounded requests, and existing-provider fallbacks.
- Production catalog bootstrap and Railway deployment support for the API and website.
- Backend CI lint, unit tests, and real PostgreSQL integration coverage, including empty-database and repeated bootstrap checks.

## [1.0.0] - 2026-04-19

First App Store release.

### Added
- **AI preview pipeline** — snap a site photo, get a photoreal before/after remodel render through PiAPI Nano Banana Pro (primary) with a Google GenAI Gemini 3.1 Flash Image fallback, then a follow-up Gemini text call that drops material + labor suggestions into the project.
- **AI-generated estimates** — new "Generate with AI" CTA on the project detail view. Gemini writes a complete client-ready estimate (title, overview, grouped line items, assumptions, exclusions, terms) using the project's selected materials, the company's branding, and any configured pricing profile + labor rates. Pro-gated under `AI_ESTIMATE_LOCKED`.
- **Professional PDF documents** — rebuilt `PDFGenerator` renders branded letterheads (logo + address + contact), two-column headers, category-banded line items with zebra rows, accent-color totals panels, and Scope Assumptions / Exclusions / Notes / Terms blocks. Shared across estimate, invoice, and proposal exports.
- **Project creation wizard** — 6-step flow (type → client → photos → prompt → details → review). Users can name the project up front; auto-name falls back to type + client. Final review step carries a toggle that kicks off an AI preview automatically after the project opens.
- **Project detail edit sheet** — form-style editor for title, description, type, quality tier, budget range, square footage, and dimensions without re-entering the wizard.
- **Estimate editor** — grouped materials / labor / other sections with swipe-to-delete, drag-to-reorder, line-item markup and tax, a DIY toggle that strips labor costs for owner-operated jobs, and a sticky totals bar.
- **Invoice flow** — auto-numbered invoices created from any approved estimate via a per-row context menu. Partial payments, overdue banners, payment progress bar.
- **Proposal flow** — generates a shareable public approval link, branded proposal preview, and a PDF export.
- **StoreKit 2 subscriptions** — Pro Monthly ($19.99 with 7-day introductory free trial) and Pro Annual ($149.99). Server-authoritative entitlement store, atomic free-tier credit consumption, purchase reconciliation via the backend, refund-driven revocation, and full Apple-required disclosure text on the paywall.
- **Bilingual UI** — 441 user-facing strings fully translated to Spanish (Latin American) via `Localizable.xcstrings`.
- **Modern list pages** — Estimates and Invoices tabs rebuilt around `MetricCard` summaries, count-bearing filter pills, and glass-card rows with leading status icons.
- **Auth** — email / password plus Sign in with Apple, JWT access tokens with rotating refresh and reuse detection. Account deletion flow in Settings for Guideline 5.1.1(v) compliance.
- **Repository infrastructure** — README, proprietary LICENSE (Viral Ventures LLC, Minnesota), CONTRIBUTING, SECURITY, editorconfig, issue / PR templates, CODEOWNERS, Dependabot, and CI workflows for iOS, backend, web, and TestFlight.
- **Fastlane** — `beta`, `metadata`, and `submit` lanes backed by an App Store Connect API key. App Store Connect metadata (categories, localized copy, screenshots for iPhone 6.9" and iPad 13") pre-populated in `fastlane/metadata`.

### Changed
- Estimate and invoice creation flow exclusively through the project detail screen; the Estimates and Invoices tabs are read-only browsers with a "Go to Projects" CTA when empty.
- `Info.plist` forces Dark appearance to match the app's dark-first design; privacy usage descriptions localized for Spanish.
- `PrivacyInfo.xcprivacy` declares Email, Name, Phone, Physical Address, Photos or Videos, Other User Content, Customer Support, and Purchase History — all linked, none for tracking.
- Subscription state enum picked up the `adminOverride` case to match the backend's `ADMIN_OVERRIDE` value.
- AI preview polling is resilient to transient network failures (tolerates 5 consecutive misses before showing an error, 4-minute window, auto-resumes on project re-load).

### Fixed
- PDF export actually opens the share sheet — the previous `sheet(isPresented:)` + `if let url` pattern was racing against SwiftUI state commits.
- Estimate / invoice sheet-item drivers no longer drop ids on the first tap.
- Silent failure when the generation polling loop expired without a terminal status now surfaces a clear retry prompt.
- Project detail view surfaces `viewModel.errorMessage` through an alert, so estimate and invoice creation failures no longer fail silently.

### Removed
- `InvoiceCreationSheet` (required typing an estimate ID by hand).
- `CLAUDE.md`, `project-specs/`, `screenshots/`, `backend-api-spec.md`, and loose simulator screenshots from git tracking.

## [1.0.0] - 2026-04-16

Initial production release.

### Added
- Native iOS application with SwiftUI, StoreKit 2 subscriptions, Apple Sign In, and bilingual English/Spanish localization.
- Photo-to-proposal product loop: photo upload, AI remodel preview (PiAPI Nano Banana Pro with Google GenAI fallback), auto-generated materials and labor, estimate editor, shareable proposal, and invoice creation.
- Backend API on Node.js + Express + Prisma + PostgreSQL with cursor-based pagination, structured logging, Redis-backed rate limiting, and production hardening (compression, graceful shutdown, request IDs).
- Server-side entitlement enforcement with atomic usage bucket consumption and StoreKit 2 purchase reconciliation.
- Auth flow with JWT access tokens and rotating refresh tokens, including refresh-token reuse detection.
- Apple Liquid Glass design system with `#FF9230` brand accent, dark-first palette, and reusable components.
- iPad-responsive layouts and iOS 26 system color adoption.
- App Store submission readiness: paywall compliance for guideline 3.1.2, account deletion flow, onboarding trial, proposal share page, and a comprehensive seeded dataset for review.

### Fixed
- Auth-gate splash hang on cold launch.
- Inflated material and labor pricing in AI-generated estimates.
- Paywall trapping users without an escape route; the dismiss control is now always reachable.

---

[Unreleased]: https://github.com/jwillz7667/ProEstimateAI/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jwillz7667/ProEstimateAI/releases/tag/v1.0.0
