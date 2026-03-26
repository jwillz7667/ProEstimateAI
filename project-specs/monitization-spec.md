Below is the monetization spec for **ProEstimate AI**. It is written so a coding LLM can implement the paywall, usage gating, subscription state, free usage credits, and free-trial flow cleanly.

For iOS, the paid layer should use **StoreKit 2 auto-renewable subscriptions**. Apple describes auto-renewable subscriptions as the correct model for ongoing access to premium content, services, or features, and StoreKit 2 as the current purchase framework for Apple platforms. Users can only hold one active subscription product per subscription group at a time, and introductory offers such as free trials are limited to eligible users, with one introductory offer redemption per subscription group. Use the **App Store Server API** and App Store Server Notifications to keep backend entitlements in sync, and enable **Billing Grace Period** so temporary payment issues do not immediately cut off paid access. ([Apple Developer][1])

# 1. Monetization model

Use a three-layer model.

**Layer 1: Free starter usage**
Every new account gets:

* 3 free AI generations
* 3 free quote/proposal exports
* exported PDFs are watermarked
* no branded exports
* no client approval links without watermark
* no unlimited estimate history

This is **app-managed usage**, not an App Store trial.

**Layer 2: Pro subscription**
Unlocks:

* unlimited generations, subject to fair-use/rate limits
* unlimited quotes and proposals
* no watermark
* branded PDFs
* branded proposal share pages
* proposal approval workflow
* invoice generation/export
* higher image resolution
* project version history
* material links in final exports
* bilingual document templates

**Layer 3: free trial on Pro**
Recommended:

* 7-day free trial on the monthly plan
* optionally also on annual, but only if pricing strategy supports it

This is the **App Store introductory offer**, not the same thing as the 3 free starter uses. Apple’s introductory offers can be configured as free trials for eligible new subscribers, and eligibility is tied to the subscription group. ([Apple Developer][2])

# 2. Recommended product lineup in App Store Connect

Create one subscription group:

**Subscription group**

* `proestimate_pro`

Inside that group create:

**Product 1**

* `proestimate.pro.monthly`

**Product 2**

* `proestimate.pro.annual`

Reasoning:

* one active subscription per group
* clean upgrade/downgrade behavior
* shared entitlement logic
* shared introductory-offer eligibility at the group level ([Apple Developer][3])

Recommended introductory offer:

* 7-day free trial on monthly
* keep annual as a price-anchoring option
* test whether annual should also have a trial later

Recommended later:

* add win-back offers only after churn data exists. Apple supports win-back offers, but they are a second-phase optimization, not a V1 requirement. ([Apple Developer][4])

# 3. Entitlement model

The backend should not treat “subscription” and “usage credits” as the same thing.

Use these entitlement states:

* `free_starter`
* `trial_active`
* `pro_active`
* `grace_period`
* `billing_retry`
* `expired`
* `canceled_but_active_until_end`
* `lifetime_admin_override` only if needed internally

Use these capability flags:

* `can_generate_preview`
* `can_export_pdf`
* `can_remove_watermark`
* `can_use_branding`
* `can_create_invoice`
* `can_share_client_link`
* `can_use_material_links`
* `can_access_project_history`
* `can_use_high_res_generation`

Free users are governed by **remaining credits**. Paid users are governed by **subscription state**.

# 4. Exact free-tier rules

New users get:

* `free_generation_credits_total = 3`
* `free_quote_credits_total = 3`

Consumption rules:

* one generation credit is burned when a generation job is successfully started
* one quote credit is burned when a proposal/quote PDF is successfully generated for export
* simple edits to a saved estimate do not consume a quote credit until export
* invoice generation should be Pro-only
* every free PDF includes watermark
* every free share page displays watermark/banner
* free users can still view projects they created

Watermark text:

* “Created with ProEstimate AI”
* keep it tasteful but obvious
* include on every page footer and diagonally on cover/hero if desired

Recommended free restrictions:

