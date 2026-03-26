Below is the next implementation layer for the coding LLM: exact API contracts, DTO shapes, backend service boundaries, middleware rules, and SwiftUI commerce skeletons. This is the level where the coding LLM should be able to start generating the actual codebase in an organized way without inventing product behavior.

# 1. Normalized API response envelope

All backend endpoints should return a consistent envelope.

Use this shape everywhere:

```ts
type ApiSuccess<T> = {
  ok: true
  data: T
  meta?: {
    requestId?: string
    timestamp?: string
    pagination?: {
      nextCursor?: string | null
    }
  }
}

type ApiError = {
  ok: false
  error: {
    code: string
    message: string
    fieldErrors?: Record<string, string[]>
    details?: unknown
    retryable?: boolean
    paywall?: PaywallDecisionDto
  }
  meta?: {
    requestId?: string
    timestamp?: string
  }
}
```

Rules:

* never return unstructured errors
* always include a machine-readable `code`
* if a request is blocked by monetization, include a `paywall` payload
* do not mix transport errors with business errors

# 2. Core shared DTOs

These DTOs should live in `packages/types` and be imported by both the backend and web client. The iOS app should mirror them as Swift structs.

## 2.1 Commerce DTOs

```ts
type SubscriptionStateDto =
  | "FREE"
  | "TRIAL_ACTIVE"
  | "PRO_ACTIVE"
  | "GRACE_PERIOD"
  | "BILLING_RETRY"
  | "CANCELED_ACTIVE"
  | "EXPIRED"
  | "REVOKED"

type UsageMetricDto = "AI_GENERATION" | "QUOTE_EXPORT"

type FeatureCodeDto =
  | "CAN_GENERATE_PREVIEW"
  | "CAN_EXPORT_QUOTE"
  | "CAN_REMOVE_WATERMARK"
  | "CAN_USE_BRANDING"
  | "CAN_CREATE_INVOICE"
  | "CAN_SHARE_APPROVAL_LINK"
  | "CAN_EXPORT_MATERIAL_LINKS"
  | "CAN_USE_HIGH_RES_PREVIEW"
```

```ts
type StoreProductDto = {
  productId: string
  planCode: "PRO_MONTHLY" | "PRO_ANNUAL"
  displayName: string
  description: string
  priceDisplay: string
  billingPeriodLabel: string
  hasIntroOffer: boolean
  introOfferDisplayText?: string | null
  isEligibleForIntroOffer?: boolean | null
  isFeatured?: boolean
  savingsText?: string | null
}
```

```ts
type UsageBucketDto = {
  metricCode: UsageMetricDto
  includedQuantity: number
  consumedQuantity: number
  remainingQuantity: number
  source: string
}
```

```ts
type EntitlementSnapshotDto = {
  subscriptionState: SubscriptionStateDto
  currentPlanCode: "FREE_STARTER" | "PRO_MONTHLY" | "PRO_ANNUAL"
  featureFlags: Record<FeatureCodeDto, boolean>
  usage: UsageBucketDto[]
  renewalDate?: string | null
  trialEndsAt?: string | null
  gracePeriodEndsAt?: string | null
  isAutoRenewEnabled?: boolean | null
  billingWarning?: string | null
}
```

```ts
type PaywallPlacementDto =
  | "ONBOARDING_SOFT_GATE"
  | "POST_FIRST_GENERATION"
  | "POST_FIRST_QUOTE_EXPORT"
  | "GENERATION_LIMIT_HIT"
  | "QUOTE_LIMIT_HIT"
  | "INVOICE_LOCKED"
  | "BRANDING_LOCKED"
  | "APPROVAL_SHARE_LOCKED"
  | "WATERMARK_REMOVAL_LOCKED"
  | "SETTINGS_UPGRADE"

type PaywallDecisionDto = {
  placement: PaywallPlacementDto
  triggerReason: string
  blocking: boolean
  headline: string
  subheadline: string
  primaryCtaTitle: string
  secondaryCtaTitle?: string | null
  showContinueFree: boolean
  showRestorePurchases: boolean
  recommendedProductId?: string | null
  availableProducts?: StoreProductDto[]
}
```

