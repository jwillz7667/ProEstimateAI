# Home, project flow and five-panel listing — November 3, 2026

The user requested at least five screenshots **per device**, correction of the **original orange-ribbon panorama** to account for gallery gutters, and a more useful modern dashboard. A proposed atmospheric replacement was rejected; the delivered campaign retains the original ribbon. The latest simulator preference is **keep simulators closed**, superseding the earlier allow response. No simulator was opened, booted, launched or captured for this work.

## App behavior

Home now starts with one New Project action and three readable recent-project rows. Status and titles sit outside photos, the business summary is compact and secondary, and plan information is quiet. The rotating promotional video is no longer instantiated and its unused component was removed. Regular-width layouts can use work/context columns; accessibility sizes stack. Home no longer starts up to ten generation lookups just to hydrate carousel images.

Summary and project requests publish independently, preserving usable content and the primary action during partial failures. Account/company revisions reject stale responses and clear content on workspace changes. The recent preview sorts its first returned project page by update time; it does not claim to paginate the full history, which remains in Projects.

Standard project setup is two input pages: category and optional name, then photos/notes with one AI control and optional estimate details. Searchable adaptive category tiles replace the dense fixed grid. Paid lawn projects retain the measurement step. Progress, Back and final actions derive from the active steps. Free manual projects require no photo and trigger no AI/map calls. Existing trial/subscription gates remain enforced.

Manual Create Estimate is now visible directly. Saved estimates and AI Ready → Review open a real line-item editor rather than PDF export. Draft items support add, edit and remove; server totals are refreshed after each operation. Quantity, price, markup, tax and text bounds are validated, and tax percentage is converted to the canonical fractional wire value. Ambiguous line-item saves are not blindly retried; the user must reconcile with the saved document. Non-draft estimates are read-only. Export, proposal and invoice actions remain separate paid actions.

The API also checks DRAFT status under the same parent row lock used for line-item mutations. A stale client cannot edit a sent, approved, declined or expired estimate; canonical totals and historical reads are preserved. Deployment `497b56b0-6ff7-45c9-aed9-72644d7c9842` from tracked backend source `7fbc2a5` is successful. No environment variables, customer rows or volume configuration were changed.

## Artwork and gutter calibration

Campaign: `artifacts/app-store-listing/2026-11-03`. Each of six exact export families contains **five** ordered RGB PNGs without alpha: 1206×2622, 1320×2868, 1284×2778, 2064×2752, 2048×2732 and 1668×2420. The optional 2048×2732 family shares Apple's bucket with 2064×2752, so staging selects five buckets in each of five locales: **125 images**, five per bucket, rather than appending to the former three.

The live public App Store iPhone gallery measured 273.328125 CSS pixels per card with a 20-pixel gutter at a 1200-pixel viewport. For export width W, the virtual gutter G is round(W×20/273.328125). The original ribbon is drawn once across 5W+4G, with panel i cropped at i×(W+G). Foreground artwork uses the same stride. This preserves the curve through the hidden gallery strips instead of treating adjacent images as touching.

That measurement is a reference calibration. iPad exports use the same ratio as an inference, not a claimed native iPad measurement; storefront/device geometry can vary. Reference/alternate gap previews and an interactive gallery review are included. No fixed PNG panorama can adapt its crop to every possible gutter ratio. The original palette and normalized curve profile are preserved.

Provenance is explicit in the campaign README, sources and manifest. Existing approved phone artwork includes generated concept UI; preserved photo/generation and historic capture crops are used where available. The new Home and tablet estimate/proposal views are code-derived illustrations with fictional sample data, **not new runtime captures**. The user prohibited opening simulators, so new touch interactions and pixel-level iPhone/iPad layouts have not been executed. No customer credentials or reviewer password are embedded.

## Verification