* no custom logo on PDF
* no invoice export
* no approval workflow
* no branded colors in exported documents
* material links shown in app only, not exported, unless subscribed

# 5. Recommended paywall strategy

Do not show one generic paywall. Use three gate types.

## Gate A: soft onboarding paywall

Shown after account creation and after first successful preview generation.

Goal:

* explain value
* show free usage meter
* let the user continue on free plan

CTA stack:

* Start 7-Day Free Trial
* Continue with 3 Free Generations
* Restore Purchases

This gate is informational, not hard-blocking.

## Gate B: action-trigger paywall

Shown when the user tries to:

* export branded proposal
* remove watermark
* create invoice
* share client approval page
* generate a 4th preview
* export a 4th quote/proposal

This is the main monetization gate.

## Gate C: exhausted-credits hard paywall

Shown when:

* `free_generation_credits_remaining == 0` and user taps Generate
* `free_quote_credits_remaining == 0` and user taps Export Quote

This gate should block the action until:

* they subscribe
* or they restore an active entitlement

# 6. Subscription flow

## First-time user flow

1. User signs up.
2. Backend creates account and free starter entitlements.
3. Dashboard shows usage card:

   * 3/3 generations
   * 3/3 quotes
4. User can complete core workflow without paying immediately.
5. After first strong aha moment, show soft paywall.

## Trial start flow

1. User taps Start Free Trial from any paywall.
2. App loads StoreKit products.
3. App displays monthly and annual pricing.
4. Monthly shows “7-day free trial” badge if eligible.
5. User completes purchase with StoreKit 2.
6. Client immediately verifies transaction locally.
7. Client sends transaction data to backend.
8. Backend validates and records subscription state.
9. Entitlement flips to `trial_active`.
10. UI unlocks premium features instantly.

## Paid conversion flow

1. Trial expires.
2. Apple renews to paid monthly unless canceled.
3. Backend receives updated status from App Store Server API / notifications.
4. Entitlement flips from `trial_active` to `pro_active`.
5. No disruption in feature access. ([Apple Developer][5])

## Grace period flow

1. Renewal fails due to payment issue.
2. If Billing Grace Period is enabled, keep premium access active temporarily.
3. Backend marks state as `grace_period`.
4. UI can show subtle billing warning banner in Settings, not a blocking paywall.
5. If recovery succeeds, state returns to `pro_active`.
6. If recovery fails, transition to `expired`. ([Apple Developer][6])

## Expiration flow

1. Subscription expires or billing recovery fails.
2. Premium access ends.
3. User keeps existing projects and documents.
4. Editing/exporting premium features re-locks.
5. Existing branded exports remain stored.
6. New exports revert to free restrictions only if free credits remain; otherwise hard paywall.

## Restore purchases flow

1. User taps Restore Purchases.
2. App refreshes StoreKit transaction state.
3. App syncs with backend.
4. Backend recalculates entitlement from verified purchase state.
5. UI updates accordingly.

# 7. Paywall screen spec

The paywall must look premium and native, consistent with the rest of the app.

## Visual direction

* dark glass sheet over blurred project imagery
* black/orange theme
* strong primary CTA
* minimal clutter
* pricing cards with soft depth
* monthly/annual segmented toggle
* visible “3 free generations + 3 free quotes” starter message
* clean legal footer

## Content hierarchy

Top headline:

* “Win more jobs in minutes”

Subheadline:

* “Create AI remodel previews, polished quotes, and branded proposals.”

Feature bullets:

* Unlimited AI previews
* Unlimited quotes and exports
* No watermark
* Branded PDFs and proposals
* Client-ready invoices
* Material links included

Trust row:

* 7-day free trial
* Cancel anytime
* Restore purchases

Secondary info:

* “Free plan includes 3 generations and 3 quote exports with watermark.”

## Price cards

Monthly card:

* “Pro Monthly”
* price
* “7-day free trial” badge if eligible

Annual card:

* “Pro Annual”
* annual price
* savings badge
* no trial or trial depending configuration