## 2.2 Request/response DTOs

### `GET /v1/commerce/products`

Response:

```ts
type GetCommerceProductsResponse = {
  products: StoreProductDto[]
}
```

### `GET /v1/commerce/entitlement`

Response:

```ts
type GetEntitlementResponse = {
  entitlement: EntitlementSnapshotDto
}
```

### `POST /v1/commerce/purchase-attempt`

Request:

```ts
type CreatePurchaseAttemptRequest = {
  storeProductId: string
  offerType?: "INTRO_TRIAL" | "STANDARD" | null
  placement?: PaywallPlacementDto | null
  projectId?: string | null
}
```

Response:

```ts
type CreatePurchaseAttemptResponse = {
  purchaseAttemptId: string
  appAccountToken: string
}
```

### `POST /v1/commerce/transactions/sync`

Request:

```ts
type SyncTransactionRequest = {
  purchaseAttemptId?: string | null
  storeProductId: string
  transactionId: string
  originalTransactionId: string
  appAccountToken: string
  environment: "Sandbox" | "Production"
  signedPayload?: string | null
}
```

Response:

```ts
type SyncTransactionResponse = {
  entitlement: EntitlementSnapshotDto
}
```

### `POST /v1/commerce/restore`

Request:

```ts
type RestorePurchasesRequest = {
  appAccountToken?: string | null
}
```

Response:

```ts
type RestorePurchasesResponse = {
  entitlement: EntitlementSnapshotDto
}
```

### `GET /v1/usage`

Response:

```ts
type GetUsageResponse = {
  usage: UsageBucketDto[]
}
```

### `POST /v1/usage/check`

Request:

```ts
type CheckUsageRequest = {
  action:
    | "GENERATE_PREVIEW"
    | "EXPORT_QUOTE"
    | "CREATE_INVOICE"
    | "REMOVE_WATERMARK"
    | "ENABLE_BRANDING"
    | "SHARE_APPROVAL_LINK"
  projectId?: string | null
}
```

Response:

```ts
type CheckUsageResponse = {
  allowed: boolean
  reason?: string | null
  entitlement: EntitlementSnapshotDto
  paywall?: PaywallDecisionDto | null
}
```

# 3. Quote and generation gate contracts

The coding LLM should not invent gating responses ad hoc. Create exact gate helpers.

## 3.1 Generation action guard

Return one of:

```ts
type GeneratePreviewGateResult =
  | { allowed: true; mode: "FREE_CREDIT" | "PRO" }
  | { allowed: false; paywall: PaywallDecisionDto }
```

Rules:

* if Pro/trial/grace/canceled_active -> allowed `PRO`
* else if generation credits remaining > 0 -> allowed `FREE_CREDIT`
* else -> blocked with `GENERATION_LIMIT_HIT`

## 3.2 Quote export guard

Return one of:

```ts
type ExportQuoteGateResult =
  | {
      allowed: true
      mode: "FREE_WATERMARKED" | "PRO"
      exportPolicy: {
        applyWatermark: boolean
        allowBranding: boolean
        allowApprovalLink: boolean
        allowMaterialLinks: boolean
      }
    }
  | { allowed: false; paywall: PaywallDecisionDto }
```

## 3.3 Invoice guard

Return one of:

```ts
type CreateInvoiceGateResult =
  | { allowed: true }
  | { allowed: false; paywall: PaywallDecisionDto }
```

# 4. Backend service interface contracts

These are the interfaces the coding LLM should implement before controllers.

## 4.1 Entitlement service

```ts
interface EntitlementService {
  getEffectiveEntitlement(userId: string, companyId: string): Promise<EntitlementSnapshotDto>
  canGeneratePreview(userId: string, companyId: string): Promise<GeneratePreviewGateResult>
  canExportQuote(userId: string, companyId: string): Promise<ExportQuoteGateResult>
  canCreateInvoice(userId: string, companyId: string): Promise<CreateInvoiceGateResult>
  canRemoveWatermark(userId: string, companyId: string): Promise<boolean>
  canUseBranding(userId: string, companyId: string): Promise<boolean>
}
```

