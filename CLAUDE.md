# CLAUDE.md — ProEstimate AI

> **Read this entire document before every task.** It is your architectural source of truth for this codebase. Internalize the cross-layer wiring, data flows, and patterns described here so that every line of code you produce is structurally coherent with the existing system.

---

## Agent Collaboration Protocol

**Always spawn sub-agents for non-trivial work.** Before starting any task that touches more than one file or requires research, decompose it into parallel sub-agent tasks. This is mandatory, not optional.

- **Research before code**: Spawn an `Explore` agent to map affected files, trace call sites, and identify integration points before writing a single line.
- **Parallel feature work**: When a task spans iOS + backend, spawn separate agents for each layer. One agent handles Swift/SwiftUI changes, another handles TypeScript/Express/Prisma changes.
- **Validation after code**: After writing code, spawn a sub-agent to review the changes for correctness, type safety, and adherence to the patterns documented below.
- **Cross-layer consistency**: When adding/modifying an API endpoint, spawn agents in parallel: one for the backend route/controller/service/dto/validator, one for the iOS APIEndpoint case + service method + ViewModel integration.
- **Complex debugging**: Spawn one agent to trace the iOS call path and another to trace the backend request path. Compare results.

Sub-agents should receive complete context: file paths, class names, the specific pattern to follow, and what "done" looks like. Never delegate understanding — brief the agent with your synthesis of this document.

---

## Project Identity

ProEstimate AI is an iOS-native AI estimating and invoicing platform for contractors. The core product loop:

```
Photo Upload → AI Remodel Preview (Nano Banana 2) → Material/Labor Suggestions → Estimate → Proposal → Invoice
```

Three platform targets:
- **iOS app** — SwiftUI, `ProEstimate AI/` (primary product, shipping)
- **Backend API** — Node.js + TypeScript + Express + Prisma + PostgreSQL, `backend/`, Railway
- **Web app** — Next.js on Vercel (not yet built)

---

## Build & Run

### iOS

Xcode project with `fileSystemSynchronizedGroups` — files auto-discovered from filesystem, **never edit pbxproj manually**.

```bash
open "ProEstimate AI.xcodeproj"

# CLI build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project "ProEstimate AI.xcodeproj" \
  -scheme "ProEstimate AI" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

- Bundle ID: `Res.ProEstimate-AI`
- Deployment: iOS 26.4+, Xcode 26.4+
- Swift 5.0, `SWIFT_APPROACHABLE_CONCURRENCY`, `MainActor` default isolation

### Backend

```bash
cd backend
npm install && npx prisma generate
npx prisma migrate dev        # Local migrations
npm run dev                    # Nodemon dev server
npm run build                  # tsc compile
npm run lint                   # ESLint
npx prisma studio              # Visual DB browser
```

Required env: `DATABASE_URL`, `JWT_SECRET` (>=32 chars), `JWT_REFRESH_SECRET` (>=32 chars). At least one of `PIAPI_API_KEY` or `GOOGLE_AI_API_KEY` for image generation. Optional: `GOOGLE_PLACES_API_KEY`.

### Deploy

```bash
cd backend && railway up --detach    # Railway deploy
railway variables --set "KEY=value"  # Set env vars
railway logs                         # Tail logs
```

Dockerfile: multi-stage node:20-alpine. Entrypoint: `prisma migrate deploy && node dist/index.js`. Health: `/health`.

---

## System Architecture — Cross-Layer Wiring

This is how the three layers connect. Internalize this so every change maintains structural coherence.

```
┌─────────────────────────────────────────────────────────────────────┐
│  iOS App (SwiftUI)                                                  │
│                                                                     │
│  ProEstimate_AIApp (@main)                                          │
│    ├── @State appState: AppState          ← auth, user, company     │
│    ├── @State appRouter: AppRouter        ← per-tab NavigationPath  │
│    ├── @State entitlementStore            ← subscription snapshot   │
│    ├── @State usageMeterStore             ← free credit tracking    │
│    ├── @State featureGateCoordinator      ← feature access guards   │
│    └── @State paywallPresenter            ← paywall sheet trigger   │
│                                                                     │
│  Views → @Environment(ServiceType.self) → ViewModels → Services     │
│    │                                                                │
│    └── Live*Service → APIClient.shared → URLSession                 │
│              │                                                      │
│              ├── APIEndpoint enum (50+ cases) → URLRequest           │
│              ├── snake_case JSON encoding/decoding                   │
│              ├── APISuccessEnvelope<T> / APIErrorEnvelope            │
│              ├── 401 → auto token refresh → retry once               │
│              ├── 402 → PaywallError with PaywallDecision             │
│              └── TokenStore (Keychain-backed, singleton)             │
│                                                                     │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ HTTPS JSON (snake_case)
                            │ Authorization: Bearer <jwt>
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Backend API (Express + TypeScript)                                 │
│                                                                     │
│  Middleware Chain:                                                   │
│    cors → json(10mb) → requestId → globalRateLimit(100/min)         │
│    → requireAuth (JWT verify → req.userId, req.companyId)           │
│                                                                     │
│  Route → Controller (HTTP) → Service (business logic) → Prisma     │
│    │                                                                │
│    ├── Response: sendSuccess<T>(res, data, meta)                    │
│    │   { ok: true, data: T, meta: { request_id, timestamp, pagination } }
│    │                                                                │
│    ├── Error: sendError(res, statusCode, errorObj)                  │
│    │   { ok: false, error: { code, message, field_errors, paywall } }
│    │                                                                │
│    └── Error Classes: AppError → NotFoundError, ValidationError,    │
│        AuthenticationError, AuthorizationError, PaywallError(402),  │
│        ConflictError                                                │
│                                                                     │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ Prisma ORM
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  PostgreSQL (Railway)                                               │
│                                                                     │
│  Core: User → Company, Client, Project → Asset, AIGeneration →     │
│        MaterialSuggestion, Estimate → EstimateLineItem,            │
│        Proposal, Invoice → InvoiceLineItem, ActivityLogEntry       │
│                                                                     │
│  Commerce: Plan → SubscriptionProduct, UserEntitlement,            │
│           SubscriptionEvent, UsageBucket, UsageEvent,              │
│           PurchaseAttempt, PaywallImpression                       │
│                                                                     │
│  Auth: RefreshToken (rotated, reuse detection)                      │
│  Config: PricingProfile → LaborRateRule                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## iOS Architecture — Deep Reference

