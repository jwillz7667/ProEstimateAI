Use this as the next implementation layer for the coding LLM. It is intentionally more concrete than the prior product spec, but still stops short of dumping large volumes of code.

Apple-side implementation assumptions for this design are: ProEstimate AI uses **auto-renewable subscriptions** in a single subscription group, a **StoreKit 2** purchase flow, **introductory free trial** eligibility managed by Apple at the subscription-group level, **appAccountToken** to associate purchases to your backend user/company, **Transaction.currentEntitlements** for current local entitlement reads, and **App Store Server API + App Store Server Notifications** for backend truth and lifecycle reconciliation. Billing Grace Period should be enabled so paid users can temporarily retain access during payment recovery. ([Apple Developer][1])

# 1. Subscription products and entitlement strategy

Create one App Store subscription group:

* `proestimate_pro`

Create two products inside it:

* `proestimate.pro.monthly`
* `proestimate.pro.annual`

Set the monthly product to have a 7-day introductory free trial. Because users can hold only one subscription per group at a time and introductory offer eligibility is tied to that subscription-group setup, this is the cleanest V1 structure. ([Apple Developer][2])

Keep the free starter allowance outside of Apple subscriptions. That means:

* Apple manages the 7-day trial eligibility and paid subscription lifecycle.
* Your backend manages the “3 free generations + 3 free quotes” allowance.

That separation prevents entitlement confusion and makes the logic auditable.

# 2. Monetization states

Use two parallel systems.

The first is **subscription entitlement state**:

* `FREE`
* `TRIAL_ACTIVE`
* `PRO_ACTIVE`
* `GRACE_PERIOD`
* `BILLING_RETRY`
* `CANCELED_ACTIVE`
* `EXPIRED`
* `REVOKED`

The second is **starter-credit state**:

* `ai_generation_remaining`
* `quote_export_remaining`

A user can be:

* Free with credits remaining
* Free with zero credits
* Trial active
* Pro active
* Grace period
* Expired with no remaining credits

Never collapse these into one boolean like `isPro`.

# 3. Exact backend schema additions

Below is the concrete schema layer to add on top of the earlier product schema.

## 3.1 Enums

Use these enums at the ORM/database layer.

```prisma
enum PlanCode {
  FREE_STARTER
  PRO_MONTHLY
  PRO_ANNUAL
}

enum EntitlementStatus {
  FREE
  TRIAL_ACTIVE
  PRO_ACTIVE
  GRACE_PERIOD
  BILLING_RETRY
  CANCELED_ACTIVE
  EXPIRED
  REVOKED
  ADMIN_OVERRIDE
}

enum UsageMetricCode {
  AI_GENERATION
  QUOTE_EXPORT
}

enum UsageResetPolicy {
  NEVER
  MONTHLY
  ANNUAL
}

enum SubscriptionEventType {
  INITIAL_PURCHASE
  TRIAL_STARTED
  RENEWED
  EXPIRED
  GRACE_PERIOD_ENTERED
  GRACE_PERIOD_RECOVERED
  BILLING_RETRY_ENTERED
  AUTO_RENEW_DISABLED
  AUTO_RENEW_ENABLED
  REFUNDED
  REVOKED
  RESTORED
  PRODUCT_CHANGED
  PRICE_CONSENT_REQUIRED
}

enum PurchaseAttemptStatus {
  STARTED
  COMPLETED
  CANCELED
  FAILED
  PENDING
  RESTORED
}
```

## 3.2 Prisma-ready models

```prisma
model Plan {
  id              String   @id @default(uuid())
  code            PlanCode @unique
  name            String
  platform        String
  billingType     String
  isActive        Boolean  @default(true)
  featuresJson    Json
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  subscriptionProducts SubscriptionProduct[]
  userEntitlements     UserEntitlement[]
}
```

```prisma
model SubscriptionProduct {
  id                     String   @id @default(uuid())
  planId                 String
  platform               String
  storeProductId         String   @unique
  subscriptionGroupId    String
  durationCode           String
  isIntroOfferEnabled    Boolean  @default(false)
  introOfferType         String?
  introOfferDisplayText  String?
  createdAt              DateTime @default(now())
  updatedAt              DateTime @updatedAt

  plan Plan @relation(fields: [planId], references: [id], onDelete: Cascade)
}
```

