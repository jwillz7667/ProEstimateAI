# Changelog

All notable changes to ProEstimate AI are recorded in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Dates are in `YYYY-MM-DD` format.

---

## [Unreleased]

(Next version's changes land here.)

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
