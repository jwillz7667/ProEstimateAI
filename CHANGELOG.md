# Changelog

All notable changes to ProEstimate AI are recorded in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Dates are in `YYYY-MM-DD` format.

---

## [Unreleased]

### Added
- Professional repository layer: README, proprietary LICENSE, CONTRIBUTING, SECURITY, CHANGELOG, editor config, issue and pull-request templates, CODEOWNERS, Dependabot, and CI workflows for iOS and backend.
- `SubscriptionState.adminOverride` case so the client can decode the backend's `ADMIN_OVERRIDE` entitlement status. Treated as Pro access across the app.
- Per-estimate "Create Invoice" context menu on the project detail view, routed through `guardCreateInvoice()` and opened in a sheet via `InvoicePreviewView`.

### Changed
- Estimate and invoice creation now flow exclusively through the project detail screen. The Estimates and Invoices tabs became read-only browsers and direct users to Projects via the empty state.
- Project detail view adopted `.sheet(item:)` with `Identifiable` wrappers to drive the estimate editor and invoice preview, eliminating a race where the previous `sheet(isPresented:) + if let id` pattern could render an empty sheet.
- Project detail view now surfaces `viewModel.errorMessage` via an alert whenever a project is loaded, so `createEstimate` and `createInvoice` failures no longer fail silently.
- Estimates list rows display the real project title (enriched from the loaded project list) instead of the raw project id.

### Removed
- `InvoiceCreationSheet`, which required users to type an estimate id manually.
- `CLAUDE.md`, `project-specs/`, `screenshots/`, `backend-api-spec.md`, and loose root-level simulator screenshots from git tracking. These now live locally only, via the new `.gitignore`.

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