CTA text:

* if eligible: “Start Free Trial”
* if not eligible: “Subscribe Now”

Secondary buttons:

* Continue Free
* Restore Purchases

# 8. Recommended gating copy

## Soft gate

“You still have 3 free generations and 3 quote exports. Upgrade now to remove watermarks, unlock invoices, and create unlimited proposals.”

## Hard gate for 4th generation

“You’ve used all 3 free AI previews. Start your free trial to keep generating remodel previews.”

## Hard gate for quote export

“You’ve used all 3 free quote exports. Upgrade to create unlimited branded proposals and invoices.”

## Watermark upsell

“Remove watermark and add your branding with Pro.”

# 9. Subscription state machine

Use this state machine in backend and client.

States:

* `free`
* `trial_active`
* `active`
* `grace_period`
* `billing_retry`
* `expired`
* `revoked`

Transitions:

* free -> trial_active
* trial_active -> active
* trial_active -> expired if canceled before paid renewal and trial ends
* active -> grace_period
* grace_period -> active
* grace_period -> expired
* active -> canceled_but_active_until_end
* canceled_but_active_until_end -> expired
* any active-like state -> revoked if Apple revokes/refunds transaction

Apple exposes subscription status information through StoreKit and the App Store Server API, including subscription group status and renewal information, and recommends using server APIs to keep server state current. ([Apple Developer][7])

# 10. Backend enforcement rules

The backend is the source of truth for entitlements.

Rules:

* do not trust only the client for paid access
* verify StoreKit transaction information on the backend
* persist normalized subscription state
* persist free-usage counters separately
* every protected action checks entitlements before execution

Protected backend actions:

* create generation job if no credits and no subscription
* export unwatermarked PDF
* attach branding to PDF
* create invoice
* create client approval share page
* export material links into final document
* access high-res generation route

The client can optimistically present UI, but the backend must enforce access.

# 11. Database schema additions for monetization

Add these tables to the existing schema.

## Table: plans

Fields:

* id UUID primary key
* code TEXT unique not null
* name TEXT not null
* platform TEXT not null
* billing_type TEXT not null
* is_active BOOLEAN not null default true
* features_json JSONB not null
* created_at TIMESTAMPTZ not null default now()
* updated_at TIMESTAMPTZ not null default now()

Seed examples:

* `free_starter`
* `pro_monthly`
* `pro_annual`

## Table: subscription_products

Fields:

* id UUID primary key
* plan_id UUID not null references plans(id)
* platform TEXT not null
* store_product_id TEXT unique not null
* subscription_group_id TEXT not null
* duration_code TEXT not null
* is_intro_offer_enabled BOOLEAN not null default false
* intro_offer_type TEXT nullable
* intro_offer_display_text TEXT nullable
* created_at TIMESTAMPTZ not null default now()
* updated_at TIMESTAMPTZ not null default now()

Examples:

* `proestimate.pro.monthly`
* `proestimate.pro.annual`

## Table: user_entitlements

Fields:

* id UUID primary key
* user_id UUID not null references users(id)
* company_id UUID not null references companies(id)
* plan_id UUID not null references plans(id)
* entitlement_status TEXT not null
* starts_at TIMESTAMPTZ nullable
* ends_at TIMESTAMPTZ nullable
* source TEXT not null
* source_reference TEXT nullable
* grace_period_ends_at TIMESTAMPTZ nullable
* is_auto_renew_enabled BOOLEAN nullable
* created_at TIMESTAMPTZ not null default now()
* updated_at TIMESTAMPTZ not null default now()

Notes:

* store the current effective entitlement row
* can keep one active row plus history, or version history in separate table

## Table: subscription_events

Fields:

* id UUID primary key
* user_id UUID not null references users(id)
* company_id UUID not null references companies(id)
* platform TEXT not null
* event_type TEXT not null
* store_product_id TEXT nullable
* original_transaction_id TEXT nullable
* transaction_id TEXT nullable
* environment TEXT nullable
* effective_at TIMESTAMPTZ nullable
* payload_json JSONB not null
* created_at TIMESTAMPTZ not null default now()