### Layer Structure

```
ProEstimate AI/
  App/                   → ProEstimate_AIApp, AppState, AppRouter, AppConstants, MainTabView, PaywallPresenter
  Core/
    Models/              → Domain structs (Project, Client, Estimate, Invoice, Proposal, User, Company,
                           AIGeneration, Asset, MaterialSuggestion, ActivityLogEntry, LaborRateRule, PricingProfile)
    Models/Commerce/     → EntitlementSnapshot, SubscriptionState, PaywallDecision, StoreProductModel
    Networking/          → APIClient (protocol + impl), APIEndpoint (50+ cases), APIError, 
                           APIResponseEnvelope (success/error), TokenStore (Keychain), MockAPIClient
    Persistence/         → SwiftData: CachedProject, CachedEstimate, CachedClient
    Utilities/           → PDFGenerator, ActivityViewRepresentable
  DesignSystem/
    Tokens/              → ColorTokens (#F97316 primary), TypographyTokens, SpacingTokens, RadiusTokens, ShadowTokens
    Components/          → GlassCard, PrimaryCTAButton, SecondaryButton, StatusBadge, MetricCard,
                           CurrencyText, SearchBar, AvatarView, LoadingStateView, RetryStateView,
                           EmptyStateView, SectionHeaderView
    Extensions/          → Color+Hex, Date+Formatting, View+GlassEffect (.glassCard modifier)
  Features/
    Auth/                → Login, SignUp, ForgotPassword, AppleSignIn
    Dashboard/           → Revenue metrics, recent projects, quick actions, subscription card
    Projects/
      List/              → Project list with filtering
      Creation/          → 6-step wizard (type → client → photos → prompt → details → review)
      Detail/            → Overview, images, AI preview, materials, estimates, activity
    Estimates/           → Editor (grouped line items), list, totals, PDF export
    Invoices/            → List, creation sheet, preview, totals
    Proposals/           → Preview (hero, scope, estimate table), send flow
    Clients/             → List, detail, form (CRUD)
    Commerce/            → Paywall host, plan selector, feature comparison, usage meter, purchase flow
    Settings/            → Company branding, tax, numbering, pricing profiles, language
    QuickGenerate/       → Simplified generation without full project creation
  Resources/             → Localizable.xcstrings, Info.plist
```

