# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ProEstimate AI is an iOS-first AI estimating and invoicing platform for contractors, remodelers, and home project professionals. The core workflow is: **Photo upload → AI remodel preview → material suggestions → draft estimate → proposal → invoice**.

The product has three platform targets:
- **iOS app** — SwiftUI native (primary product)
- **Web app** — Next.js on Vercel (admin, sharing, client-view)
- **Backend API** — Node.js + TypeScript, PostgreSQL on Railway

## Build & Run (iOS)

The iOS app is an Xcode project (not SPM-based, no Package.swift).

```bash
# Open in Xcode
open "ProEstimate AI.xcodeproj"

# Build from CLI
xcodebuild -project "ProEstimate AI.xcodeproj" -scheme "ProEstimate AI" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests (when test target exists)
xcodebuild -project "ProEstimate AI.xcodeproj" -scheme "ProEstimate AI" -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- Bundle ID: `Res.ProEstimate-AI`
- Development Team: `487LC4H9U4`
- Deployment Target: iOS 26.4
- Xcode version: 26.4+
- Swift version: 5.0 with `SWIFT_APPROACHABLE_CONCURRENCY` and `MainActor` default isolation enabled

## iOS Architecture

Currently a fresh Xcode project with SwiftUI + SwiftData template. The target architecture per the spec:

- **Persistence**: SwiftData (`ModelContainer` / `ModelContext`) — currently has a single `Item` model
- **Entitlements**: CloudKit (iCloud), Push Notifications (remote-notification background mode)
- **Monetization**: StoreKit 2 auto-renewable subscriptions, single group `proestimate_pro` with monthly + annual products
- **Localization**: English first, Spanish as first-class (string catalogs enabled)
- **Design**: Apple Liquid Glass / translucent material style, orange accent `#F97316`, SF Pro typography

## Key Design Decisions from Specs

- Separate UI, state, domain logic, networking, persistence, and provider integrations into distinct layers
- Feature-based file organization, not giant shared folders
- Business logic must not live inside SwiftUI views — keep it testable
- The iOS client must NOT call privileged AI or material-sourcing APIs directly; all AI calls go through the backend
- Free starter credits (3 AI generations, 3 quote exports) are backend-managed, not App Store trials
- The 7-day free trial is an App Store introductory offer on the monthly subscription
- Subscription state uses an enum with 8 states (`FREE`, `TRIAL_ACTIVE`, `PRO_ACTIVE`, `GRACE_PERIOD`, `BILLING_RETRY`, `CANCELED_ACTIVE`, `EXPIRED`, `REVOKED`) — never collapse to a single boolean
- All backend API responses use a consistent `{ ok, data/error, meta }` envelope
- Shared DTOs live in `packages/types` (TypeScript), mirrored as Swift structs on iOS

## Project Specs

Detailed product, API, monetization, and subscription specs are in `project-specs/`:
- `spec.md` — Full product spec (screens, flows, architecture, visual design)
- `more-spec.md` — API contracts, DTOs, backend service boundaries, middleware rules
- `monitization-spec.md` — Paywall, usage gating, StoreKit 2 subscription implementation
- `subscription-flow.md` — Subscription states, backend schema, purchase/reconciliation flows
