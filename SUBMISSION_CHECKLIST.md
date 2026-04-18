# App Store Submission Checklist

Everything needed to get ProEstimate AI through App Store review, organized by where the work lives.

- Bundle ID: `Res.ProEstimate-AI`
- Team ID: `487LC4H9U4`
- Deployment target: iOS 26.4
- Device families: iPhone + iPad
- Entity: Viral Ventures LLC (Minnesota)

---

## 0. What this audit already fixed in the repo

All of the following are committed or staged, verified by `xcodebuild`:

- [x] Added `LSApplicationCategoryType = public.app-category.business` to Info.plist so the App Store category doesn't fall back to Utilities.
- [x] Removed the empty `com.apple.developer.in-app-payments` entitlement. That key is Apple Pay for merchants; StoreKit 2 subscriptions don't need an entitlement. Leaving it empty can confuse code-signing and has no benefit.
- [x] Added Spanish localizations for the three privacy usage descriptions in `InfoPlist.xcstrings` (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`). Previously English-only even though the app ships bilingual copy everywhere else.
- [x] Expanded `PrivacyInfo.xcprivacy` to declare three more collected data types that the app actually handles through Client records and project content:
  - `NSPrivacyCollectedDataTypePhoneNumber` (client phone numbers)
  - `NSPrivacyCollectedDataTypePhysicalAddress` (client addresses, company address)
  - `NSPrivacyCollectedDataTypeOtherUserContent` (project notes, estimate notes, descriptions)

---

## 1. Decisions to make before you submit

These are things I flagged but did not change on my own.

### 1a. Interface style override

`Info.plist` has `UIUserInterfaceStyle = Light`. Every UI surface in the app is dark-mode designed (Apple Liquid Glass on a dark palette, `#FF9230` accent). When a user in Dark mode launches the current build, iOS will force the dark-designed UI into a light shell, which mangles contrast and readability.

Three options:
- Change to `Dark` — what the design clearly intends. The app will always render in dark mode regardless of system setting. Recommended.
- Remove the key entirely — the app will follow system preference. Only do this if you actually plan to add light-mode styling.
- Keep as `Light` — only valid if you're about to ship a light-mode palette.

### 1b. Build number bump

Currently `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1`. Every TestFlight and App Store upload requires `CURRENT_PROJECT_VERSION` to be strictly greater than any previous upload for the same `MARKETING_VERSION`. If you have already pushed a build 1 to TestFlight, bump to 2 before archiving.

Xcode → Target → General → Identity → Build field.

### 1c. App Icon review

`Assets.xcassets/AppIcon.appiconset` has the three required variants (Default, Dark, TintedLight) at 1024×1024 — the modern iOS 18+ single-size format. Confirm the art you have there is the final production icon, not a placeholder. The file names all say `house2-iOS-*` which suggests they may be iteration artwork.

---

## 2. Xcode-side pre-flight

Complete before you archive:

- [ ] **Signing** — Xcode → Signing & Capabilities → Team: Viral Ventures LLC. Verify "Automatically manage signing" is on and shows a valid provisioning profile.
- [ ] **Capabilities** — Only Sign in with Apple should be enabled. Other entitlements (push, app groups, iCloud, associated domains) should be off unless you plan to use them.
- [ ] **Bump build number** (see 1b).
- [ ] **Pick production scheme** — the "ProEstimate AI" scheme with Release configuration.
- [ ] **Verify Privacy Manifest** — Xcode will warn during archive if any third-party SDKs require privacy manifests you haven't declared. Address warnings before shipping.
- [ ] **Remove console noise** — no `print` or `NSLog` calls in production code paths; `os.Logger` is preferred but be careful with what you log (no user content, no tokens).
- [ ] **Archive for App Store** — Product → Archive (must use a real device or "Any iOS Device" destination, not a simulator).

After archive succeeds, Organizer will offer Distribute → App Store Connect. Upload and wait for the build to finish processing (5–30 min).

---

## 3. App Store Connect — first-time app setup

Open [App Store Connect](https://appstoreconnect.apple.com) → My Apps → plus button → New App.

- [ ] **Platform:** iOS
- [ ] **Name:** ProEstimate AI (30 char max, exact match on App Store)
- [ ] **Primary Language:** English (US)
- [ ] **Bundle ID:** `Res.ProEstimate-AI` (must already be registered in your developer account)
- [ ] **SKU:** any unique string, e.g. `proestimate-ios-1`
- [ ] **User Access:** Full access

---

## 4. App Information (left sidebar → App Information)

- [ ] **Category:** Primary **Business**, Secondary **Productivity**
- [ ] **Content Rights:** "Does this app contain, show, or access third-party content?" — **No** (AI renders are first-party; user-uploaded photos belong to the user)
- [ ] **Age Rating:** Answer the questionnaire. Expected outcome: **4+**
  - No cartoon/realistic violence
  - No sexual content
  - No profanity
  - No horror/fear themes
  - No gambling
  - Unrestricted web access: **No** (the app browses only your own domain for proposal shares)
- [ ] **Privacy Policy URL:** `https://proestimateai.com/privacy`
- [ ] **License Agreement:** EULA — use Apple's Standard EULA or paste `LICENSE`-based EULA
- [ ] **Copyright:** `2026 Viral Ventures LLC`
- [ ] **Routing App Coverage File:** not applicable
- [ ] **Trade representative contact:** fill in if you want Korea support

---

## 5. Pricing and Availability

- [ ] **Price:** Free
- [ ] **Availability:** All territories (or pick specific ones)
- [ ] **Availability start:** immediately
- [ ] **Tax Category:** Standard iOS Application

Volume purchase, B2B, etc. — leave default unless you specifically want those.

---

## 6. App Privacy (left sidebar → App Privacy)

This section must match `PrivacyInfo.xcprivacy` or Apple will reject. The manifest says:

- [ ] **Tracking:** No (no third-party tracking SDKs, no IDFA)
- [ ] **Data Collected:** declare each, all linked to the user's identity, none used for tracking:
  - Contact Info → **Email Address** — purposes: App Functionality, Account Management
  - Contact Info → **Name** — purposes: App Functionality, Account Management
  - Contact Info → **Phone Number** — purposes: App Functionality
  - Contact Info → **Physical Address** — purposes: App Functionality
  - User Content → **Photos or Videos** — purposes: App Functionality
  - User Content → **Other User Content** — purposes: App Functionality
  - User Content → **Customer Support** — purposes: Customer Support
  - Purchases → **Purchase History** — purposes: App Functionality

---

## 7. Subscriptions (left sidebar → Monetization → Subscriptions)

The StoreKit config file in the repo mirrors what you need here.

### 7a. Subscription Group

- [ ] Create group: **ProEstimate Pro** (reference name)
- [ ] App Store Localizations: add a group display name and level description in:
  - English (U.S.) — Display: `ProEstimate Pro` — Description: `Unlock unlimited AI previews, quotes, invoices, and branding.`
  - Spanish (Mexico) — Display: `ProEstimate Pro` — Description: `Desbloquea previsualizaciones AI ilimitadas, cotizaciones, facturas y marca.`
- [ ] Add image for the group (1024×1024, transparent or branded).

### 7b. Pro Monthly

- [ ] **Reference Name:** Pro Monthly
- [ ] **Product ID:** `proestimate.pro.monthly` (must match the StoreKit config exactly)
- [ ] **Subscription Duration:** 1 Month
- [ ] **Price:** $19.99 USD — Apple will generate other tiers automatically
- [ ] **Family Sharing:** off
- [ ] **Localizations** (en + es, copy from the StoreKit file):
  - en — Display: `Pro Monthly` — Description: `Full access to all Pro features, billed monthly`
  - es — Display: `Pro Mensual` — Description: `Acceso completo a todas las funciones Pro, facturado mensualmente`
- [ ] **Review screenshot:** one screenshot showing the paywall (use the asset at `.github/assets/readme/paywall.png`)
- [ ] **Review notes:** short explanation of what Pro unlocks

### 7c. Pro Annual

- [ ] **Reference Name:** Pro Annual
- [ ] **Product ID:** `proestimate.pro.annual`
- [ ] **Subscription Duration:** 1 Year
- [ ] **Price:** $149.99 USD (37% off vs. monthly)
- [ ] **Family Sharing:** off
- [ ] **Localizations:**
  - en — Display: `Pro Annual` — Description: `Full access to all Pro features, billed annually — save 37%`
  - es — Display: `Pro Anual` — Description: `Acceso completo a todas las funciones Pro, facturado anualmente — ahorra 37%`
- [ ] **Review screenshot:** same paywall screenshot is fine
- [ ] **Review notes:** short explanation

### 7d. Introductory Offer (Monthly only)

- [ ] Offer Type: **Free**
- [ ] Duration: **1 Week**
- [ ] Eligibility: **New Subscribers** (or broader if you want)
- [ ] Territories: **All**

### 7e. Server-to-server

StoreKit 2 handles reconciliation client-side; this app already does a `POST /v1/commerce/transactions/sync` after each purchase. You do not need App Store Server Notifications to ship, but they are recommended for refund handling:

- [ ] (Optional) App Store Server Notifications v2 URL: `https://proestimate-api-production.up.railway.app/v1/commerce/app-store-webhook` (only if you implement the handler)

---

## 8. Version Information (first version — 1.0)

Select your uploaded build (appears after processing).

### 8a. App Store listing copy

- [ ] **Subtitle** (30 char max): suggestion — `AI estimates for contractors`
- [ ] **Promotional Text** (170 char max, can be updated without re-review): suggestion — `Turn a photo into a professional estimate in minutes. AI remodel previews, automatic material and labor pricing, branded proposals and invoices.`
- [ ] **Description** (4000 char max): write 3–5 paragraphs covering:
  - One-sentence hook
  - Core loop: photo → AI preview → auto-priced estimate → branded proposal → invoice
  - Feature highlights (bulleted)
  - Subscription disclosure (required for 3.1.2 compliance — include price, auto-renewal language, link to Privacy and Terms)
- [ ] **Keywords** (100 char max, comma-separated, no spaces after commas): suggestion — `estimate,contractor,construction,remodel,invoice,proposal,AI,pricing,materials,quote`
- [ ] **Support URL:** `https://proestimateai.com/support` (make sure this resolves — stand up a minimal support page or redirect to mailto)
- [ ] **Marketing URL:** `https://proestimateai.com`

### 8b. Screenshots (required sizes)

Upload to App Store Connect. You already have simulator captures in `screenshots/` that can be used directly.

Required for first submission:
- [ ] **6.9" iPhone (iPhone 17 Pro Max / 16 Pro Max):** 1290 × 2796 px — **3 minimum, 6 max**
- [ ] **6.5" iPhone (iPhone 14 Plus / 11 Pro Max, legacy):** 1284 × 2778 or 1242 × 2688 — **3 min, 6 max**
- [ ] **13" iPad (iPad Pro M4):** 2064 × 2752 or 2048 × 2732 — **3 min, 6 max** (required since you target iPad)

Frame each shot in Simulator using **iPhone 17 Pro Max** and **iPad Pro 13"** destinations to get the right dimensions. Tip: Simulator → Device → Screenshot.

Order matters — put the before/after AI render first. Suggested order:
1. Before/after preview hero
2. Dashboard
3. Project type grid / AI generation in progress
4. Estimate editor (with line items)
5. Proposal / shareable client page
6. Paywall (must show subscription terms)

### 8c. App Preview videos (optional but conversion-boosting)

- [ ] 3 per device size max
- [ ] 15–30 seconds each
- [ ] Show real in-app functionality (no fake UI)

### 8d. General App Information (on the version page)

- [ ] **What's New in This Version:** first release — "Initial release."
- [ ] **Copyright:** `2026 Viral Ventures LLC`
- [ ] **Version:** 1.0

### 8e. App Review Information

- [ ] **Sign-in Information required:** **Yes**
  - Create a demo account on your production backend: `review+app@proestimateai.com` with a fixed password
  - Pre-populate it with 1–2 sample projects, a completed AI generation, one estimate, and one invoice so the reviewer has something to explore without waiting on AI generation
  - In the username/password fields, enter those credentials
- [ ] **Notes:**
  ```
  ProEstimate AI turns a construction-site photo into an AI-rendered
  remodel preview and a priced estimate.

  - Demo account above has a pre-seeded project with a completed preview.
  - Pro-only features (invoicing, AI-generated estimates, watermark-free
    PDFs) are gated behind Apple StoreKit 2. The 7-day free trial on the
    monthly subscription is disclosed on the paywall before purchase.
  - Sign in with Apple is supported.
  - Account deletion is available via Settings → Account → Delete Account.

  If the AI preview takes longer than a minute, it is the PiAPI or Google
  GenAI backend queue — please wait 60–120 seconds.
  ```
- [ ] **Contact Information:** phone, email for Viral Ventures LLC
- [ ] **Attachment:** optional screenshot or short video walk-through

### 8f. Export Compliance

- [ ] **Does your app use encryption?** No (we set `ITSAppUsesNonExemptEncryption = false` in Info.plist — this question should auto-complete)

### 8g. Content Rights

- [ ] Confirm "Does your app contain, display, or access third-party content?" — **No**

### 8h. Age Rating

Already set in Section 4 (expected: 4+).

### 8i. Build

- [ ] Select the uploaded build from the list once it's finished processing.

### 8j. Release

Pick one:
- [ ] **Manually release** (recommended for first submission — you control the exact moment)
- [ ] **Automatically release** (ships the second it's approved)
- [ ] **Phased release over 7 days** (gradual rollout, safer for first launch)

---

## 9. Guideline-specific compliance double-check

Apple rejects most first-time submissions for these:

- [ ] **2.1 (App Completeness):** No placeholder content, no broken buttons, no "Coming Soon" screens. Every feature the app advertises works.
- [ ] **3.1.2 (Auto-renewing subscriptions):** paywall UI shows, before purchase, all of: title, duration, price per period, auto-renewal terms, link to Privacy Policy and Terms of Use, restore-purchases button. ProEstimate AI already satisfies this — double-check the paywall text matches the disclosed amounts.
- [ ] **3.1.2 (subscription description fields):** Apple also requires the subscription's description (in the App Store Connect IAP details) to spell out "auto-renewing subscription — cancel anytime in Settings". Add a sentence to both en and es descriptions if the reviewer flags it.
- [ ] **4.0 (Design):** UI should feel native iOS. Dark mode support or a deliberate dark-only design (see 1a).
- [ ] **4.8 (Sign in with Apple):** if you offer any third-party sign-in, you must offer Sign in with Apple as an equivalent option. You already have it.
- [ ] **5.1.1(v) (Account deletion):** the app must have an in-app path to delete an account. Verify Settings → Account → Delete Account works end-to-end against production backend.
- [ ] **5.1.1 (data collection):** the permission dialogs only request data the app actually uses. The three usage descriptions are accurate for this app.
- [ ] **5.5 (Developer contact):** Support URL must be live and include a contact method.

---

## 10. TestFlight (strongly recommended before App Store)

- [ ] Upload the same archive to TestFlight first (same build, same bundle)
- [ ] Add yourself + team as Internal Testers (no review needed)
- [ ] Run through the entire flow on a real device: signup, photo upload, AI generation, estimate, invoice, subscription purchase (use a sandbox Apple ID), restore purchases
- [ ] Fix anything you spot, bump build number, re-upload
- [ ] Only then submit for App Store review

---

## 11. After submission

- [ ] Review team usually responds in 24–48 hours
- [ ] If rejected, read the Resolution Center message carefully and reply in the Resolution Center (not a new submission) to avoid extra review cycles
- [ ] If approved, monitor crash reports and subscription events for the first 72 hours
- [ ] Update `CHANGELOG.md` with the ship date and move `Unreleased` content under `1.0.0`

---

## 12. CLI automation — what I can do for you if you set up an API key

I can't log into App Store Connect on your behalf, but if you create an App Store Connect API key (Users and Access → Keys → Generate), I can help you:

- Use `fastlane deliver` to upload metadata and screenshots from the repo in one command
- Use `fastlane pilot` to manage TestFlight builds
- Use `xcrun notarytool` for manual uploads
- Wire a GitHub Actions job that uploads a TestFlight build on every merge to `main` (adds an `Archive + Upload` step to `.github/workflows/ios.yml`)

If you want any of that, generate a key, save it to `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, and tell me the Key ID + Issuer ID — I'll wire up Fastlane and a workflow.

Until then, everything in Sections 3–10 is manual in the App Store Connect web UI.