## 4.2 Usage credit service

```ts
interface UsageCreditService {
  initializeStarterCredits(userId: string, companyId: string): Promise<void>
  getUsageSummary(userId: string, companyId: string): Promise<UsageBucketDto[]>
  consumeGenerationCredit(params: {
    userId: string
    companyId: string
    projectId?: string | null
    relatedEntityId?: string | null
  }): Promise<UsageBucketDto>
  consumeQuoteCredit(params: {
    userId: string
    companyId: string
    projectId?: string | null
    relatedEntityId?: string | null
  }): Promise<UsageBucketDto>
}
```

## 4.3 Commerce sync service

```ts
interface CommerceSyncService {
  syncClientTransaction(input: SyncTransactionRequest, actor: {
    userId: string
    companyId: string
  }): Promise<EntitlementSnapshotDto>

  restorePurchases(input: RestorePurchasesRequest, actor: {
    userId: string
    companyId: string
  }): Promise<EntitlementSnapshotDto>

  handleAppStoreNotification(payload: unknown): Promise<void>
}
```

## 4.4 Paywall service

```ts
interface PaywallService {
  evaluate(input: {
    userId: string
    companyId: string
    placement: PaywallPlacementDto
    triggerReason: string
    blocking: boolean
    locale: string
    projectId?: string | null
  }): Promise<PaywallDecisionDto>

  recordImpression(input: {
    userId: string
    companyId: string
    placement: PaywallPlacementDto
    triggerReason: string
    projectId?: string | null
    shownVariant?: string | null
  }): Promise<void>
}
```

## 4.5 Watermark policy service

```ts
type ExportBrandingPolicy = {
  applyWatermark: boolean
  allowBranding: boolean
  allowApprovalLink: boolean
  allowMaterialLinks: boolean
}

interface WatermarkPolicyService {
  getProposalExportPolicy(userId: string, companyId: string): Promise<ExportBrandingPolicy>
  getInvoiceExportPolicy(userId: string, companyId: string): Promise<ExportBrandingPolicy>
}
```

# 5. Repository contracts

Keep repositories simple and narrowly scoped.

## 5.1 Usage repository

```ts
interface UsageRepository {
  findBuckets(userId: string, companyId: string): Promise<UsageBucketRecord[]>
  findBucketForUpdate(userId: string, companyId: string, metricCode: UsageMetricCode): Promise<UsageBucketRecord | null>
  createBucket(input: CreateUsageBucketInput): Promise<UsageBucketRecord>
  updateConsumedQuantity(id: string, consumedQuantity: number): Promise<UsageBucketRecord>
  createUsageEvent(input: CreateUsageEventInput): Promise<void>
}
```

## 5.2 Entitlement repository

```ts
interface EntitlementRepository {
  findCurrentEntitlement(userId: string, companyId: string): Promise<UserEntitlementRecord | null>
  upsertEntitlement(input: UpsertEntitlementInput): Promise<UserEntitlementRecord>
  createSubscriptionEvent(input: CreateSubscriptionEventInput): Promise<void>
}
```

## 5.3 Plan/product repository

```ts
interface PlanRepository {
  findPlanByCode(code: string): Promise<PlanRecord | null>
  findSubscriptionProducts(): Promise<SubscriptionProductRecord[]>
  findSubscriptionProductByStoreId(storeProductId: string): Promise<SubscriptionProductRecord | null>
}
```

# 6. Backend middleware and route guards

The coding LLM should implement action-level guards instead of giant route-level conditionals.

## 6.1 Auth middleware

Every commerce and usage route requires:

* authenticated user
* resolved `companyId`
* request-scoped user context

## 6.2 Subscription enforcement helper

Create a reusable helper:

```ts
async function requireCapability(
  capability: FeatureCodeDto,
  actor: { userId: string; companyId: string }
): Promise<void>
```