### Feature Module Pattern — How to Add Code

Every feature follows this structure. When adding to a feature, place files accordingly:

```
Features/{FeatureName}/
  Models/         → Feature-specific request/response DTOs
  Services/       → Protocol (*ServiceProtocol: Sendable) + LiveService + MockService
  ViewModels/     → @Observable classes, own business logic, never in Views
  Views/          → SwiftUI views, compose from DesignSystem components
  Components/     → Feature-specific reusable subviews
```

### Service Layer — Dependency Injection Pattern

Every ViewModel receives services via default parameters. No global DI container.

```swift
// Service protocol + implementations
protocol ProjectServiceProtocol: Sendable {
    func listProjects() async throws -> [Project]
    func getProject(_ id: String) async throws -> Project
    // ...
}

final class LiveProjectService: ProjectServiceProtocol {
    private let apiClient: APIClientProtocol
    init(apiClient: APIClientProtocol = APIClient.shared) { self.apiClient = apiClient }
    func listProjects() async throws -> [Project] {
        try await apiClient.request(.listProjects(cursor: nil))
    }
}

final class MockProjectService: ProjectServiceProtocol { /* fake data + delays */ }

// ViewModel with default injection
@Observable final class ProjectListViewModel {
    private let projectService: ProjectServiceProtocol
    private let clientService: ClientServiceProtocol
    
    init(
        projectService: ProjectServiceProtocol = LiveProjectService(),
        clientService: ClientServiceProtocol = LiveClientService()
    ) {
        self.projectService = projectService
        self.clientService = clientService
    }
}
```

### State Management — No Combine, Pure Observation

- **@Observable** for all state holders (ViewModels, stores, router)
- **@Environment(Type.self)** to access singletons injected at App level
- **@State** for local view state and for singleton creation in ProEstimate_AIApp
- **Per-tab NavigationPath** in AppRouter (dashboardPath, projectsPath, estimatesPath, invoicesPath, clientsPath, settingsPath)
- **No @Published, no ObservableObject, no Combine** — pure Swift Observation framework

### Navigation — AppRouter + AppDestination

```swift
enum AppDestination: Hashable {
    // Projects
    case projectDetail(id: String), projectCreation
    // Estimates
    case estimateEditor(id: String), estimateList(projectId: String)
    // Proposals
    case proposalPreview(id: String)
    // Invoices
    case invoiceDetail(id: String), invoicePreview(id: String)
    // Clients
    case clientDetail(id: String), clientForm(id: String?)
    // Settings
    case companyBranding, taxSettings, numberingSettings, pricingProfiles, languageSettings, subscriptionSettings
    // Commerce
    case paywall(placement: String)
}
```

Six tabs: Dashboard, Projects, Estimates, Invoices, Clients, Settings.

### Networking — APIClient + APIEndpoint

**APIEndpoint** is an enum with 50+ cases. Each case defines `path`, `method`, `requiresAuth`, `queryItems`, `body`. When adding a new endpoint, add a case here — this is the single source of truth for all HTTP requests.

**APIClient** handles:
- Building URLRequest from APIEndpoint
- snake_case JSON encoding (JSONEncoder) / decoding (custom decoder for JS fractional seconds)
- Auth header injection from TokenStore
- 401 auto-retry: refresh token once, retry request; on second 401 call `onUnauthorized`
- 402 PaywallError extraction with PaywallDecision payload
- Response unwrapping via `APISuccessEnvelope<T>` / `APIErrorEnvelope`

**TokenStore** — Keychain-backed singleton, `kSecAttrAccessibleAfterFirstUnlock` for background sync. Service name: `ai.proestimate.ios`.

### SwiftData Offline Cache

Three cached models with denormalized summary fields + full JSON payload:
- `CachedProject` (@Attribute(.unique) projectId)
- `CachedEstimate` (@Attribute(.unique) estimateId)
- `CachedClient` (@Attribute(.unique) clientId)

ModelContainer initialized in `ProEstimate_AIApp.init()`.

### Design System — Visual Language

**Apple Liquid Glass** — layered translucent materials, soft depth, rounded cards, frosted overlays.