```prisma
model UserEntitlement {
  id                    String             @id @default(uuid())
  userId                String
  companyId             String
  planId                String
  entitlementStatus     EntitlementStatus
  startsAt              DateTime?
  endsAt                DateTime?
  gracePeriodEndsAt     DateTime?
  isAutoRenewEnabled    Boolean?
  source                String
  sourceReference       String?
  originalTransactionId String?
  latestTransactionId   String?
  environment           String?
  createdAt             DateTime           @default(now())
  updatedAt             DateTime           @updatedAt

  user    User    @relation(fields: [userId], references: [id], onDelete: Cascade)
  company Company @relation(fields: [companyId], references: [id], onDelete: Cascade)
  plan    Plan    @relation(fields: [planId], references: [id])

  @@index([userId, companyId])
  @@index([entitlementStatus])
}
```

```prisma
model SubscriptionEvent {
  id                    String                @id @default(uuid())
  userId                String
  companyId             String
  platform              String
  eventType             SubscriptionEventType
  storeProductId        String?
  originalTransactionId String?
  transactionId         String?
  appAccountToken       String?
  environment           String?
  effectiveAt           DateTime?
  payloadJson           Json
  createdAt             DateTime              @default(now())

  user    User    @relation(fields: [userId], references: [id], onDelete: Cascade)
  company Company @relation(fields: [companyId], references: [id], onDelete: Cascade)

  @@index([userId, companyId, createdAt])
  @@index([originalTransactionId])
}
```

```prisma
model UsageBucket {
  id               String           @id @default(uuid())
  userId           String
  companyId        String
  metricCode       UsageMetricCode
  includedQuantity Int
  consumedQuantity Int              @default(0)
  resetPolicy      UsageResetPolicy
  source           String
  createdAt        DateTime         @default(now())
  updatedAt        DateTime         @updatedAt

  user    User    @relation(fields: [userId], references: [id], onDelete: Cascade)
  company Company @relation(fields: [companyId], references: [id], onDelete: Cascade)

  @@unique([userId, companyId, metricCode, source])
  @@index([userId, companyId])
}
```

```prisma
model UsageEvent {
  id                String   @id @default(uuid())
  userId            String
  companyId         String
  projectId         String?
  metricCode        UsageMetricCode
  quantity          Int      @default(1)
  eventType         String
  source            String
  relatedEntityType String?
  relatedEntityId   String?
  metadataJson      Json?
  createdAt         DateTime @default(now())

  user    User    @relation(fields: [userId], references: [id], onDelete: Cascade)
  company Company @relation(fields: [companyId], references: [id], onDelete: Cascade)
  project Project? @relation(fields: [projectId], references: [id], onDelete: SetNull)

  @@index([userId, companyId, metricCode, createdAt])
}
```

```prisma
model PaywallImpression {
  id            String   @id @default(uuid())
  userId        String
  companyId     String
  placement     String
  triggerReason String
  projectId     String?
  shownVariant  String?
  createdAt     DateTime @default(now())

  user    User    @relation(fields: [userId], references: [id], onDelete: Cascade)
  company Company @relation(fields: [companyId], references: [id], onDelete: Cascade)
  project Project? @relation(fields: [projectId], references: [id], onDelete: SetNull)

  @@index([userId, companyId, createdAt])
}
```

```prisma
model PurchaseAttempt {
  id               String                @id @default(uuid())
  userId           String
  companyId        String
  platform         String
  storeProductId   String
  offerType        String?
  offerIdentifier  String?
  status           PurchaseAttemptStatus
  appAccountToken  String?
  metadataJson     Json?
  createdAt        DateTime              @default(now())
  updatedAt        DateTime              @updatedAt

  user    User    @relation(fields: [userId], references: [id], onDelete: Cascade)
  company Company @relation(fields: [companyId], references: [id], onDelete: Cascade)

  @@index([userId, companyId, createdAt])
}
```

## 3.3 Seed data

Seed these rows:

Plan seeds:

* `FREE_STARTER`
* `PRO_MONTHLY`
* `PRO_ANNUAL`

SubscriptionProduct seeds:

* `proestimate.pro.monthly` linked to `PRO_MONTHLY`
* `proestimate.pro.annual` linked to `PRO_ANNUAL`

Starter usage seeds for each new user/company:

* `AI_GENERATION` included 3, consumed 0, reset policy `NEVER`, source `free_starter`
* `QUOTE_EXPORT` included 3, consumed 0, reset policy `NEVER`, source `free_starter`

# 4. Backend services

The coding LLM should build these services as separate modules.

## 4.1 EntitlementService

Responsibilities:

* compute effective entitlement for a user/company
* read `UserEntitlement`
* resolve final access flags
* answer `canPerform(action)`

Key methods:

* `getEffectiveEntitlement(userId, companyId)`
* `syncFromVerifiedTransaction(payload)`
* `syncFromServerNotification(payload)`
* `reconcileFromAppStore(originalTransactionId)`
* `canGeneratePreview(userId, companyId)`
* `canExportQuote(userId, companyId)`
* `canCreateInvoice(userId, companyId)`
* `canExportWatermarkFree(userId, companyId)`

Rules:

* if `TRIAL_ACTIVE`, allow all Pro features
* if `PRO_ACTIVE`, allow all Pro features
* if `GRACE_PERIOD`, allow all Pro features but surface billing warning
* if `FREE`, fallback to usage buckets
* if `EXPIRED`, deny Pro features and fallback to free only if unused starter credits remain
* if `REVOKED`, immediately remove Pro features

## 4.2 UsageCreditService

Responsibilities:

* initialize starter credits
* atomically consume credits
* return remaining credits
* write audit trail into `UsageEvent`

Key methods:

* `initializeStarterCredits(userId, companyId)`
* `getUsageSummary(userId, companyId)`
* `consumeGenerationCredit(userId, companyId, projectId)`
* `consumeQuoteExportCredit(userId, companyId, projectId, proposalId)`
* `hasGenerationCreditsRemaining(userId, companyId)`
* `hasQuoteCreditsRemaining(userId, companyId)`

Important rule:
Credit consumption must be atomic and server-side. Do not decrement in the client.

## 4.3 CommerceSyncService

Responsibilities:

* accept verified StoreKit payload from app
* ingest App Store Server Notifications
* call App Store Server API when reconciliation is needed
* update `UserEntitlement`
* append `SubscriptionEvent`

Use the backend as the durable truth because Apple provides the server API and server notifications for lifecycle handling. ([Apple Developer][3])

## 4.4 PaywallService

Responsibilities:

* determine whether a paywall should be shown
* determine which paywall variant to show
* produce paywall copy model and CTA configuration
* log `PaywallImpression`

Methods:

* `evaluatePaywall(userId, companyId, action, projectId?)`
* `recordImpression(...)`
* `getPaywallConfig(locale, placement, triggerReason, isTrialEligible)`

## 4.5 WatermarkService

Responsibilities:

* decide whether PDF export must be watermarked
* inject watermark configuration into PDF rendering
* enforce free-plan export restrictions

Methods:

* `getExportBrandingPolicy(userId, companyId)`
* `shouldApplyWatermark(userId, companyId)`
* `getProposalExportPolicy(userId, companyId)`
* `getInvoiceExportPolicy(userId, companyId)`

# 5. Protected backend actions

These actions must call EntitlementService before doing any work:

* start generation job
* export proposal PDF
* create invoice
* export invoice PDF
* enable company branding on PDF
* create approval-share link
* export material links into document
* request high-resolution preview export

Decision logic:

`start generation`

* allow if Pro active
* else allow only if starter generation credits remain
* else block with hard paywall response

`export proposal PDF`

* allow if Pro active -> export unwatermarked/branded
* else allow only if starter quote credits remain -> export watermarked/unbranded
* else block with hard paywall response

`create invoice`

* Pro only

# 6. API contract additions

These are the exact backend endpoints the coding LLM should add.

## Commerce endpoints

`GET /v1/commerce/products`
Returns App Store product metadata as normalized app-facing models.

`GET /v1/commerce/entitlement`
Returns:

* effective entitlement state
* current plan
* trial eligibility flag from app-side cache or backend flag
* usage remaining
* feature flags

`POST /v1/commerce/purchase-attempt`
Creates a `PurchaseAttempt` before StoreKit purchase starts.
Body:

* `storeProductId`
* `offerType`
* `projectId?`

Returns:

* `purchaseAttemptId`
* `appAccountToken`

`POST /v1/commerce/transactions/sync`
Client sends verified purchase transaction snapshot after successful StoreKit purchase.
Body:

* `storeProductId`
* `transactionId`
* `originalTransactionId`
* `appAccountToken`
* `environment`
* `signedPayload?`
* `purchaseAttemptId?`

Returns:

* refreshed entitlement response

`POST /v1/commerce/restore`
Client asks backend to reconcile after restore.

`POST /v1/commerce/webhooks/app-store`
App Store Server Notifications endpoint.

## Usage endpoints

`GET /v1/usage`
Returns starter usage summary.

`POST /v1/usage/check`
Body:

* `action`
* `projectId?`
  Returns:
* `allowed`
* `reason`
* `paywallVariant?`
* `remainingCredits`
* `effectiveEntitlement`

# 7. StoreKit 2 architecture for SwiftUI

Build a dedicated commerce module in the iOS app.

Recommended folder structure:

* `Commerce/Models`
* `Commerce/Services`
* `Commerce/ViewModels`
* `Commerce/Views`
* `Commerce/StoreKit`
* `Commerce/Mocks` for tests only

Core types to implement:

* `StoreProductModel`
* `EntitlementSnapshot`
* `UsageSummary`
* `PaywallContext`
* `PurchaseResultModel`
* `CommerceFeatureGate`
* `SubscriptionState`

Core protocols:

* `StoreKitProductProvider`
* `PurchaseCoordinator`
* `CommerceAPIClient`
* `EntitlementStoreProtocol`

Concrete services:

* `StoreKitCatalogService`
* `StoreKitPurchaseCoordinator`
* `CommerceAPIService`
* `EntitlementStore`
* `UsageMeterStore`

## 7.1 StoreKitCatalogService

Responsibilities:

* load products using Apple product IDs
* map raw StoreKit `Product` to app-facing product models
* expose intro-offer flags and pricing display strings

## 7.2 StoreKitPurchaseCoordinator

Responsibilities:

* start purchase
* pass `.appAccountToken(UUID)` in `purchase(options:)`
* verify transaction result locally
* finish transaction when appropriate
* send purchase sync payload to backend

Apple documents that `appAccountToken(_:)` associates a UUID with the purchase and that the same token is returned in the resulting transaction, which is exactly what you want for mapping purchases to backend accounts. Apple also documents `purchase(options:)` as the method to call when a customer initiates purchase in-app. ([Apple Developer][4])

## 7.3 EntitlementStore

Responsibilities:

* load current entitlement from backend
* refresh local entitlements on app launch and foreground
* optionally inspect `Transaction.currentEntitlements` for instant local UX
* merge local StoreKit observations with backend entitlement snapshot

Apple documents `Transaction.currentEntitlements` as the latest transactions that entitle a customer to in-app purchases and subscriptions. Use it for immediate app responsiveness, but keep the backend as final authority. ([Apple Developer][5])

## 7.4 Purchase flow sequence

1. User taps Start Free Trial or Subscribe.
2. Client asks backend for `purchaseAttemptId` and `appAccountToken`.
3. Client calls StoreKit `purchase(options:)` with `.appAccountToken(...)`.
4. Purchase result returns.
5. Client verifies transaction locally.
6. Client posts transaction sync payload to backend.
7. Backend records `SubscriptionEvent`, updates `UserEntitlement`.
8. Client refreshes entitlement snapshot.
9. UI unlocks premium state.

## 7.5 Restore flow sequence

1. User taps Restore Purchases.
2. Client triggers StoreKit restore path.
3. Client refreshes local entitlements.
4. Client calls backend restore endpoint.
5. Backend reconciles via server state if needed.
6. Client refreshes entitlement snapshot again.

## 7.6 Foreground refresh rules

