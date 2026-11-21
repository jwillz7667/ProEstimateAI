# ProEstimate AI iOS audit (2026-11-21)

Scope: the iOS app on `codex/railway-fal-migration` (PR #56, head `38b0559`). That branch, not `main`, produced 1.0.10 (17). The public App Store lookup shows 1.0.10 live since Nov 10, minimum iOS 26.4.

Method: static review of the Swift source, project settings, entitlements, Info.plist, asset catalog and fastlane config, plus the latest CI logs for this branch and live checks of the API and legal pages. I could not run the app on a device or simulator from this environment, so anything marked "verify on device" is unconfirmed.

## Bottom line

The app builds, its regression suites pass in CI, and the production API is healthy. Nothing I found will crash it on a normal launch. The problems are workflow and polish: one push feature that silently never works, a paywall that shows up far more often than it was designed to, Spanish that is mostly missing, and some spots where the UI makes users guess.

## Verified working

| Check | Result |
| :-- | :-- |
| iOS CI on PR #56 (simulator build + 10 regression runners) | Pass |
| Backend `GET /health` | `healthy`, database and Redis connected |
| `proestimateai.com/terms`, `/privacy` | 200 |
| PR #56 mergeability | Mergeable, clean |

## Fixed on branch `audit/ux-fixes-2026-11-21` (commit `15707f8`)

| # | Problem | Fix |
| :-- | :-- | :-- |
| 1 | Tapping **Continue** on the onboarding offer page (declining the trial pitch) immediately opened the login paywall sheet anyway. | Onboarding passes an `onDeclineOffer` callback; the login offer is marked handled for that session. |
| 2 | The login offer was meant to show once per login, but `TokenStore.sessionIdentifier` is a fresh UUID on every cold launch, so free and trial users saw the paywall almost every time they opened the app. | `PaywallPresenter` now records the last time each user saw or declined it and caps it at once per 24 hours. Added `loginOfferFrequency()` to `scripts/tests/IOSRegressionTests.swift`. Existing tests still pass the same calls. |
| 3 | Settings opened from the Home avatar wrapped `SettingsView` (which has its own `NavigationStack`) in a second `NavigationStack`. Nested stacks break the Done button placement and pushes to Company Branding, Tax and so on. | `SettingsView(onDone:)` renders Done inside its own stack; the extra wrapper is gone. |
| 4 | Sign-out only reset the Home tab's navigation. Signing in to a different account could land on the previous account's pushed project, invoice or client screen. | `AppRouter.resetAll()` on sign-out. |
| 5 | `ModelContainer` failure called `fatalError`, so any incompatible SwiftData schema change would crash launch for every existing user. | Rebuilds the store, then falls back to in-memory. Safe because those models are cache only (see item 8 below). |
| 6 | About 16 MB of dead weight in the bundle: the `CategoryThumbs` image set (no code references it; the picker uses `CategoryTiles`), `dashboard_hero.mp4`, and the unused `LoopingVideoPlayer`. | Removed. The project uses file-system synchronized groups, so no `.pbxproj` edit was needed. |

I could not compile these changes here. CI on a PR will build them and run the regression scripts.

## Must fix (not changed, needs your call or Apple-side setup)

### 1. Merge PR #56
`main` is 93 commits behind what is live on the App Store. The next person (or agent) who branches from `main` starts from stale code. PR #52 (`fix/testflight-existing-signing`) has also been open since Oct 10, and there are roughly 20 stale branches.

### 2. Push notifications cannot work
The app registers for APNs and the backend has a sender (`backend/src/lib/apns.ts`), but:
- `ProEstimate_AI.entitlements` has no `aps-environment` key.
- The `register_bundle_id` lane only enables `APPLE_ID_AUTH` and `IN_APP_PURCHASE`.
- The `beta` lane downloads the existing profile read-only, so it will never pick up Push.

Result: `didFailToRegisterForRemoteNotificationsWithError` on every device, so "your preview is ready" pushes never arrive when the app is closed. Local notifications from in-app polling still work.

I did not add the entitlement because with the read-only profile it would break the next TestFlight export. To turn it on:
1. Add `PUSH_NOTIFICATIONS` to `wanted` in the `register_bundle_id` lane and run the "Register bundle id" workflow (or enable Push on the App ID in the developer portal).
2. Regenerate the App Store provisioning profile so it includes Push.
3. Add `aps-environment` = `production` to `ProEstimate_AI.entitlements`.
4. Make sure `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` and `APNS_PRIVATE_KEY` are set on Railway.

### 3. APNs token is never removed on sign-out
`ApnsRegistrar.deregister(token:)` exists but nothing calls it. Once push is enabled, a phone that signed out keeps getting the previous account's notifications. Store the last token, and call deregister before `TokenStore.clearTokens()` in `AppState.signOut` (it needs the access token). Alternatively, have the backend delete device rows in `/auth/logout`.

### 4. The "System" appearance option does nothing
`Info.plist` sets `UIUserInterfaceStyle = Dark`. The default mode, and the server default, is "system", which passes `nil` to `preferredColorScheme`, so the plist wins and the app is always dark. Choosing "Light" does work. Pick one:
- Dark-only: remove the System and Light options, or
- Real system mode: delete the plist key. Light-mode phones will then switch to the light theme, so check every screen in light mode first.

## UX improvements, in priority order

### P1: these make the app harder to use

1. **Spanish is mostly missing.** About 569 literal UI strings in code; roughly 334 are not in `Localizable.xcstrings` and 69 more have no `es` value. 163 catalog keys are stale. A user who picks Español gets mostly English. Build once in Xcode so it extracts strings, then translate. Also `.environment(\.locale, …)` only affects SwiftUI `Text`; `String(localized:)` calls in view models still follow the device language, so in-app language switching gives mixed screens.
2. **No offline mode.** `CachedProject`, `CachedEstimate` and `CachedClient` are registered with SwiftData, but nothing reads or writes them. With weak signal on a job site, cold launch waits 8 seconds, then shows "couldn't restore" with Retry and Sign Out. At minimum, let a user with stored tokens into the app with the last known user and company and show the offline banner; then actually cache the project and estimate lists.
3. **Cancel in New Project throws away work silently.** The creation cover's Cancel dismisses even after photos and notes are added. Confirm when the draft has content. The estimate flow already saves a recovery draft, so the project flow is the odd one out.
4. **Two "New" buttons with overlapping meaning.** Home shows a large "New estimate" card and a smaller "New project" link. Contractors will not know which to use. Add one line explaining the difference ("Project = photos and AI preview; Estimate = pricing you send"), or make "New project" a choice inside the estimate flow.
5. **Deployment target is iOS 26.4.** Anyone on iOS 26.0 to 26.3 cannot install. CI compiles against the iOS 26.2 SDK and passes, which means no 26.3 or 26.4 APIs are in use. Dropping the target to 26.0 should be a one-line change; let CI confirm it.

### P2: clarity and polish

6. **Dense copy.** Several screens read like terms of service, for example the follow-up history footer ("A queued message is sent by the server. Provider acceptance does not confirm…") and the job-cost and payment explanations. Rewrite in contractor language and move edge-case detail behind an info button.
7. **Inconsistent branding.** Splash and login say "ProEstimate" while the app name is "ProEstimate AI". The logo asset is named `housd-icon-light`. `LSApplicationCategoryType` is `lifestyle`; this is a business app.
8. **Settings shows up in two places**: the Settings tab and the Home avatar sheet. That is fine, but `router.settingsPath` is never bound, so `AppRouter.push(_, on: .settings)` silently does nothing. Bind it or remove it.

### P3: code health (no user impact today)

9. About 45 distinct compiler warnings, several marked "this is an error in the Swift 6 language mode". The main cluster is `TokenStore`: it is `Sendable` and lock-protected, but default MainActor isolation makes its keychain helpers MainActor-isolated while they are called from `OSAllocatedUnfairLock.withLock` closures. Mark the class `nonisolated`. Also `PaywallDecision: Equatable` and the `User`/`Company` decoding inside the restore task group.
10. Deprecated on iOS 26: the bare `ASPresentationAnchor()` fallback in both sign-in coordinators (use `init(windowScene:)`), `CLPlacemark` in `AddressSearchField`, and `Text + Text` in `AIEstimateReadyCard`.
11. `sheet(isPresented:)` with `if let` inside, which the README bans, is still used in `ProjectDetailView` (edit sheet), `ClientDetailView` (edit sheet) and `ChangeOrderViews` (editor). If the model is nil when the sheet opens, the user gets a blank sheet.
12. `AppDestination.lawnMeasurement`, `.roofScouting`, `.clientForm`, `.subscriptionSettings` and `.paywall` fall through to `EmptyView()` in `appNavigationDestinations()`. They are only shown via sheets today, but a future `push` would show a blank screen.

## How to ship the fixes

1. Push `audit/ux-fixes-2026-11-21` (it is stacked on PR #56) and open a PR into `codex/railway-fal-migration`, or into `main` after #56 merges.
2. Let iOS CI build and run the regression scripts.
3. On a device, check that declining the onboarding offer goes straight to Home, that a cold relaunch does not show the paywall again the same day, and that Done works in the Settings sheet from Home.