| Token | Value |
|-------|-------|
| Primary orange | `#F97316` |
| Background (dark) | `#0B0B0C` |
| Surface (dark) | `#111214` |
| Success | `#22C55E` |
| Warning | `#F59E0B` |
| Error | `#EF4444` |
| Spacing scale | 4, 8, 12, 16, 20, 24, 32, 40, 48, 64 |

Typography: SF Pro. Money amounts use `.rounded.monospaced` variants (moneyLarge/Medium/Small/Caption). Glass effect via `.glassCard(cornerRadius:)` modifier.

---

## Backend Architecture — Deep Reference

### Module Structure

Every module in `src/modules/` follows:

```
src/modules/{name}/
  {name}.routes.ts       → Express router with route definitions
  {name}.controller.ts   → Request handlers (extract params, call service, send response)
  {name}.service.ts      → Business logic (Prisma queries, transactions, validation)
  {name}.dto.ts          → Response shaping functions (Prisma model → API response)
  {name}.validators.ts   → Zod schemas for request validation
```

Flow: `Route → validate(zodSchema) → Controller → Service → Prisma → DTO → sendSuccess/sendError`

### Route Mounting (app.ts)

All routes under `/v1` prefix. Public (no auth): `/health`, `GET /v1/generations/:id/preview`, `GET /v1/assets/:id/image`.

```
/v1/auth              → signup, login, apple-signin, refresh, logout
/v1/users             → getMe, updateMe
/v1/companies         → getMe, updateMe
/v1/clients           → CRUD
/v1/projects          → CRUD + nested /assets, /generations, /activity
/v1/assets            → upload (multipart), serve image
/v1/generations       → create (async), get (poll), preview (public binary)
/v1/materials         → update selection
/v1/estimates         → CRUD + nested /line-items
/v1/estimate-line-items → CRUD
/v1/proposals         → CRUD + send
/v1/invoices          → CRUD + nested /line-items + send
/v1/invoice-line-items → CRUD
/v1/pricing-profiles  → CRUD + nested labor rates
/v1/labor-rates       → CRUD
/v1/activity          → list by project
/v1/commerce          → products, entitlement, purchase-attempt, sync, restore
/v1/usage             → get summary, check (atomic consume)
/v1/dashboard         → stats
/v1/contractors       → search (future)
```

### Middleware Chain

1. `cors` — configured origins, credentials: true
2. `express.json({ limit: '10mb' })` — for base64 image uploads
3. `requestIdMiddleware` — UUID v4 on every request/response
4. `globalRateLimit` — 100 req/min/IP
5. `authRateLimit` — 10 req/min/IP (auth routes only)
6. `requireAuth` — JWT verification, sets `req.userId` + `req.companyId`
7. `validate(zodSchema, source)` — Zod validation on body/query/params
8. `errorHandler` — catches AppError subclasses, formats envelope

### Shared Libraries (`src/lib/`)

| File | Purpose |
|------|---------|
| `errors.ts` | AppError hierarchy (NotFound, Validation, Auth, Paywall, Conflict) |
| `jwt.ts` | signAccessToken (15m), signRefreshToken (30d), verify functions |
| `envelope.ts` | sendSuccess, sendError — format response envelope |
| `hash.ts` | bcrypt hash/verify (SALT_ROUNDS=12) |
| `id.ts` | CUID2 generation via @paralleldrive/cuid2 |
| `pagination.ts` | Cursor-based pagination (default 25, max 100) |
| `params.ts` | Express param normalization |
| `apple-auth.ts` | Apple JWKS identity token verification |
| `image-gen.ts` | Image generation orchestrator — provider selection + fallback (PiAPI → Google GenAI) |
| `piapi-image-gen.ts` | PiAPI Nano Banana Pro/2 provider (create task → poll → download → base64) |
| `material-gen.ts` | Gemini text (gemini-2.5-flash-preview-05-20) material/labor estimation |

### AI Generation Pipeline — Complete Trace