If denied, throw a business error with embedded paywall payload where appropriate.

## 6.3 Credit consumption timing rules

The backend must consume credits only at the correct point:

* generation credit is consumed when generation job is successfully enqueued
* quote credit is consumed when PDF export job is successfully started
* do not consume credits on UI opening, draft editing, or failed validation

# 7. Proposal export policy rules

The PDF layer must consume a single export policy object and never infer monetization rules itself.

```ts
type ProposalExportRenderOptions = {
  applyWatermark: boolean
  allowBranding: boolean
  allowApprovalLink: boolean
  allowMaterialLinks: boolean
}
```

Behavior:

* free mode -> watermark true, branding false, approval false, material links false
* Pro/trial -> all true except any product-specific future restrictions

# 8. Swift models for the iOS commerce module

Mirror backend DTOs in Swift.

```swift
struct StoreProductModel: Identifiable, Equatable, Codable {
    let id: String
    let productId: String
    let planCode: PlanCode
    let displayName: String
    let description: String
    let priceDisplay: String
    let billingPeriodLabel: String
    let hasIntroOffer: Bool
    let introOfferDisplayText: String?
    let isEligibleForIntroOffer: Bool?
    let isFeatured: Bool
    let savingsText: String?
}
```

```swift
enum PlanCode: String, Codable {
    case freeStarter = "FREE_STARTER"
    case proMonthly = "PRO_MONTHLY"
    case proAnnual = "PRO_ANNUAL"
}
```

```swift
enum SubscriptionState: String, Codable {
    case free = "FREE"
    case trialActive = "TRIAL_ACTIVE"
    case proActive = "PRO_ACTIVE"
    case gracePeriod = "GRACE_PERIOD"
    case billingRetry = "BILLING_RETRY"
    case canceledActive = "CANCELED_ACTIVE"
    case expired = "EXPIRED"
    case revoked = "REVOKED"
}
```

```swift
enum UsageMetricCode: String, Codable {
    case aiGeneration = "AI_GENERATION"
    case quoteExport = "QUOTE_EXPORT"
}
```

```swift
struct UsageBucket: Codable, Equatable {
    let metricCode: UsageMetricCode
    let includedQuantity: Int
    let consumedQuantity: Int
    let remainingQuantity: Int
    let source: String
}
```

```swift
struct EntitlementSnapshot: Codable, Equatable {
    let subscriptionState: SubscriptionState
    let currentPlanCode: PlanCode
    let featureFlags: [String: Bool]
    let usage: [UsageBucket]
    let renewalDate: Date?
    let trialEndsAt: Date?
    let gracePeriodEndsAt: Date?
    let isAutoRenewEnabled: Bool?
    let billingWarning: String?
}
```

```swift
enum PaywallPlacement: String, Codable {
    case onboardingSoftGate = "ONBOARDING_SOFT_GATE"
    case postFirstGeneration = "POST_FIRST_GENERATION"
    case postFirstQuoteExport = "POST_FIRST_QUOTE_EXPORT"
    case generationLimitHit = "GENERATION_LIMIT_HIT"
    case quoteLimitHit = "QUOTE_LIMIT_HIT"
    case invoiceLocked = "INVOICE_LOCKED"
    case brandingLocked = "BRANDING_LOCKED"
    case approvalShareLocked = "APPROVAL_SHARE_LOCKED"
    case watermarkRemovalLocked = "WATERMARK_REMOVAL_LOCKED"
    case settingsUpgrade = "SETTINGS_UPGRADE"
}
```

```swift
struct PaywallDecision: Codable, Equatable {
    let placement: PaywallPlacement
    let triggerReason: String
    let blocking: Bool
    let headline: String
    let subheadline: String
    let primaryCtaTitle: String
    let secondaryCtaTitle: String?
    let showContinueFree: Bool
    let showRestorePurchases: Bool
    let recommendedProductId: String?
    let availableProducts: [StoreProductModel]?
}
```

# 9. Swift protocol skeletons

The coding LLM should generate these protocols first.