On app foreground:

* refresh local StoreKit entitlements
* refresh backend entitlement snapshot if stale
* update dashboard usage/subscription card
* if state is `GRACE_PERIOD`, surface billing warning banner

# 8. SwiftUI paywall architecture

## 8.1 Paywall screen tree

Use this screen tree.

`PaywallHostView`

* owns presentation shell
* takes `PaywallContext`

Inside it:

`PaywallBackgroundView`

* blurred room/project image or branded abstract gradient
* black/orange glass styling

`PaywallHeaderView`

* title
* subtitle
* trust row
* dismiss button if allowed

`PlanSelectorView`

* segmented monthly/annual selector
* trial badge display
* savings badge

`FeatureComparisonListView`

* unlimited previews
* unlimited quotes
* remove watermark
* branded PDFs
* invoices
* material links

`FreeUsageMeterView`

* shows remaining free starter credits
* only visible on free state

`PrimaryPurchaseCTAView`

* “Start Free Trial” or “Subscribe Now”

`SecondaryActionsView`

* Continue Free
* Restore Purchases
* Terms / Privacy

`PaywallFooterLegalView`

* renewal language
* billing disclosure
* cancel-anytime language

## 8.2 View models

### `PaywallHostViewModel`

Responsibilities:

* load paywall config
* hold selected plan
* know current context
* handle CTA taps
* log impression

Inputs:

* `PaywallContext`
* `EntitlementSnapshot`
* `UsageSummary`

Outputs:

* headline
* subheadline
* selected plan
* available products
* CTA title
* canDismiss
* showContinueFree
* feature rows
* remaining usage text

### `PlanSelectorViewModel`

Responsibilities:

* map available products into monthly/annual cards
* pick default selected plan
* expose “trial available” label

### `PurchaseCTAViewModel`

Responsibilities:

* build CTA text
* show purchase state
* disable while purchasing
* expose post-purchase success action

### `FreeUsageMeterViewModel`

Responsibilities:

* show remaining generations
* show remaining quote exports
* show urgency copy as credits get low

# 9. Paywall placements

Implement these placements as enum-backed contexts.

* `onboarding_soft_gate`
* `post_first_generation`
* `post_first_quote_export`
* `generation_limit_hit`
* `quote_limit_hit`
* `invoice_locked`
* `branding_locked`
* `approval_share_locked`
* `watermark_removal_locked`
* `settings_upgrade`

Each placement should be configurable so copy can evolve without rewriting view logic.

# 10. Free-trial and starter-credit UX rules

The free starter allowance and App Store free trial should be shown together, but explained separately.

Recommended copy model:

Primary:

* “Start your 7-day Pro trial”

Secondary:

* “Or keep exploring with 3 free AI previews and 3 watermarked quotes.”

Do not frame the free starter credits as the same thing as the Apple trial.

# 11. Watermarked export flow

For free users:

1. User taps Export Quote.
2. Backend checks starter quote credits.
3. If remaining, consume one quote credit atomically.
4. Backend generates proposal PDF with:

   * watermark enabled
   * no custom branding
   * no approval CTA
   * optional limited material links
5. Export succeeds.

For Pro users:

1. User taps Export Quote.
2. No quote-credit consumption.
3. Backend generates full branded PDF.
4. Share link and approval workflow enabled.

Watermarking must happen only on the server-side render path, never as a client-only overlay.

# 12. Dashboard subscription and usage card

Implement a single glassy dashboard card component with two modes.

## Free mode

Show:

* `AI Previews: 2/3 left`
* `Quotes: 1/3 left`
* CTA: `Start Free Trial`

## Trial mode

Show:

* `Pro Trial Active`
* `Ends in X days`
* CTA: `Manage Plan`

## Active paid mode

Show:

* `Pro Active`
* renewal status if known

## Grace period mode

Show:

* `Billing issue detected`
* `You still have access while Apple retries payment`
* CTA: `Manage Subscription`

Billing Grace Period allows continued access while Apple attempts to recover payment, but your app must still inspect renewal status and entitlements correctly. ([Apple Developer][6])

# 13. App Store Server notification handling

Build an ingestion layer that:

* validates and parses notification payloads
* maps them into normalized `SubscriptionEvent`s
* updates `UserEntitlement`
* emits internal analytics events
* triggers user-facing refresh jobs if needed

At minimum handle:

* initial buy
* renewal
* expiration
* billing retry
* grace period entry/recovery
* auto-renew status changes
* refund/revocation

Apple’s server notifications cover purchases, renewals, offer redemptions, refunds, and related lifecycle events, so this is the right webhook mechanism for backend state changes. ([Apple Developer][7])

# 14. Coding-LLM implementation rules for this subsystem

The coding LLM must:

1. Keep StoreKit code isolated from views.
2. Keep backend entitlement logic isolated from controller routes.
3. Use transactional DB updates when consuming starter credits.
4. Never decrement credits in UI-only logic.
5. Comment every commerce service and every major method.
6. Make all product IDs and plan codes centrally configurable.
7. Localize all paywall text.
8. Test free starter, trial, active, expired, and grace-period paths.
9. Ensure every protected backend route calls entitlement checks.
10. Keep analytics logging non-blocking.

# 15. Suggested file layout

## iOS

* `Commerce/Models/StoreProductModel.swift`
* `Commerce/Models/EntitlementSnapshot.swift`
* `Commerce/Models/UsageSummary.swift`
* `Commerce/Services/StoreKitCatalogService.swift`
* `Commerce/Services/StoreKitPurchaseCoordinator.swift`
* `Commerce/Services/EntitlementStore.swift`
* `Commerce/Services/UsageMeterStore.swift`
* `Commerce/ViewModels/PaywallHostViewModel.swift`
* `Commerce/ViewModels/PlanSelectorViewModel.swift`
* `Commerce/ViewModels/PurchaseCTAViewModel.swift`
* `Commerce/ViewModels/FreeUsageMeterViewModel.swift`
* `Commerce/Views/PaywallHostView.swift`
* `Commerce/Views/PlanSelectorView.swift`
* `Commerce/Views/FeatureComparisonListView.swift`
* `Commerce/Views/FreeUsageMeterView.swift`

## Backend

* `src/modules/commerce/commerce.controller.ts`
* `src/modules/commerce/commerce.service.ts`
* `src/modules/commerce/storekit-sync.service.ts`
* `src/modules/commerce/entitlement.service.ts`
* `src/modules/commerce/usage-credit.service.ts`
* `src/modules/commerce/paywall.service.ts`
* `src/modules/commerce/watermark.service.ts`
* `src/modules/commerce/dto/*`
* `src/modules/commerce/repositories/*`
* `src/modules/commerce/tests/*`

# 16. Immediate next build step

Build this in order:

1. Add Prisma models and migrations.
2. Seed plans and products.
3. Implement backend entitlement and usage services.
4. Build `GET /v1/commerce/entitlement`.
5. Build StoreKit catalog + purchase coordinator in iOS.
6. Build the paywall UI shell.
7. Wire generation/export routes to entitlement checks.
8. Add server-side watermark policy into proposal PDF export.

Next, I can generate the exact DTOs, endpoint request/response shapes, and the SwiftUI class/protocol skeletons for the commerce module.

[1]: https://developer.apple.com/app-store/subscriptions/?utm_source=chatgpt.com "Auto-renewable Subscriptions - App Store"
[2]: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/?utm_source=chatgpt.com "Offer auto-renewable subscriptions"
[3]: https://developer.apple.com/documentation/appstoreserverapi?utm_source=chatgpt.com "App Store Server API | Apple Developer Documentation"
[4]: https://developer.apple.com/documentation/storekit/product/purchaseoption/appaccounttoken%28_%3A%29?utm_source=chatgpt.com "appAccountToken(_:) | Apple Developer Documentation"
[5]: https://developer.apple.com/documentation/storekit/transaction/currententitlements?utm_source=chatgpt.com "currentEntitlements | Apple Developer Documentation"
[6]: https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions/?utm_source=chatgpt.com "Enable billing grace period for auto-renewable subscriptions"
[7]: https://developer.apple.com/documentation/appstoreservernotifications?utm_source=chatgpt.com "App Store Server Notifications"