```
1. iOS: POST /v1/projects/:projectId/generations { prompt, materials? }
2. Backend validates ownership, checks entitlement:
   ├── Pro user: proceed directly
   └── Free user: atomic UsageBucket decrement in Prisma transaction
       └── If remaining <= 0: throw PaywallError(402, GENERATION_LIMIT_HIT)
3. Create AIGeneration record (status: QUEUED), log activity
4. Return 201 immediately (fire-and-forget async processing)
5. processGeneration() background:
   ├── Update status → PROCESSING
   ├── Fetch most recent ORIGINAL asset with imageData + public URL
   ├── Call generatePreviewImage(prompt, context, referencePhoto, referenceAssetUrl)
   │   ├── PROVIDER 1 (primary): PiAPI Nano Banana Pro (if PIAPI_API_KEY set)
   │   │   ├── POST https://api.piapi.ai/api/v1/task (nano-banana-pro)
   │   │   ├── Poll GET /task/{id} every 3s until completed (max 2 min)
   │   │   ├── Download image from CDN URL → convert to base64
   │   │   ├── Internal fallback: nano-banana-2 if pro fails
   │   │   └── Reference photos via public asset URL (PiAPI needs URLs, not base64)
   │   └── PROVIDER 2 (fallback): Google GenAI direct (if GOOGLE_AI_API_KEY set)
   │       └── Gemini 3.1 Flash Image: temp=1, topP=0.95, safety OFF, 2K
   │           Reference photos via base64 inline data
   ├── Store base64 image + mimeType in AIGeneration record
   ├── Update status → COMPLETED, set previewUrl/thumbnailUrl
   └── Fire generateAndStoreMaterials() (non-critical background):
       ├── Gemini text model → material suggestions
       ├── Gemini text model → labor estimates
       └── Store all as MaterialSuggestion records
6. iOS polls GET /v1/generations/:id until status = "completed"
7. iOS fetches image from GET /v1/generations/:id/preview (public, cached immutably)
```

**Image Generation Provider Configuration:**

| Env Var | Provider | Role |
|---------|----------|------|
| `PIAPI_API_KEY` | PiAPI Nano Banana Pro/2 | Primary — async task-based, CDN image delivery |
| `GOOGLE_AI_API_KEY` | Google GenAI (Gemini 3.1 Flash Image) | Fallback — direct API, inline base64 |

At least one must be set. If both are set, PiAPI is tried first. If PiAPI fails entirely, Google GenAI is used. Within PiAPI, `nano-banana-pro` is tried first with `nano-banana-2` as internal fallback.

### Auth Flow — JWT + Refresh Token Rotation

```
Signup/Login → { access_token (15m), refresh_token (30d) }
  └── Stored in Keychain via TokenStore
  
Request fails 401 → APIClient auto-attempts refresh:
  POST /v1/auth/refresh { refresh_token }
  └── Backend: verify JWT, find token in DB, detect reuse attack, 
      delete old token, issue new pair, store new refresh token
  └── If refresh succeeds: retry original request with new access_token
  └── If refresh fails: call onUnauthorized → sign out
```

**Token reuse detection**: If a refresh token is not found in DB (already rotated), all user tokens are revoked (stolen token scenario).

### Prisma Schema — Key Enums

```
ProjectType:    KITCHEN, BATHROOM, FLOORING, ROOFING, PAINTING, SIDING, ROOM_REMODEL, EXTERIOR, CUSTOM
ProjectStatus:  DRAFT → PHOTOS_UPLOADED → GENERATING → GENERATION_COMPLETE → ESTIMATE_CREATED → 
                PROPOSAL_SENT → APPROVED/DECLINED → INVOICED → COMPLETED → ARCHIVED
QualityTier:    STANDARD, PREMIUM, LUXURY
GenerationStatus: QUEUED → PROCESSING → COMPLETED/FAILED
EstimateStatus: DRAFT → SENT → APPROVED/DECLINED/EXPIRED
ProposalStatus: DRAFT → SENT → VIEWED → APPROVED/DECLINED/EXPIRED
InvoiceStatus:  DRAFT → SENT → VIEWED → PARTIALLY_PAID/PAID/OVERDUE/VOID
LineItemCategory: MATERIALS, LABOR, OTHER
```

---

## Commerce & Monetization — Complete System

This is the most complex subsystem. Every feature gate, paywall trigger, and subscription state must be consistent across iOS and backend.

### Subscription State Machine (8 states)

```
FREE ──────────→ TRIAL_ACTIVE ──→ PRO_ACTIVE ←──── BILLING_RETRY
                      │                │                   ↑
                      │                ├──→ GRACE_PERIOD ──┘
                      │                │         │
                      │                ├──→ CANCELED_ACTIVE
                      ▼                │         │
                   EXPIRED ←───────────┴─────────┘
                      ↑
                   REVOKED (from any active state)
```