```swift
protocol CommerceAPIClientProtocol {
    func fetchProducts() async throws -> [StoreProductModel]
    func fetchEntitlement() async throws -> EntitlementSnapshot
    func createPurchaseAttempt(
        storeProductId: String,
        offerType: String?,
        placement: PaywallPlacement?,
        projectId: String?
    ) async throws -> PurchaseAttemptResponse

    func syncTransaction(_ request: SyncTransactionRequest) async throws -> EntitlementSnapshot
    func restorePurchases(appAccountToken: String?) async throws -> EntitlementSnapshot
    func checkUsage(action: UsageCheckAction, projectId: String?) async throws -> UsageCheckResponse
}
```

```swift
protocol StoreKitCatalogProviding {
    func loadProducts() async throws -> [StoreProductModel]
}
```

```swift
protocol PurchaseCoordinating {
    func purchase(productId: String, context: PaywallPlacement?) async throws -> EntitlementSnapshot
    func restorePurchases() async throws -> EntitlementSnapshot
}
```

```swift
protocol EntitlementStoreProtocol: ObservableObject {
    var snapshot: EntitlementSnapshot? { get }
    func refresh() async
    func update(_ snapshot: EntitlementSnapshot)
    func hasFeature(_ featureKey: String) -> Bool
}
```

```swift
protocol UsageMeterStoreProtocol: ObservableObject {
    var usageBuckets: [UsageBucket] { get }
    func refresh() async
    func remaining(for metric: UsageMetricCode) -> Int
}
```

# 10. Swift concrete class skeletons

Do not put purchase logic in views. Use dedicated services.

## 10.1 `CommerceAPIClient`

Responsibilities:

* hit backend endpoints
* decode normalized response envelopes
* map errors into app-friendly error types

Key methods:

* `fetchProducts()`
* `fetchEntitlement()`
* `createPurchaseAttempt(...)`
* `syncTransaction(...)`
* `restorePurchases(...)`
* `checkUsage(...)`

## 10.2 `StoreKitCatalogService`

Responsibilities:

* request StoreKit products from Apple
* normalize pricing display
* join StoreKit data with backend product config if needed

## 10.3 `StoreKitPurchaseCoordinator`

Responsibilities:

* create purchase attempt on backend
* launch StoreKit purchase
* verify successful transaction locally
* call backend sync
* update entitlement store
* finish transaction

## 10.4 `EntitlementStore`

Responsibilities:

* published snapshot
* app launch refresh
* foreground refresh
* derived helpers like `isPremium`, `isTrial`, `isGracePeriod`

## 10.5 `UsageMeterStore`

Responsibilities:

* load usage from backend or entitlement snapshot
* expose remaining counts
* support dashboard usage card

# 11. SwiftUI paywall skeleton

## 11.1 `PaywallHostView`

Responsibilities:

* host all paywall sections
* react to purchase state
* present selected product
* display trial eligibility and usage meter

State:

* loading
* loaded
* purchasing
* restoreInProgress
* failed(error)

Subcomponents:

* `PaywallHeroSection`
* `PlanToggleSection`
* `FeatureListSection`
* `UsageMeterSection`
* `PurchaseButtonSection`
* `SecondaryActionsSection`
* `LegalDisclosureSection`

## 11.2 `PaywallHostViewModel`

Properties:

* `context: PaywallPlacement`
* `decision: PaywallDecision?`
* `products: [StoreProductModel]`
* `selectedProductId: String?`
* `entitlementSnapshot: EntitlementSnapshot?`
* `purchaseState: PurchaseUIState`
* `errorMessage: String?`

Methods:

* `load()`
* `selectProduct(_:)`
* `purchaseSelectedProduct()`
* `restorePurchases()`
* `dismiss()`

## 11.3 `PurchaseUIState`

```swift
enum PurchaseUIState: Equatable {
    case idle
    case loading
    case purchasing
    case restoring
    case success
    case failed(message: String)
}
```

# 12. Dashboard and gating view models

## 12.1 `DashboardSubscriptionCardViewModel`

