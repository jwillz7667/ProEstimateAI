# ProEstimate AI — Complete Backend API Specification

## Table of Contents
1. [Infrastructure & Middleware Pipeline](#1-infrastructure--middleware-pipeline)
2. [Response Contract](#2-response-contract)
3. [Complete Endpoint Inventory (Current)](#3-complete-endpoint-inventory)
4. [iOS ↔ Backend Wiring Map](#4-ios--backend-wiring-map)
5. [Critical Gaps & Missing Endpoints](#5-critical-gaps--missing-endpoints)
6. [Schema Gaps — Missing Fields & Models](#6-schema-gaps)
7. [Prioritized Remediation Plan](#7-prioritized-remediation-plan)

---

## 1. Infrastructure & Middleware Pipeline

### Request Lifecycle (ordered)

```
Client Request
  │
  ├── 1. CORS (origin: CORS_ORIGIN env, credentials: true)
  ├── 2. express.json({ limit: '10mb' })          ← base64 image payloads
  ├── 3. requestIdMiddleware                       ← UUID v4 → req.requestId + x-request-id header
  ├── 4. globalRateLimit                           ← 100 req/min/IP (sliding window)
  ├── 5. [auth routes only] authRateLimit          ← 10 req/min/IP
  ├── 6. [protected routes] requireAuth            ← Bearer JWT → req.userId + req.companyId
  ├── 7. [per-route] validate(zodSchema, source)   ← Zod validation on body/query/params
  ├── 8. Controller → Service → Prisma → DTO
  └── 9. errorHandler                              ← AppError → envelope, unhandled → 500
```

### Auth Mechanism
- **Access token**: JWT, 15min TTL, signed with `JWT_SECRET`
- **Refresh token**: JWT, 30-day TTL, signed with `JWT_REFRESH_SECRET`, stored in DB
- **Token rotation**: Each refresh deletes the old token and issues a new pair
- **Reuse detection**: If a refresh token is not found in DB (already rotated), ALL user tokens are revoked — signals stolen token
- **Admin bypass**: `ADMIN_EMAILS` env var → cached `Set<email>`, bypasses entitlement gates

### Rate Limiting
| Scope | Limit | Applied To |
|-------|-------|------------|
| Global | 100 req/min/IP | All routes |
| Auth | 10 req/min/IP | `/v1/auth/*` only |

---

## 2. Response Contract

### Success Envelope
```json
{
  "ok": true,
  "data": "<T>",
  "meta": {
    "request_id": "uuid",
    "timestamp": "ISO8601",
    "pagination": { "next_cursor": "string | null" }
  }
}
```

### Error Envelope
```json
{
  "ok": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable",
    "field_errors": { "fieldName": ["message"] },
    "retryable": true | false,
    "paywall": { "placement": "string", "decision": "..." } | null
  },
  "meta": { "request_id": "uuid", "timestamp": "ISO8601" }
}
```

### Status Code Mapping
| Code | Error Class | When |
|------|-------------|------|
| 200 | — | Success (GET/PATCH/DELETE/action POST) |
| 201 | — | Resource created (POST) |
| 400 | `ValidationError` | Zod validation failure |
| 401 | `AuthenticationError` | Missing/invalid/expired JWT |
| 402 | `PaywallError` | Feature gated, credits exhausted |
| 403 | `AuthorizationError` | Authenticated but not permitted |
| 404 | `NotFoundError` | Resource not found or ownership mismatch |
| 409 | `ConflictError` | Duplicate (e.g., email already exists) |
| 500 | Unhandled | Unexpected server error |

---

## 3. Complete Endpoint Inventory (65 Implemented Endpoints)

### Module: Health (1 endpoint)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | No | DB connectivity check |

### Module: Auth (7 endpoints)
| Method | Path | Auth | Rate Limit | Description |
|--------|------|------|------------|-------------|
| POST | `/v1/auth/signup` | No | Auth (10/min) | Create user + company + entitlement + usage buckets |
| POST | `/v1/auth/login` | No | Auth | Email/password → token pair |
| POST | `/v1/auth/apple-signin` | No | Auth | Apple JWKS verify → create or link account |
| POST | `/v1/auth/refresh` | No | Auth | Rotate refresh token, issue new pair |
| POST | `/v1/auth/logout` | No* | Auth | Revoke refresh token(s) |
| POST | `/v1/auth/forgot-password` | No | Auth | Generate reset token (email TODO) |
| POST | `/v1/auth/reset-password` | No | Auth | Consume reset token, update password |

**Signup transaction**: Creates `Company` → `User(OWNER)` → `UserEntitlement(FREE)` → 2x `UsageBucket` (AI_GENERATION: 5, QUOTE_EXPORT: 5).

### Module: Users (1 endpoint)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/users/me` | Yes | Current user profile |

### Module: Companies (2 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/companies/me` | Yes | Current company profile |
| PATCH | `/v1/companies/me` | Yes | Update company settings (branding, tax, prefixes) |

### Module: Clients (5 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/clients` | Yes | Paginated list (cursor-based) |
| GET | `/v1/clients/:id` | Yes | Single client |
| POST | `/v1/clients` | Yes | Create client |
| PATCH | `/v1/clients/:id` | Yes | Update client |
| DELETE | `/v1/clients/:id` | Yes | Delete client |

### Module: Projects (5 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/projects` | Yes | Paginated list |
| GET | `/v1/projects/:id` | Yes | Single project |
| POST | `/v1/projects` | Yes | Create project |
| PATCH | `/v1/projects/:id` | Yes | Update project (status, details) |
| DELETE | `/v1/projects/:id` | Yes | Delete project (cascades assets, generations, activity) |

### Module: Assets (4 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/projects/:projectId/assets` | Yes | List project assets |
| POST | `/v1/projects/:projectId/assets` | Yes | Upload (base64 in JSON body → stored as `imageData`) |
| GET | `/v1/assets/:id/image` | **Both** | Serve binary image (public + auth-protected copies) |
| DELETE | `/v1/assets/:id` | Yes | Delete asset |

**Image storage**: Base64 in PostgreSQL `Text` column. URL rewritten to `/v1/assets/{id}/image`. Response: binary + `Cache-Control: public, max-age=31536000, immutable`.

### Module: Generations (5 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/projects/:projectId/generations` | Yes | List project generations |
| POST | `/v1/projects/:projectId/generations` | Yes | **Create generation (entitlement-gated)** |
| GET | `/v1/generations/:id` | Yes | Poll generation status |
| GET | `/v1/generations/:id/preview` | Yes | Serve generated image binary |
| GET | `/v1/generations/:id/preview` | **No** | Public copy (mounted separately in app.ts) |

**Generation pipeline** (fire-and-forget after 201):
```
QUEUED → PROCESSING → fetch reference photo → PiAPI Nano Banana Pro
  ├── fallback: PiAPI Nano Banana 2
  └── fallback: Google GenAI (Gemini 3.1 Flash Image)
→ COMPLETED (imageData stored) → background: Gemini 2.5 Flash → MaterialSuggestions
```

**Entitlement gate**: Pro → unlimited. Free → atomic `UsageBucket` decrement in Prisma transaction. 0 remaining → `PaywallError(402, GENERATION_LIMIT_HIT)`.

### Module: Materials (2 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/generations/:generationId/materials` | Yes | List material suggestions for a generation |
| PATCH | `/v1/materials/:id` | Yes | Toggle `is_selected` on a suggestion |

### Module: Estimates (5 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/estimates` | Yes | Paginated list (optional `project_id` filter) |
| GET | `/v1/estimates/:id` | Yes | Single estimate |
| POST | `/v1/estimates` | Yes | Create (auto-number `EST-XXXX` via transaction) |
| PATCH | `/v1/estimates/:id` | Yes | Update status, totals, notes |
| DELETE | `/v1/estimates/:id` | Yes | Delete estimate (cascades line items) |

### Module: Estimate Line Items (4 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/estimates/:estimateId/line-items` | Yes | List line items |
| POST | `/v1/estimates/:estimateId/line-items` | Yes | Create + recalculate estimate totals |
| PATCH | `/v1/estimate-line-items/:id` | Yes | Update + recalculate |
| DELETE | `/v1/estimate-line-items/:id` | Yes | Delete + recalculate |

**Recalculation**: Every CUD on line items triggers `recalculateEstimateTotals` — sums by category (MATERIALS, LABOR, OTHER), computes tax per line (`lineTotal * taxRate`), subtracts `discountAmount`.

### Module: Proposals (4 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/proposals` | Yes | Paginated list (optional `project_id` filter) |
| GET | `/v1/proposals/:id` | Yes | Single proposal |
| POST | `/v1/proposals` | Yes | Create (generates `shareToken = UUID`) |
| POST | `/v1/proposals/:id/send` | Yes | Mark as SENT, set `sentAt`, log activity |

### Module: Invoices (6 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/invoices` | Yes | Paginated list (optional `project_id` filter) |
| GET | `/v1/invoices/:id` | Yes | Single invoice |
| POST | `/v1/invoices` | Yes | **Create (Pro-only gate)**, auto-number `INV-XXXX` |
| PATCH | `/v1/invoices/:id` | Yes | Update status, payment tracking |
| POST | `/v1/invoices/:id/send` | Yes | Mark as SENT, set `sentAt`, log activity |
| DELETE | `/v1/invoices/:id` | Yes | Delete invoice |

**Invoice entitlement gate**: Requires `CAN_CREATE_INVOICE === true` AND active subscription status. Free → `PaywallError(402, INVOICE_LOCKED)`.

### Module: Invoice Line Items (4 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/invoices/:invoiceId/line-items` | Yes | List line items |
| POST | `/v1/invoices/:invoiceId/line-items` | Yes | Create + recalculate invoice totals |
| PATCH | `/v1/invoice-line-items/:id` | Yes | Update + recalculate |
| DELETE | `/v1/invoice-line-items/:id` | Yes | Delete + recalculate |

### Module: Pricing Profiles (5 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/pricing-profiles` | Yes | Paginated list |
| GET | `/v1/pricing-profiles/:id` | Yes | Single profile |
| POST | `/v1/pricing-profiles` | Yes | Create (transaction if `is_default`) |
| PATCH | `/v1/pricing-profiles/:id` | Yes | Update (transaction if setting default) |
| DELETE | `/v1/pricing-profiles/:id` | Yes | Delete (cascades labor rates) |

### Module: Labor Rates (4 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/pricing-profiles/:profileId/labor-rates` | Yes | List rates for profile |
| POST | `/v1/pricing-profiles/:profileId/labor-rates` | Yes | Create rate rule |
| PATCH | `/v1/labor-rates/:id` | Yes | Update rate rule |
| DELETE | `/v1/labor-rates/:id` | Yes | Delete rate rule |

### Module: Activity (1 endpoint)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/projects/:projectId/activity` | Yes | Paginated activity log for project |

### Module: Commerce (5 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/commerce/products` | Yes | List subscription products with plan details |
| GET | `/v1/commerce/entitlement` | Yes | Current entitlement snapshot (feature flags + usage) |
| POST | `/v1/commerce/purchase-attempt` | Yes | Create purchase attempt → `appAccountToken` for StoreKit |
| POST | `/v1/commerce/transactions/sync` | Yes | Sync StoreKit transaction → upgrade entitlement |
| POST | `/v1/commerce/restore` | Yes | Restore purchases from StoreKit receipt |

**Entitlement snapshot** returns:
```
subscription_state, current_plan_code,
feature_flags: { CAN_GENERATE_PREVIEW, CAN_EXPORT_QUOTE, CAN_REMOVE_WATERMARK,
  CAN_USE_BRANDING, CAN_CREATE_INVOICE, CAN_SHARE_APPROVAL_LINK,
  CAN_EXPORT_MATERIAL_LINKS, CAN_USE_HIGH_RES_PREVIEW },
usage: [{ metric_code, included_quantity, consumed_quantity, remaining_quantity }],
renewal_date, trial_ends_at, grace_period_ends_at, billing_warning
```

### Module: Usage (2 endpoints)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/usage` | Yes | Same as `GET /commerce/entitlement` |
| POST | `/v1/usage/check` | Yes | **Atomic credit consumption** (serializable transaction) |

### Module: Dashboard (1 endpoint)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/dashboard/summary` | Yes | 6 parallel queries → aggregate stats |

### Module: Contractors (1 endpoint)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/contractors/search` | Yes | Google Places text search by project type + location |

**Total: 65 implemented endpoints across 16 modules.**

---

## 4. iOS ↔ Backend Wiring Map

Every iOS `APIEndpoint` enum case maps 1:1 to a backend route:

| iOS APIEndpoint Case | Backend Route | iOS Service | iOS ViewModel |
|---------------------|---------------|-------------|---------------|
| `authLogin` | POST `/v1/auth/login` | `LiveAuthService` | `LoginViewModel` |
| `authSignup` | POST `/v1/auth/signup` | `LiveAuthService` | `SignUpViewModel` |
| `authAppleSignIn` | POST `/v1/auth/apple-signin` | `LiveAuthService` | `LoginViewModel` |
| `authRefreshToken` | POST `/v1/auth/refresh` | `APIClient` (auto) | — (transparent) |
| `authLogout` | POST `/v1/auth/logout` | `LiveAuthService` | `AppState` |
| `authForgotPassword` | POST `/v1/auth/forgot-password` | `LiveAuthService` | `ForgotPasswordViewModel` |
| `getMe` | GET `/v1/users/me` | `LiveUserService` | `AppState` (bootstrap) |
| `getCompany` | GET `/v1/companies/me` | `LiveCompanyService` | `AppState` / `SettingsViewModel` |
| `updateCompany` | PATCH `/v1/companies/me` | `LiveCompanyService` | `CompanyBrandingViewModel` |
| `listClients` | GET `/v1/clients` | `LiveClientService` | `ClientListViewModel` |
| `getClient` | GET `/v1/clients/:id` | `LiveClientService` | `ClientDetailViewModel` |
| `createClient` | POST `/v1/clients` | `LiveClientService` | `ClientFormViewModel` |
| `updateClient` | PATCH `/v1/clients/:id` | `LiveClientService` | `ClientFormViewModel` |
| `deleteClient` | DELETE `/v1/clients/:id` | `LiveClientService` | `ClientDetailViewModel` |
| `listProjects` | GET `/v1/projects` | `LiveProjectService` | `ProjectListViewModel` |
| `getProject` | GET `/v1/projects/:id` | `LiveProjectService` | `ProjectDetailViewModel` |
| `createProject` | POST `/v1/projects` | `LiveProjectService` | `ProjectCreationViewModel` |
| `updateProject` | PATCH `/v1/projects/:id` | `LiveProjectService` | `ProjectDetailViewModel` |
| `deleteProject` | DELETE `/v1/projects/:id` | `LiveProjectService` | `ProjectDetailViewModel` |
| `listAssets` | GET `/v1/projects/:pid/assets` | `LiveAssetService` | `ProjectDetailViewModel` |
| `uploadAsset` | POST `/v1/projects/:pid/assets` | `LiveAssetService` | `ProjectCreationViewModel` |
| `deleteAsset` | DELETE `/v1/assets/:id` | `LiveAssetService` | `ProjectDetailViewModel` |
| `listGenerations` | GET `/v1/projects/:pid/generations` | `LiveGenerationService` | `ProjectDetailViewModel` |
| `createGeneration` | POST `/v1/projects/:pid/generations` | `LiveGenerationService` | `ProjectDetailViewModel` |
| `getGeneration` | GET `/v1/generations/:id` | `LiveGenerationService` | `ProjectDetailViewModel` (polling) |
| `listMaterialSuggestions` | GET `/v1/generations/:gid/materials` | `LiveMaterialService` | `ProjectDetailViewModel` |
| `updateMaterialSelection` | PATCH `/v1/materials/:id` | `LiveMaterialService` | `ProjectDetailViewModel` |
| `listEstimates` | GET `/v1/estimates` | `LiveEstimateService` | `EstimateListViewModel` |
| `getEstimate` | GET `/v1/estimates/:id` | `LiveEstimateService` | `EstimateEditorViewModel` |
| `createEstimate` | POST `/v1/estimates` | `LiveEstimateService` | `ProjectDetailViewModel` |
| `updateEstimate` | PATCH `/v1/estimates/:id` | `LiveEstimateService` | `EstimateEditorViewModel` |
| `deleteEstimate` | DELETE `/v1/estimates/:id` | `LiveEstimateService` | `EstimateEditorViewModel` |
| `listEstimateLineItems` | GET `/v1/estimates/:eid/line-items` | `LiveEstimateService` | `EstimateEditorViewModel` |
| `createEstimateLineItem` | POST `/v1/estimates/:eid/line-items` | `LiveEstimateService` | `EstimateEditorViewModel` |
| `updateEstimateLineItem` | PATCH `/v1/estimate-line-items/:id` | `LiveEstimateService` | `EstimateEditorViewModel` |
| `deleteEstimateLineItem` | DELETE `/v1/estimate-line-items/:id` | `LiveEstimateService` | `EstimateEditorViewModel` |
| `listProposals` | GET `/v1/proposals` | `LiveProposalService` | `ProposalListViewModel` |
| `getProposal` | GET `/v1/proposals/:id` | `LiveProposalService` | `ProposalPreviewViewModel` |
| `createProposal` | POST `/v1/proposals` | `LiveProposalService` | `ProjectDetailViewModel` |
| `sendProposal` | POST `/v1/proposals/:id/send` | `LiveProposalService` | `ProposalPreviewViewModel` |
| `listInvoices` | GET `/v1/invoices` | `LiveInvoiceService` | `InvoiceListViewModel` |
| `getInvoice` | GET `/v1/invoices/:id` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `createInvoice` | POST `/v1/invoices` | `LiveInvoiceService` | `InvoiceCreationViewModel` |
| `updateInvoice` | PATCH `/v1/invoices/:id` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `sendInvoice` | POST `/v1/invoices/:id/send` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `deleteInvoice` | DELETE `/v1/invoices/:id` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `listInvoiceLineItems` | GET `/v1/invoices/:iid/line-items` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `createInvoiceLineItem` | POST `/v1/invoices/:iid/line-items` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `updateInvoiceLineItem` | PATCH `/v1/invoice-line-items/:id` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `deleteInvoiceLineItem` | DELETE `/v1/invoice-line-items/:id` | `LiveInvoiceService` | `InvoiceDetailViewModel` |
| `listPricingProfiles` | GET `/v1/pricing-profiles` | `LivePricingService` | `PricingProfilesViewModel` |
| `getPricingProfile` | GET `/v1/pricing-profiles/:id` | `LivePricingService` | `PricingProfilesViewModel` |
| `createPricingProfile` | POST `/v1/pricing-profiles` | `LivePricingService` | `PricingProfilesViewModel` |
| `updatePricingProfile` | PATCH `/v1/pricing-profiles/:id` | `LivePricingService` | `PricingProfilesViewModel` |
| `deletePricingProfile` | DELETE `/v1/pricing-profiles/:id` | `LivePricingService` | `PricingProfilesViewModel` |
| `listLaborRateRules` | GET `/v1/pricing-profiles/:pid/labor-rates` | `LivePricingService` | `PricingProfilesViewModel` |
| `createLaborRateRule` | POST `/v1/pricing-profiles/:pid/labor-rates` | `LivePricingService` | `PricingProfilesViewModel` |
| `updateLaborRateRule` | PATCH `/v1/labor-rates/:id` | `LivePricingService` | `PricingProfilesViewModel` |
| `deleteLaborRateRule` | DELETE `/v1/labor-rates/:id` | `LivePricingService` | `PricingProfilesViewModel` |
| `listActivityLog` | GET `/v1/projects/:pid/activity` | `LiveActivityService` | `ProjectDetailViewModel` |
| `getCommerceProducts` | GET `/v1/commerce/products` | `CommerceAPIClient` | `FeatureGateCoordinator` |
| `getEntitlement` | GET `/v1/commerce/entitlement` | `CommerceAPIClient` | `EntitlementStore` |
| `createPurchaseAttempt` | POST `/v1/commerce/purchase-attempt` | `CommerceAPIClient` | `PaywallHostViewModel` |
| `syncTransaction` | POST `/v1/commerce/transactions/sync` | `CommerceAPIClient` | `PaywallHostViewModel` |
| `restorePurchases` | POST `/v1/commerce/restore` | `CommerceAPIClient` | `PaywallHostViewModel` |
| `getUsage` | GET `/v1/usage` | `CommerceAPIClient` | `UsageMeterStore` |
| `checkUsage` | POST `/v1/usage/check` | `CommerceAPIClient` | `UsageMeterStore` |
| `getDashboardSummary` | GET `/v1/dashboard/summary` | `LiveDashboardService` | `DashboardViewModel` |

**All 65 iOS APIEndpoint cases have matching backend routes. No orphaned endpoints.**

---

## 5. Critical Gaps — Missing Endpoints

These endpoints are required by the project specs but are NOT implemented:

### GAP 1: App Store Server Notifications Webhook — CRITICAL

```
POST /v1/commerce/webhooks/app-store
```
- **Auth**: No (Apple-signed JWS payload, verified via Apple root CA)
- **Purpose**: Receive subscription lifecycle events from Apple (renewals, expirations, grace periods, billing retries, refunds, revocations)
- **Without this**: Subscription state is NEVER updated server-side after initial purchase. A lapsed subscriber retains `PRO_ACTIVE` indefinitely.
- **Implementation**:
  - Verify Apple JWS using `jsonwebtoken` + Apple Root CA certificate chain
  - Parse `signedTransactionInfo` and `signedRenewalInfo`
  - Map Apple notification types → `SubscriptionEventType` enum
  - Update `UserEntitlement` status based on event (e.g., `DID_FAIL_TO_RENEW` → `BILLING_RETRY`, `EXPIRED` → `EXPIRED`, `REVOKE` → `REVOKED`, `DID_RENEW` → `PRO_ACTIVE`)
  - Create `SubscriptionEvent` audit record
- **iOS wiring**: None needed — Apple sends directly to this URL configured in App Store Connect
- **Backend files to create/modify**:
  - `src/modules/commerce/commerce.routes.ts` — add route
  - `src/modules/commerce/commerce.service.ts` — add `handleAppStoreNotification()`
  - `src/lib/apple-receipt.ts` — new file for JWS verification

### GAP 2: Proposal PDF Export — CRITICAL

```
GET /v1/proposals/:id/export
```
- **Auth**: Yes
- **Purpose**: Generate PDF with server-side watermark enforcement
- **Without this**: Free-tier watermark enforcement is client-only (bypassable). The spec explicitly states "watermarking must happen only on the server-side render path."
- **Implementation**:
  - Fetch proposal + estimate + line items + company branding + project + before/after images
  - Check entitlement: `CAN_REMOVE_WATERMARK` → clean PDF; else → watermarked
  - Render PDF using `pdfkit` or `puppeteer`
  - Return binary `application/pdf` with `Content-Disposition: attachment`
  - Optionally store as Asset record (`pdfAssetId` on Proposal)
- **iOS wiring**: New `APIEndpoint.exportProposal(id: String)` → `LiveProposalService.exportPDF()` → returns `Data` for share sheet
- **Backend files to create**:
  - `src/modules/pdf/pdf.service.ts` — shared PDF rendering engine
  - `src/modules/pdf/watermark.service.ts` — watermark policy
  - `src/modules/proposals/proposals.routes.ts` — add export route
  - `src/modules/proposals/proposals.service.ts` — add `exportPDF()`

### GAP 3: Invoice PDF Export — HIGH

```
GET /v1/invoices/:id/export
```
- Same pattern as proposal export. Invoice PDFs with company branding + watermark enforcement.
- **Backend files**: `src/modules/invoices/invoices.routes.ts` — add export route

### GAP 4: Public Proposal Share Page — HIGH

```
GET /v1/proposals/share/:shareToken
```
- **Auth**: No (public, secured by unguessable UUID token)
- **Purpose**: Client views proposal, sees before/after images, pricing, scope — can approve or decline
- **Without this**: The entire client approval workflow is broken. `shareToken` is generated and stored but never consumed.
- **Implementation**:
  - Lookup proposal by `shareToken`
  - Include: estimate (with line items), project (with assets + generations), company branding
  - If `viewedAt` is null, set it + log `PROPOSAL_VIEWED` activity
  - Return full proposal view DTO
- **Related endpoints needed**:

```
POST /v1/proposals/share/:shareToken/respond
```
  - Body: `{ decision: "approved" | "declined", message?: string }`
  - Updates proposal status + `respondedAt`
  - Logs `PROPOSAL_APPROVED` or `PROPOSAL_DECLINED` activity
- **iOS wiring**: Not directly — this is consumed by a web view (Safari or in-app WKWebView)
- **Backend files**:
  - `src/modules/proposals/proposals.routes.ts` — add public routes
  - `src/modules/proposals/proposals.service.ts` — add `getByShareToken()`, `respondToProposal()`

### GAP 5: Proposal Update & Delete — MEDIUM

```
PATCH /v1/proposals/:id
DELETE /v1/proposals/:id
```
- Currently proposals cannot be edited or deleted after creation.
- **Implementation**: Standard CRUD pattern following existing modules.

### GAP 6: User Profile Update — MEDIUM

```
PATCH /v1/users/me
```
- Currently only `GET /v1/users/me` exists. Users cannot update their name, phone, avatar.
- **Implementation**: Zod schema for `full_name`, `phone`, `avatar_url` + standard update.

### GAP 7: Email Sending Infrastructure — HIGH

The following endpoints log "TODO: send email" but never actually send:
- `POST /v1/auth/forgot-password` — password reset email
- `POST /v1/proposals/:id/send` — proposal link to client
- `POST /v1/invoices/:id/send` — invoice to client

**Implementation**: Integrate a transactional email provider (Resend, SendGrid, or AWS SES). Create `src/lib/email.ts` with template rendering + send.

---

## 6. Schema Gaps — Missing Fields & Models

### 6A. Missing Prisma Fields (per spec)

**Proposal** — missing 7 fields:
| Field | Type | Purpose |
|-------|------|---------|
| `proposalNumber` | String | Auto-incremented (like estimates) |
| `title` | String | Proposal title |
| `introText` | String? | Introduction paragraph |
| `scopeOfWork` | String? | Scope description |
| `timelineText` | String? | Timeline description |
| `footerText` | String? | Footer/closing |
| `pdfAssetId` | String? | FK → Asset for generated PDF |

**Estimate** — missing 6 fields:
| Field | Type | Purpose |
|-------|------|---------|
| `pricingProfileId` | String? | FK → PricingProfile used |
| `createdByUserId` | String? | Audit: who created |
| `title` | String? | Estimate title |
| `assumptions` | String? | Assumptions text block |
| `exclusions` | String? | Exclusions text block |
| `contingencyAmount` | Decimal? | Contingency line |

**Invoice** — missing 5 fields:
| Field | Type | Purpose |
|-------|------|---------|
| `proposalId` | String? | FK → Proposal (traceability) |
| `issuedDate` | DateTime? | Formal issue date |
| `discountAmount` | Decimal? | Discount |
| `paymentInstructions` | String? | Payment instructions text |
| `currencyCode` | String? | Currency (default USD) |

**Company** — missing 5 fields:
| Field | Type | Purpose |
|-------|------|---------|
| `defaultLanguage` | String? | Default doc language |
| `timezone` | String? | Business timezone |
| `websiteUrl` | String? | Company website |
| `proposalPrefix` | String? | Auto-numbering prefix |
| `taxLabel` | String? | Custom tax label (e.g., "GST") |

**EstimateLineItem** — missing 3 key fields:
| Field | Type | Purpose |
|-------|------|---------|
| `parentLineItemId` | String? | Self-referential FK for grouping |
| `sourceMaterialSuggestionId` | String? | FK back to MaterialSuggestion |
| `itemType` | String? | flat_rate / per_unit / hourly |

**LaborRateRule** — missing rate type variants:
| Field | Type | Purpose |
|-------|------|---------|
| `rateType` | String | hourly / flat / unit |
| `flatRate` | Decimal? | Flat-rate amount |
| `unitRate` | Decimal? | Per-unit amount |
| `unit` | String? | Unit label for unit-rate types |

### 6B. Commerce Schema Drift (vs subscription-flow.md)

**`UsageBucket` unique constraint** — DATA INTEGRITY BUG:
- Current: `@@unique([userId, metricCode])` (2-field)
- Spec requires: `@@unique([userId, companyId, metricCode, source])` (4-field)
- Impact: Cannot have both a `STARTER_CREDITS` bucket and a `PRO_SUBSCRIPTION` bucket for the same metric. The commerce sync service tries to upsert a `PRO_SUBSCRIPTION` source bucket, which would violate the 2-field unique constraint.

**`UserEntitlement`** — missing fields:
| Field | Type | Purpose |
|-------|------|---------|
| `startsAt` | DateTime? | When subscription started |
| `endsAt` | DateTime? | When subscription ends |
| `source` | String? | How entitlement was acquired |
| `latestTransactionId` | String? | Most recent App Store transaction |
| `environment` | String? | sandbox / production |

**`SubscriptionEventType`** — missing 8 enum values:
`INITIAL_PURCHASE`, `GRACE_PERIOD_ENTERED`, `GRACE_PERIOD_RECOVERED`, `BILLING_RETRY_ENTERED`, `AUTO_RENEW_DISABLED`, `AUTO_RENEW_ENABLED`, `REFUNDED`, `PRODUCT_CHANGED`

**`EntitlementStatus`** — missing `ADMIN_OVERRIDE` value.

### 6C. Missing Models (V1.5+)

| Model | Purpose | Priority |
|-------|---------|----------|
| `user_identities` | OAuth provider abstraction (Apple, future Google) | Medium |
| `job_runs` | Durable async job tracking | Medium |
| `material_catalog_items` | Supplier/product catalog | Low |
| `project_members` | Team member assignment | Low (V1.5) |

---

## 7. Prioritized Remediation Plan

### P0 — Ship Blockers (Must fix before production billing)

| # | Item | Effort | Impact |
|---|------|--------|--------|
| 1 | **App Store Server Notifications webhook** | 2-3 days | Without this, subscriptions never expire server-side |
| 2 | **UsageBucket unique constraint fix** | 1 hour | Migration: change `@@unique([userId, metricCode])` → `@@unique([userId, companyId, metricCode, source])` |
| 3 | **UserEntitlement missing fields** | 2 hours | Migration: add `startsAt`, `endsAt`, `source`, `latestTransactionId`, `environment` |
| 4 | **SubscriptionEventType enum expansion** | 1 hour | Migration: add 8 missing values |

### P1 — Revenue Protection

| # | Item | Effort | Impact |
|---|------|--------|--------|
| 5 | **Server-side PDF export** (proposals + invoices) | 3-4 days | Watermark enforcement is client-only — bypassable |
| 6 | **Email sending infrastructure** | 1-2 days | Password reset, proposal send, invoice send are all no-ops |
| 7 | **Public proposal share page** | 1-2 days | Client approval workflow is completely broken |

### P2 — Feature Completeness

| # | Item | Effort | Impact |
|---|------|--------|--------|
| 8 | Proposal PATCH/DELETE endpoints | 2 hours | Users can't edit proposals |
| 9 | User profile PATCH endpoint | 1 hour | Users can't update their profile |
| 10 | Proposal schema migration (7 new fields) | 1 hour | Missing title, scope, timeline text |
| 11 | Estimate schema migration (6 new fields) | 1 hour | Missing assumptions, exclusions, contingency |
| 12 | Invoice schema migration (5 new fields) | 1 hour | Missing payment instructions, discount |
| 13 | Company schema migration (5 new fields) | 1 hour | Missing timezone, website, proposal prefix |

### P3 — Polish & Extensibility

| # | Item | Effort | Impact |
|---|------|--------|--------|
| 14 | EstimateLineItem hierarchical grouping (`parentLineItemId`) | 2 hours | Enables grouped/nested line items |
| 15 | LaborRateRule rate type variants | 2 hours | Enables flat-rate and per-unit labor |
| 16 | ActivityLogEntry generic entity tracking | 2 hours | Activity for non-project entities |
| 17 | `user_identities` model for OAuth extensibility | 3 hours | Future Google Sign-In support |

### Recommended Implementation Order

```
Phase 1 (Week 1): P0 items — Fix billing infrastructure
  ├── #2: UsageBucket constraint migration
  ├── #3: UserEntitlement fields migration
  ├── #4: SubscriptionEventType enum migration
  └── #1: App Store webhook endpoint

Phase 2 (Week 2): P1 items — Revenue protection
  ├── #6: Email infrastructure (Resend/SendGrid)
  ├── #7: Public proposal share page + respond
  └── #5: PDF export service (proposals + invoices)

Phase 3 (Week 3): P2 items — Feature completeness
  ├── #8-9: Missing CRUD endpoints
  └── #10-13: Schema migrations for missing fields

Phase 4 (Week 4): P3 items — Polish
  └── #14-17: Advanced features
```

### Architecture Best Practices Applied

1. **Module isolation**: Each new endpoint follows the existing `routes → controller → service → dto` pattern
2. **Transactional integrity**: All multi-table writes use Prisma transactions
3. **Idempotency**: Webhook handler uses `transactionId` for deduplication
4. **Zero-trust ownership**: Every query includes `companyId` filter — no resource leak across tenants
5. **Cursor pagination**: All list endpoints, never offset-based
6. **Envelope consistency**: All responses through `sendSuccess`/`sendError`
7. **Error hierarchy**: Specific `AppError` subclasses, never raw `throw new Error()`
8. **Zod at boundaries**: Every request body/query validated before hitting controller
9. **DTO transformation**: Never leak Prisma types; Decimal→Number, DateTime→ISO, enums→lowercase