### Free Tier Credits

| Metric | Included | Reset |
|--------|----------|-------|
| AI_GENERATION | 3 | NEVER |
| QUOTE_EXPORT | 3 | NEVER |

Credits consumed atomically server-side. Client optimistically decrements then confirms with backend. PDFs watermarked ("Created with ProEstimate AI").

### Feature Gate Matrix

| Feature | Free | Trial/Pro |
|---------|------|-----------|
| AI preview generation | 3 credits | Unlimited |
| Quote/proposal export | 3 credits (watermarked) | Unlimited (branded) |
| Remove watermark | No | Yes |
| Branded PDFs | No | Yes |
| Invoice creation | No | Yes |
| Client approval share link | No | Yes |
| Material links in export | No | Yes |
| High-res preview | No | Yes |

### iOS Commerce Wiring

```
ProEstimate_AIApp.bootstrap():
  1. CommerceAPIClient() → commerceAPI
  2. entitlementStore.configure(commerceAPI)
  3. usageMeterStore.configure(commerceAPI, entitlementStore)
  4. featureGateCoordinator.configure(entitlementStore, usageMeterStore)
  5. await entitlementStore.refresh()     ← GET /v1/commerce/entitlement
  6. await usageMeterStore.refresh()      ← syncs from snapshot
  7. await featureGateCoordinator.loadProducts() ← GET /v1/commerce/products

Feature Guard Flow (e.g., generate preview):
  1. ViewModel calls featureGateCoordinator.guardGeneratePreview()
  2. Returns .allowed or .blocked(PaywallDecision)
  3. If blocked: paywallPresenter.present(decision) → PaywallHostView sheet
  4. If allowed + free: usageMeterStore.consumeGeneration() → optimistic decrement → backend confirm

Purchase Flow:
  1. PaywallHostViewModel.purchase()
  2. POST /v1/commerce/purchase-attempt → appAccountToken
  3. StoreKit 2: Product.purchase(options: appAccountToken)
  4. POST /v1/commerce/transactions/sync → EntitlementSnapshot
  5. entitlementStore.refresh() + usageMeterStore.refresh()
  6. UI re-renders with Pro access
```

### Paywall Placements

`ONBOARDING_SOFT_GATE`, `POST_FIRST_GENERATION`, `POST_FIRST_QUOTE_EXPORT`, `GENERATION_LIMIT_HIT`, `QUOTE_LIMIT_HIT`, `INVOICE_LOCKED`, `BRANDING_LOCKED`, `APPROVAL_SHARE_LOCKED`, `WATERMARK_REMOVAL_LOCKED`, `SETTINGS_UPGRADE`

### Backend Entitlement Guards

Generation creation and invoice creation are entitlement-gated in their respective service files. Generation checks `CAN_GENERATE_PREVIEW` (true for Pro, credit-gated for Free). Invoice checks `CAN_CREATE_INVOICE` + active subscription status. Both throw `PaywallError(402)` with a `PaywallDecision` payload when denied.

---

## Code Patterns — What the AI Must Follow

### Swift/iOS Conventions

- **@Observable** for all stateful classes — never `ObservableObject` or `@Published`
- **Protocol-first services**: `*ServiceProtocol: Sendable` + `Live*Service` + `Mock*Service`
- **Default parameter injection**: `init(service: MyServiceProtocol = LiveMyService())`
- **Guard early**: `guard let` for optionals, `guard` for preconditions
- **Boolean naming**: `isLoading`, `hasCompleted`, `shouldRetry`, `canGenerate`
- **Business logic in ViewModels**, never in Views. Views are declarative layout only.
- **DesignSystem components**: Use `GlassCard`, `PrimaryCTAButton`, `StatusBadge`, `CurrencyText`, spacing/color/typography tokens. Never hardcode colors or fonts.
- **@Environment** for singletons: `@Environment(AppRouter.self)`, `@Environment(EntitlementStore.self)`, etc.
- **Error enums**: Conform to `LocalizedError`, use `case` per error type
- **Extensions**: Group by protocol conformance

### TypeScript/Backend Conventions