Responsibilities:

* choose which card layout to show
* format usage/trial/renewal data
* expose CTA destination

Derived display rules:

* free + credits remaining -> show starter credits and upgrade CTA
* trial -> show “trial active” and end date
* pro -> show “Pro active”
* grace period -> show billing warning banner
* expired with zero credits -> show locked state and upgrade CTA

## 12.2 `FeatureGateCoordinator`

This is important. Build one feature-gating coordinator that view models can call before protected actions.

Methods:

* `guardGeneratePreview(projectId:)`
* `guardExportQuote(projectId:)`
* `guardCreateInvoice(projectId:)`
* `guardEnableBranding(projectId:)`

Each method should:

1. call backend `checkUsage`
2. if allowed, continue
3. if denied, return a `PaywallDecision`
4. UI presents paywall with correct placement

# 13. Error model

Create a single app-side commerce error type.

```swift
enum CommerceError: LocalizedError, Equatable {
    case network
    case backend(code: String, message: String)
    case paywallRequired(PaywallDecision)
    case purchaseCancelled
    case purchasePending
    case verificationFailed
    case restoreFailed
    case unknown(String)
}
```

Rules:

* user cancellation is not a “failure” toast
* pending purchase state should be handled calmly
* verification failure should not unlock premium
* backend denial with paywall payload should present paywall, not generic error

# 14. App lifecycle integration

On app launch:

* hydrate auth
* fetch entitlement snapshot
* fetch usage if not already included
* update dashboard subscription card

On foreground:

* refresh entitlement snapshot if stale
* refresh local StoreKit transactions if needed
* if user returned from App Store purchase flow, reconcile immediately

On login/logout:

* reset stores cleanly
* do not leak previous user’s entitlement data

# 15. Analytics events for monetization

Track the following:

* `paywall_impression`
* `paywall_dismissed`
* `paywall_continue_free_tapped`
* `purchase_attempt_started`
* `purchase_attempt_completed`
* `purchase_attempt_failed`
* `restore_started`
* `restore_completed`
* `restore_failed`
* `starter_generation_credit_consumed`
* `starter_quote_credit_consumed`
* `generation_blocked_paywall`
* `quote_export_blocked_paywall`
* `invoice_blocked_paywall`
* `trial_started`
* `subscription_became_active`
* `subscription_expired`
* `subscription_entered_grace_period`

# 16. First-pass backend implementation order

1. Add Prisma models and migration.
2. Seed plans and subscription products.
3. Build repositories.
4. Build `UsageCreditService`.
5. Build `EntitlementService`.
6. Build `GET /v1/commerce/entitlement`.
7. Build `GET /v1/commerce/products`.
8. Build `POST /v1/usage/check`.
9. Wire generation and export guards to backend routes.
10. Build purchase-attempt + transaction sync endpoints.
11. Build App Store notification ingestion.
12. Build restore flow.
13. Wire PDF export policy.

# 17. First-pass iOS implementation order

1. Add commerce models.
2. Add API client methods.
3. Build `EntitlementStore`.
4. Build `UsageMeterStore`.
5. Build StoreKit catalog service.
6. Build purchase coordinator.
7. Build `PaywallHostViewModel`.
8. Build `PaywallHostView`.
9. Build dashboard subscription card.
10. Add feature-gate coordinator to generation and quote flows.
11. Add restore purchases flow in Settings/paywall.
12. Add analytics hooks.

# 18. Non-negotiable implementation rules for the coding LLM

* Never put StoreKit purchase logic inside SwiftUI views.
* Never consume credits from the client without backend confirmation.
* Never infer export watermark state from UI; ask backend policy.
* Never use stringly-typed product IDs scattered across files.
* Never mix starter-credit logic with paid-subscription logic in one blob.
* Always comment commerce services and gate methods.
* Always keep paywall copy localized.
* Always keep purchase success path idempotent.

The next logical layer after this is the actual starter prompt for the coding LLM to begin with the backend commerce module and Prisma schema, followed by the SwiftUI commerce package.
