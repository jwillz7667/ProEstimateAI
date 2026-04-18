# ProEstimate AI

**Photo-to-proposal in minutes — an AI-native estimating and invoicing platform for contractors.**

ProEstimate AI turns a job-site photo into a fully costed estimate, branded proposal, and billable invoice — in the time it used to take to open a spreadsheet. Contractors upload photos of the space, the app generates a realistic AI remodel preview, auto-suggests materials and labor with quality tiers, and produces a sendable estimate. Approved estimates become invoices with a single tap.

> **Status:** Production. Shipping on the App Store. iOS 26.4+. Backend on Railway. Web in development.

---

## Contents

- [Overview](#overview)
- [Key capabilities](#key-capabilities)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [Environment configuration](#environment-configuration)
- [Development](#development)
- [Deployment](#deployment)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

---

## Overview

The core product loop:

```
Photo upload  ->  AI remodel preview  ->  Material & labor suggestions
                                                     |
                                                     v
                      Estimate  ->  Proposal (shareable)  ->  Invoice
```

Three platform targets:

| Target | Status | Stack |
| :----- | :----- | :---- |
| iOS app | Shipping | SwiftUI, SwiftData, StoreKit 2, Swift 6 concurrency |
| Backend API | Shipping | Node.js + TypeScript + Express + Prisma + PostgreSQL |
| Marketing site | Development | Next.js 15, React 19, Tailwind 4, Three.js |

## Key capabilities

- **On-device photo capture** with cloud AI rendering of before/after remodel previews via PiAPI (Nano Banana Pro/2) with a Google GenAI (Gemini 3.1 Flash Image) fallback.
- **Auto-generated line items** for materials, labor, and other costs, with Standard / Premium / Luxury quality tiers driving both imagery and pricing.
- **Structured estimate editor** with grouped line items, per-item markup, taxation, discounts, and DIY / Professional toggle.
- **Proposal generator** with a public shareable client-approval link.
- **Invoice creation** from approved estimates, including partial-payment tracking and overdue banners.
- **StoreKit 2 subscriptions** with a 7-day introductory trial, atomic free-tier credits, and server-side entitlement enforcement.
- **Bilingual UI** (English + Spanish) via native string catalogs.
- **Apple Sign In** plus email/password authentication with refresh-token rotation and reuse detection.
- **Apple Liquid Glass** design language with a dark-first palette and an `#FF9230` brand accent.

## Architecture

```
+---------------------------------------------------------------+
|  iOS App (SwiftUI, @Observable, Swift 6)                     |
|                                                               |
|  Views -> ViewModels -> Services -> APIClient -> URLSession   |
|                                         |                     |
|                                         v                     |
|              APIEndpoint enum (single source of truth)        |
|   JWT access/refresh, auto-retry on 401, PaywallError on 402  |
+---------------------------+-----------------------------------+
                            |  HTTPS JSON (snake_case)
                            v
+---------------------------------------------------------------+
|  Backend API (Express + TypeScript)                          |
|                                                               |
|  Router -> validate(Zod) -> Controller -> Service -> Prisma   |
|  sendSuccess / sendError envelope; AppError hierarchy         |
|  Rate limits, request IDs, Redis-backed counters              |
+---------------------------+-----------------------------------+
                            |
                            v
+---------------------------------------------------------------+
|  PostgreSQL (Railway)                                         |
|  Core domain + Commerce + Auth + Config tables                |
+---------------------------------------------------------------+
```

Additional notes:

- Every HTTP response follows a strict envelope: `{ ok, data, meta }` for success, `{ ok: false, error }` for errors. Errors carry a `code`, `message`, and optional `field_errors` / `paywall` payload.
- Cursor-based pagination everywhere. No offset pagination.
- Refresh tokens are rotated on every use; detected reuse revokes all sessions for the user.
- Images are stored as base64 in PostgreSQL text columns and served with immutable cache headers.

## Tech stack

**iOS**
- Swift 6.x with `SWIFT_APPROACHABLE_CONCURRENCY` and `MainActor` default isolation
- SwiftUI + `@Observable` (no Combine, no `ObservableObject`)
- SwiftData for offline-cached projects, estimates, and clients
- StoreKit 2 for subscriptions with `appAccountToken` correlation
- Xcode `fileSystemSynchronizedGroups` — never hand-edit `pbxproj`

**Backend**
- Node.js 20+, TypeScript (strict mode)
- Express 4, express-rate-limit, compression
- Prisma ORM + PostgreSQL
- Zod for runtime validation at every API boundary
- `jose` + `jsonwebtoken` for JWT signing/verification
- `pino` structured logging with pino-http
- `ioredis` + `rate-limit-redis` for distributed rate limits
- Resend for transactional email

**AI providers**
- PiAPI (Nano Banana Pro/2) — primary image generation provider
- Google GenAI (Gemini 3.1 Flash Image) — fallback image provider
- Gemini 2.5 Flash — material and labor suggestion generation

**Infrastructure**
- Railway (backend + managed PostgreSQL + Redis)
- Vercel (web)
- GitHub Actions (CI)

## Repository layout

```
.
+-- ProEstimate AI/              # iOS application sources
|   +-- App/                     # Entry point, router, global state
|   +-- Core/                    # Models, networking, persistence, utilities
|   +-- DesignSystem/            # Tokens, components, view extensions
|   +-- Features/                # Feature modules (auth, projects, estimates, invoices, ...)
|   +-- Resources/               # Asset catalog, string catalogs, Info.plist
+-- ProEstimate AI.xcodeproj/    # Xcode project
+-- backend/                     # Node.js + Express + Prisma API
|   +-- prisma/                  # Schema + migrations + seed
|   +-- src/
|   |   +-- app.ts               # Express app composition
|   |   +-- index.ts             # Server entry point
|   |   +-- lib/                 # errors, envelope, jwt, hash, pagination...
|   |   +-- middleware/          # auth, validate, requestId, rateLimit
|   |   +-- modules/             # Feature modules (routes/controller/service/dto/validators)
|   +-- Dockerfile
|   +-- railway.toml
+-- web/                         # Next.js marketing site (in development)
+-- .github/                     # CI, issue/PR templates, CODEOWNERS
+-- .editorconfig
+-- .gitignore
+-- .nvmrc
+-- CHANGELOG.md
+-- CONTRIBUTING.md
+-- LICENSE
+-- README.md
+-- SECURITY.md
```

## Getting started

### Prerequisites

- macOS with Xcode 26.4+ (for iOS work)
- Node.js 20+ (`nvm use` picks the pinned version from `.nvmrc`)
- PostgreSQL 15+ (local or Docker)
- Optional: Railway CLI, `gh` CLI

### iOS

```bash
open "ProEstimate AI.xcodeproj"
```

Bundle identifier: `Res.ProEstimate-AI`. Deployment target: iOS 26.4.

Headless build:

```bash
xcodebuild \
  -project "ProEstimate AI.xcodeproj" \
  -scheme "ProEstimate AI" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

### Backend

```bash
cd backend
cp .env.example .env               # fill in DATABASE_URL, JWT secrets, AI keys
npm ci
npx prisma generate
npx prisma migrate dev
npm run dev                        # http://localhost:3000
```

Useful scripts:

| Command | Purpose |
| :------ | :------ |
| `npm run dev` | Nodemon dev server with hot reload |
| `npm run build` | Compile TypeScript to `dist/` |
| `npm start` | Run compiled server |
| `npm run lint` | Lint `src/` |
| `npm run prisma:studio` | Visual DB browser |
| `npm run prisma:migrate` | Apply new local migration |
| `npm run prisma:seed` | Seed local database |

### Web

```bash
cd web
npm ci
npm run dev                        # http://localhost:3000
```

## Environment configuration

Backend environment variables (see `backend/.env.example`):

| Name | Required | Notes |
| :--- | :------- | :---- |
| `DATABASE_URL` | yes | PostgreSQL connection string |
| `JWT_SECRET` | yes | >= 32 characters, access token signing |
| `JWT_REFRESH_SECRET` | yes | >= 32 characters, refresh token signing |
| `PIAPI_API_KEY` | one of | PiAPI key for primary image generation |
| `GOOGLE_AI_API_KEY` | one of | Google GenAI key for fallback / materials |
| `GOOGLE_PLACES_API_KEY` | no | Address autocomplete |
| `REDIS_URL` | recommended | Distributed rate limiting; falls back to in-memory |
| `RESEND_API_KEY` | no | Transactional email |
| `NODE_ENV` | no | `development` / `production` |

At least one of `PIAPI_API_KEY` or `GOOGLE_AI_API_KEY` must be set.

## Development

### iOS conventions

- `@Observable` for all stateful classes. Never `ObservableObject` or `@Published`.
- Protocol-first services: `*ServiceProtocol: Sendable` with `Live*Service` and `Mock*Service` implementations.
- Default-parameter dependency injection. No global container.
- Business logic lives in ViewModels. Views are declarative layout only.
- Boolean names read as questions: `isLoading`, `hasCompleted`, `canGenerate`.
- Design tokens only — never hardcode colors, fonts, or spacing.

### Backend conventions

- Strict TypeScript. No `any`, no unsafe casts.
- Zod at every API boundary via `validate(schema, 'body' | 'query' | 'params')`.
- Module layering: `route -> controller -> service -> dto`. Never skip layers.
- Throw typed `AppError` subclasses, never raw `Error`.
- Always use `sendSuccess(res, data, meta)` or let the error handler format the envelope.
- Prisma transactions for any multi-table write that must be atomic.
- snake_case on the wire; camelCase inside TypeScript.

### Cross-layer contract

Changing an API endpoint touches five files in lockstep:

1. Backend: `route` + `validator` + `controller` + `service` + `dto`
2. iOS `APIEndpoint` enum case
3. iOS Decodable model matching the DTO shape
4. iOS service protocol method + Live implementation
5. iOS ViewModel consuming the service

A change that ships fewer than five updates is almost certainly incomplete.

## Deployment

### Backend (Railway)

```bash
cd backend
railway up --detach
railway variables --set "KEY=value"
railway logs
```

The Docker image runs `prisma migrate deploy && node dist/index.js` on boot, so pending migrations apply automatically.

Health endpoint: `GET /health`.

### Web (Vercel)

The `web/` directory deploys to Vercel via the normal git integration. Build command: `next build`.

### iOS (App Store)

Handled through Xcode Cloud or `xcodebuild -exportArchive` into App Store Connect. TestFlight is the recommended pre-release channel.

## Contributing

This is a proprietary codebase. Contributions are restricted to authorized team members. Engineering standards, branching strategy, commit conventions, and pull-request process are documented in [CONTRIBUTING.md](./CONTRIBUTING.md).

## Security

Do not file public issues for security concerns. Responsible-disclosure instructions are in [SECURITY.md](./SECURITY.md).

## License

Copyright (c) 2026 ProEstimate AI. All Rights Reserved.

This software is proprietary. Unauthorized copying, modification, distribution, or use of this software or any portion of it, via any medium, is strictly prohibited. See [LICENSE](./LICENSE) for the full terms.