- **Strict TypeScript** — no `any`, no unsafe `as` casts
- **Zod validation** at every API boundary via `validate(schema, 'body'|'query'|'params')` middleware
- **Module pattern**: routes → controller → service → dto. Never skip layers.
- **Error throwing**: Use specific `AppError` subclasses, never raw `throw new Error()`
- **Response envelope**: Always use `sendSuccess(res, data, meta)` or let `errorHandler` catch `AppError`
- **Prisma transactions**: Use for any multi-table write or atomicity requirement (usage consumption, number auto-increment, purchase sync)
- **DTOs**: Always transform Prisma models to DTOs before sending. Never leak Prisma types to API responses. Convert Decimal → Number, DateTime → ISO string, enums → lowercase.
- **snake_case** in all API responses. camelCase internally in TypeScript.

### Cross-Layer Contract

When modifying an API endpoint, ensure consistency across:

1. **Backend**: route + validator + controller + service + dto
2. **iOS APIEndpoint**: matching case with correct path, method, body, query
3. **iOS Model**: Decodable struct matching the DTO shape (snake_case coding keys)
4. **iOS Service**: protocol method + Live implementation calling APIClient
5. **iOS ViewModel**: method calling the service, updating @Observable state

### Naming Conventions

| Layer | Convention | Example |
|-------|-----------|---------|
| Prisma model | PascalCase | `EstimateLineItem` |
| API path | kebab-case | `/v1/estimate-line-items` |
| API response field | snake_case | `total_amount` |
| Swift model | PascalCase | `EstimateLineItem` |
| Swift property | camelCase | `totalAmount` |
| TS internal | camelCase | `totalAmount` |
| Endpoint enum | camelCase | `.listEstimateLineItems` |

---

## Key Design Decisions — Inviolable Rules

1. **iOS never calls AI APIs directly** — all AI goes through backend (PiAPI or Google GenAI)
2. **Backend is source of truth** for entitlements, credits, and feature access
3. **Free credits are server-managed** via UsageBucket atomic transactions, not App Store trials
4. **The 7-day trial is an App Store introductory offer** on the monthly subscription, separate from starter credits
5. **No mock data in production** — `AppConstants.useMockData` is `false`; Mock services exist only for testing/previews
6. **Images stored as base64 in PostgreSQL** Text columns, served as binary with immutable cache headers
7. **Cursor-based pagination** everywhere (never offset-based)
8. **Token rotation with reuse detection** — stolen refresh tokens trigger full revocation
9. **Design language**: Apple Liquid Glass, translucent materials, orange accent `#F97316`
10. **Localization**: English + Spanish via Localizable.xcstrings string catalogs

---

## Critical Data Flows — End-to-End Traces

### Project Lifecycle

```
Create Project (DRAFT) → Upload Assets (base64 stored) → Generate AI Preview (QUEUED → PROCESSING → COMPLETED)
→ Review Materials (auto-generated) → Create Estimate (auto-numbered EST-XXXX) → Add/Edit Line Items
→ Create Proposal (generates shareToken) → Send to Client → Client Approves/Declines
→ Create Invoice from Estimate (auto-numbered INV-XXXX, Pro-only) → Send → Track Payment
```

### Signup → First Generation

```
1. POST /v1/auth/signup → User + Company + UserEntitlement(FREE) + 2x UsageBucket(3 each)
2. iOS stores tokens in Keychain, sets AppState.isAuthenticated
3. bootstrap() hydrates EntitlementStore, UsageMeterStore, FeatureGateCoordinator
4. User creates project (6-step wizard) → POST /v1/projects
5. User uploads photo → POST /v1/assets (multipart, stored as base64)
6. User enters prompt → POST /v1/projects/:id/generations
7. Backend: entitlement check → UsageBucket atomic decrement → create generation(QUEUED)
8. Background: Nano Banana 2 generates image → store → COMPLETED
9. Background: Gemini generates materials + labor → store as MaterialSuggestions
10. iOS polls until completed → displays before/after
```

---

## Project Specs Reference

Detailed specs in `project-specs/`:
- `spec.md` — Full product spec (screens, flows, visual design)
- `more-spec.md` — API contracts, DTOs, backend service interfaces
- `monitization-spec.md` — Paywall strategy, usage gating, StoreKit 2, feature matrix
- `subscription-flow.md` — Subscription state machine, purchase/reconciliation flows

Consult these when implementing new features or when the CLAUDE.md summary isn't detailed enough for your task.