Use for:

* initial purchase
* trial start
* renewals
* expiration
* grace period start
* billing retry
* refund/revocation
* restore

## Table: usage_buckets

Fields:

* id UUID primary key
* user_id UUID not null references users(id)
* company_id UUID not null references companies(id)
* metric_code TEXT not null
* included_quantity INT not null default 0
* consumed_quantity INT not null default 0
* reset_policy TEXT not null
* source TEXT not null
* created_at TIMESTAMPTZ not null default now()
* updated_at TIMESTAMPTZ not null default now()
  Constraints:
* unique(user_id, company_id, metric_code, source)

Seed rows for free starter:

* metric_code = `ai_generation`

* included_quantity = 3

* consumed_quantity = 0

* reset_policy = `never`

* source = `free_starter`

* metric_code = `quote_export`

* included_quantity = 3

* consumed_quantity = 0

* reset_policy = `never`

* source = `free_starter`

## Table: usage_events

Fields:

* id UUID primary key
* user_id UUID not null references users(id)
* company_id UUID not null references companies(id)
* project_id UUID nullable references projects(id)
* metric_code TEXT not null
* quantity INT not null default 1
* event_type TEXT not null
* source TEXT not null
* related_entity_type TEXT nullable
* related_entity_id UUID nullable
* metadata_json JSONB nullable
* created_at TIMESTAMPTZ not null default now()

## Table: paywall_impressions

Fields:

* id UUID primary key
* user_id UUID not null references users(id)
* company_id UUID not null references companies(id)
* placement TEXT not null
* trigger_reason TEXT not null
* project_id UUID nullable references projects(id)
* shown_variant TEXT nullable
* created_at TIMESTAMPTZ not null default now()

## Table: purchase_attempts

Fields:

* id UUID primary key
* user_id UUID not null references users(id)
* company_id UUID not null references companies(id)
* platform TEXT not null
* store_product_id TEXT not null
* offer_type TEXT nullable
* offer_identifier TEXT nullable
* status TEXT not null
* app_account_token TEXT nullable
* metadata_json JSONB nullable
* created_at TIMESTAMPTZ not null default now()
* updated_at TIMESTAMPTZ not null default now()

# 12. Feature gating matrix

Free Starter:

* 3 AI previews: yes
* 3 quote/proposal exports: yes
* watermark-free PDF: no
* branded PDF/logo/colors: no
* invoice creation: no
* client approval share page: no
* material links in exported doc: no
* high-res preview export: no
* estimate editing: yes
* project storage: yes, limited if desired

Trial / Pro:

* unlimited AI previews: yes
* unlimited quote/proposal exports: yes
* watermark-free PDF: yes
* branded PDF/logo/colors: yes
* invoice creation: yes
* client approval share page: yes
* material links in exported doc: yes
* project history: yes
* higher-res preview export: yes

# 13. StoreKit 2 implementation requirements

Use StoreKit 2 on iOS. Apple positions StoreKit 2 as the modern API layer for in-app purchases and subscriptions across Apple platforms. ([Apple Developer][8])

Implementation requirements:

* fetch products on launch of paywall
* handle purchase result states cleanly
* verify current entitlements locally for immediate UX
* sync verified purchase state to backend
* support Restore Purchases
* handle subscription status refresh on app foreground
* keep purchase and entitlement code isolated in a dedicated commerce module

Recommended app modules:

* `CommerceStore`
* `SubscriptionService`
* `EntitlementStore`
* `PaywallViewModel`
* `UsageMeterViewModel`

# 14. App Store Server integration requirements

Backend should use App Store Server API / notifications for durable subscription state. Apple explicitly provides the App Store Server API to retrieve current subscription statuses, and server notifications to keep backend state synchronized. ([Apple Developer][5])

Backend responsibilities:

* map user to app account token or equivalent identifier
* ingest server notifications
* reconcile subscription state from server API when needed
* update `user_entitlements`
* append immutable `subscription_events`
* handle refunds/revocations
* keep audit trail

# 15. PDF watermark rules

For free exports:

* apply watermark on every page
* show footer badge “Created with ProEstimate AI”
* disable custom logo and brand colors
* proposal share page should display top banner indicating free version

For paid exports:

* no watermark
* use company logo
* use company colors
* allow material links
* allow client approval controls

# 16. Dashboard and usage UI

Dashboard should include a compact usage card near the top.

Card content for free users:

* `AI Previews: 2 of 3 remaining`
* `Quote Exports: 1 of 3 remaining`
* small upsell text
* CTA: `Start Free Trial`

Card content for subscribed users:

* `Pro Active`
* renewal state if appropriate
* billing issue warning only if in grace period
* CTA: `Manage Subscription`

This card should be visually calm and glassy, with orange progress accents.

# 17. Paywall triggers

Trigger soft paywall:

* after first successful preview generation
* after first successful quote export with watermark

Trigger hard paywall:

* before 4th generation
* before 4th quote export
* when trying to create invoice on free plan
* when trying to remove watermark
* when trying to enable branding
* when trying to share a client approval page

# 18. Coding-LLM build instructions

When implementing this subsystem, the coding LLM must:

1. Create a dedicated monetization domain across iOS client and backend.
2. Separate free usage accounting from subscription entitlement accounting.
3. Never hardcode pricing or product ids in view files.
4. Put StoreKit code behind a clean abstraction.
5. Put paywall copy and feature lists in localized resources.
6. Comment every major purchase and entitlement function.
7. Log paywall impressions, purchase attempts, restores, and conversion events.
8. Ensure all premium-protected backend routes verify entitlements server-side.
9. Keep watermarking logic centralized in PDF rendering layer.
10. Make paywall placements configurable so copy and experiments can evolve.

# 19. Recommended first implementation order

First, add DB tables and seed plans/products.

Second, implement backend usage-credit service and entitlement service.

Third, implement StoreKit product loading and purchase flow in iOS.

Fourth, implement paywall UI and trigger logic.

Fifth, implement PDF watermark logic.

Sixth, implement backend subscription reconciliation and restore flow.

Seventh, add analytics and experiments.

# 20. Final recommendation

Use this exact monetization structure:

* **Free Starter:** 3 generations + 3 quote exports, watermarked
* **Pro Monthly:** 7-day free trial, then auto-renew
* **Pro Annual:** discounted annual plan
* **Backend-enforced entitlements**
* **StoreKit 2 + App Store Server API**
* **Billing Grace Period enabled**
* **Win-back offers later, not at launch** ([Apple Developer][6])

If you want, I can turn this into the next layer: exact backend tables as SQL/Prisma, the StoreKit 2 purchase architecture for SwiftUI, and the paywall screen tree with view models.

[1]: https://developer.apple.com/app-store/subscriptions/?utm_source=chatgpt.com "Auto-renewable Subscriptions - App Store"
[2]: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/?utm_source=chatgpt.com "Set up introductory offers for auto-renewable subscriptions"
[3]: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/?utm_source=chatgpt.com "Offer auto-renewable subscriptions"
[4]: https://developer.apple.com/documentation/storekit/supporting-win-back-offers-in-your-app?utm_source=chatgpt.com "Supporting win-back offers in your app"
[5]: https://developer.apple.com/documentation/appstoreserverapi?utm_source=chatgpt.com "App Store Server API | Apple Developer Documentation"
[6]: https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions/?utm_source=chatgpt.com "Enable billing grace period for auto-renewable subscriptions"
[7]: https://developer.apple.com/documentation/storekit/transaction/subscriptionstatus?utm_source=chatgpt.com "subscriptionStatus | Apple Developer Documentation"
[8]: https://developer.apple.com/storekit/?utm_source=chatgpt.com "StoreKit 2"