- Build iOS Apps plugin: integrated SDK compile succeeded in 154.7 seconds; an incremental compile after the photo-picker isolation correction succeeded in 65.4 seconds. No app or simulator was launched. Existing unrelated deprecation/concurrency warnings remain; the changed photo-picker label separately passed SDK strict-concurrency typechecking with warnings treated as errors.
- iOS standalone behavioral checks: 134 existing, 24 Home state, 32 active-step navigation, and 50 estimate-editor checks. New runners are wired into iOS CI. These exercise real models/state/serialization rather than claiming touch-interaction evidence.
- Backend source `7fbc2a5`: CI `41611158765` passed 229 unit and 124 PostgreSQL 18 integration cases, including six new editing/immutability cases.
- Live API: 20 Free-workspace checks passed, including exact decimal totals, item CRUD, sent-item 409 denials, read access and tenant cleanup. The temporary company/account and its records were deleted, access/refresh/login subsequently returned 401, and temporary credentials were removed. No AI, Apple purchases, emails or grants were used. See `validation-2026-11-03/manual-estimate-live.json`.
- Artwork: all 30 physical PNGs passed dimension/color/alpha validation and gutter crop-stride checks. Staging produced exactly 125 files; six fixture checks reject a three-panel regression, invalid order, bad dimensions, alpha and path escapes. Representative phone/tablet layouts were visually inspected at full-size and in gallery previews.

## Release

Read-only inspection `41609860305` confirmed that 1.0.8 (13) was already live (`READY_FOR_SALE`), with the old three screenshots per bucket. These changes target **1.0.9 (14)** and preserve the live version. Release notes in all five locales and the private review flow are updated.

Signed upload `41614510245` succeeded from binary source `d10738e`. Apple processed build `8d261e8e-578c-4a71-997c-a234ebd88b53` as VALID and unexpired. Metadata copy `41614514981` created new version `2845471a-267c-4af8-b52d-140add82ab0f`. Screenshot replacement `41614659361` succeeded after Apple's processing/retries; build attachment `41616169904` selected the exact build 14. The independent pre-submission readback `41617743324` verified all 125 files, exactly five per bucket and locale, ordered 01–05, COMPLETE, with source filenames, reported byte sizes and dimensions matching. See `validation-2026-11-03/screenshots-upload-readback.json`.

One read-only status attempt received Apple's HTTP 500; its retry succeeded. Intermediate reads during uploader retries showed 93, 116 and 122 completed images; these were progress observations rather than final counts. Final count is 125. The reusable verifier is `scripts/verify-uploaded-app-store-listing.py`, with nine offline positive/negative controls. It verifies per-bucket counts independently of Fastlane's cross-locale checksum shortcuts.

The initial submit run `41618201415` waited for a Mac runner and was canceled while still queued with no executed steps or Apple actions. Submission is API-only, so the workflow now runs on Ubuntu; the separate signed archive still uses macOS. Run `41618791416` successfully submitted **1.0.9 (14)** at `2026-11-03T10:23:58Z`. The age declaration remained `socialMedia=false` with all other answers preserved. Final independent readback `41619024146` confirms **WAITING_FOR_REVIEW**, build 14 attached/VALID/unexpired, all 125 COMPLETE screenshots still ordered/matched, all 40 localized listing fields matching source and review-note equality. Publication mode remains **MANUAL**; no public release was performed. See `validation-2026-11-03/app-store-submitted.json`.

All required PR checks passed on submission tooling source `9325919`; release tooling has 78 offline Ruby cases, the iOS CI runs all 240 model/state checks and compiles the integrated app, and backend CI passes the 229 unit/124 PostgreSQL cases. The designated reviewer login and finite Pro grant are active, with 18/20 AI previews remaining; no near-term expiry is configured. Its test refresh session was revoked. See `validation-2026-11-03/review-account-ready.json`.

The downloadable export package is `build/ProEstimate-AppStore-1.0.9-2026-11-03.zip`: 30 PNGs across six device sizes, reference previews, editable panoramas and source/validation documents. Gallery UI illustrations remain explicitly identified; simulator touch testing and new runtime captures are unverified under the user's keep-closed instruction.
