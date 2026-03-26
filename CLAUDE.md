# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ProEstimate AI is an iOS-first AI estimating and invoicing platform for contractors. Core workflow: **Photo → AI remodel preview (Nano Banana 2) → material suggestions → estimate → proposal → invoice**.

Three platform targets:
- **iOS app** — SwiftUI native (primary product), in `ProEstimate AI/`
- **Backend API** — Node.js + TypeScript + Express + Prisma + PostgreSQL, in `backend/`, deployed on Railway
- **Web app** — Next.js on Vercel (admin, sharing, client-view) — not yet built

## Build & Run

### iOS

Xcode project (not SPM). Uses `fileSystemSynchronizedGroups` — files are auto-discovered from the filesystem, no manual pbxproj edits needed.

```bash
# Open in Xcode
open "ProEstimate AI.xcodeproj"

# CLI build (Xcode beta required)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project "ProEstimate AI.xcodeproj" \
  -scheme "ProEstimate AI" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

- Bundle ID: `Res.ProEstimate-AI`
- Deployment Target: iOS 26.4, Xcode 26.4+
- Swift 5.0 with `SWIFT_APPROACHABLE_CONCURRENCY` and `MainActor` default isolation

### Backend

```bash
cd backend
npm install
npx prisma generate          # Generate Prisma client
npx prisma migrate dev       # Run migrations (local)
npm run dev                   # Start dev server (nodemon)
npm run build                 # TypeScript compile
npm run lint                  # ESLint
npx prisma studio             # Visual DB browser
```

Required env vars in `backend/.env`: `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET`, `GOOGLE_AI_API_KEY`. See `.env.example`.

### Deploy Backend to Railway

```bash
cd backend
railway up --detach           # Deploy (may need retry on transient connection errors)
railway variables --set "KEY=value"  # Set env vars
railway logs                  # View logs
```

Deployment uses `Dockerfile` (multi-stage, node:20-alpine). Entrypoint runs `prisma migrate deploy` then starts the server. Health check at `/health`.

## iOS Architecture

### Layering

```
App/              → Entry point (ProEstimate_AIApp), AppRouter, AppState, AppConstants, PaywallPresenter
Core/
  Models/         → Domain structs (Project, Estimate, Invoice, Client, etc.) + Commerce models
  Networking/     → APIClient (singleton), APIEndpoint enum, response envelope, TokenStore
  Persistence/    → SwiftData cached models (CachedProject, CachedEstimate, CachedClient)
  Utilities/      → PDFGenerator, ActivityViewRepresentable
DesignSystem/
  Tokens/         → ColorTokens, TypographyTokens, SpacingTokens, RadiusTokens, ShadowTokens
  Components/     → GlassCard, PrimaryCTAButton, StatusBadge, MetricCard, CurrencyText, etc.
Features/         → Feature modules (see below)
Resources/        → Localizable.xcstrings, Info.plist
```

### Feature Module Pattern

Each feature in `Features/` follows: `Models/`, `Services/`, `ViewModels/`, `Views/`. Business logic lives in ViewModels, never in Views.

### Service Layer

Every feature service has a protocol (`*ServiceProtocol: Sendable`) with both a `Mock*Service` (fake data, delays) and `Live*Service` (delegates to `APIClient.shared`). Services: Auth, Client, Project, Generation, Estimate, Invoice, Proposal, Settings. Default initializers use `Live*Service()`. `AppConstants.useMockData` is `false` — app talks to real backend.

### Navigation

`AppRouter` (Observable) manages a `NavigationPath`. Routes defined in `AppDestination` enum. Views access router via `@Environment(AppRouter.self)`.

### Commerce / Monetization

- `EntitlementStore` — polls backend for subscription state (8-state enum, not boolean)
- `UsageMeterStore` — tracks free credit consumption (3 AI generations, 3 quote exports)
- `FeatureGateCoordinator` — guards features, returns `.allowed` or `.blocked(PaywallDecision)`
- `PaywallPresenter` — centralized sheet coordinator for paywall display
- StoreKit 2 subscriptions, group `proestimate_pro` (monthly + annual)

### Networking Contract

- All requests go through `APIClient` → `APIEndpoint` enum → JSON with snake_case encoding
- Responses wrapped in `{ ok, data/error, meta }` envelope, decoded via `APISuccessEnvelope<T>`
- 401 triggers automatic token refresh + retry; failure calls `onUnauthorized` callback
- Error responses may include `paywall` object (402) for upgrade prompts

## Backend Architecture

### Module Pattern

Each module in `src/modules/` has: `*.routes.ts`, `*.controller.ts`, `*.service.ts`, `*.dto.ts`, `*.validators.ts` (Zod schemas).

Flow: Route → Controller (HTTP layer) → Service (business logic + Prisma) → DTO (response shaping)

All routes mounted under `/v1` prefix. Auth routes are unprotected; all others require `requireAuth` middleware.

### Key Modules

- **generations** — Async AI image generation pipeline: create (QUEUED) → process in background (PROCESSING) → store result (COMPLETED/FAILED). Uses Nano Banana 2 (`gemini-3.1-flash-image-preview` via `@google/genai`). Images stored as base64 in PostgreSQL `Text` column, served as binary at `GET /v1/generations/:id/preview`.
- **estimates** — CRUD + line items (materials/labor/other categories), version tracking
- **invoices** — CRUD + create-from-estimate, payment tracking, send/mark-paid
- **proposals** — CRUD + share tokens for public client links, send to client
- **commerce** — Plans, subscription products, entitlements, usage buckets/events

### Response Envelope

Success: `{ ok: true, data: T, meta: { request_id, timestamp, pagination? } }`
Error: `{ ok: false, error: { code, message, field_errors?, retryable?, paywall? }, meta }`

Error classes in `src/lib/errors.ts`: `AppError`, `NotFoundError`, `ValidationError`, `AuthenticationError`, `PaywallError` (402).

### Data Model (Prisma)

Core entities: User → Company, Client, Project → AIGeneration → MaterialSuggestion, Estimate → EstimateLineItem, Proposal, Invoice → InvoiceLineItem. Commerce: Plan → SubscriptionProduct, UserEntitlement, SubscriptionEvent, UsageBucket, UsageEvent.

Schema at `backend/prisma/schema.prisma`.

## Key Design Decisions

- iOS client never calls AI APIs directly — all AI calls go through backend
- Free credits are backend-managed via UsageBucket (atomic consumption in Prisma transactions), not App Store trials
- The 7-day free trial is an App Store introductory offer on the monthly subscription
- Subscription state uses 8 states (`FREE`, `TRIAL_ACTIVE`, `PRO_ACTIVE`, `GRACE_PERIOD`, `BILLING_RETRY`, `CANCELED_ACTIVE`, `EXPIRED`, `REVOKED`)
- API base URL: `https://proestimate-api-production.up.railway.app/v1`
- Design: Apple Liquid Glass / translucent material, orange accent `#F97316`
- Localization: English + Spanish (string catalogs)

## Project Specs

Detailed specs in `project-specs/`:
- `spec.md` — Full product spec (screens, flows, architecture, visual design)
- `more-spec.md` — API contracts, DTOs, backend service boundaries
- `monitization-spec.md` — Paywall, usage gating, StoreKit 2 implementation
- `subscription-flow.md` — Subscription states, purchase/reconciliation flows
