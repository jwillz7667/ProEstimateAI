# App Store Connect preparation — October 30, 2026

The user authorized uploading the updated iOS version and refactoring the listing with the selected updated screenshots. App Review submission and public release are separate actions and have not been requested or performed.

## Binary

Version **1.0.8**, build **11**, was archived and uploaded from source `57af10d` by [TestFlight workflow 41035118104](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41035118104). Apple's transporter accepted the package at 09:43:58 UTC. The workflow used the existing distribution certificate and a read-only provisioning profile; no certificate or profile was created. External TestFlight distribution was disabled.

Apple subsequently reported the upload `COMPLETE`, with no errors or warnings, and build `552e5d96-27db-44a9-9584-ac784dbc5a4c` `VALID` and unexpired. [Attachment workflow 41038196804](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41038196804) selected that exact build at 10:13:26 UTC. Readback confirmed version `b045e36c-4b2a-4806-9eb5-1fc0988dc4dd` remains `PREPARE_FOR_SUBMISSION` with `MANUAL` release.

## Listing

The prepared listing covers en-US, en-GB, en-AU, es-MX and es-ES. It uses the selected continuous orange/charcoal campaign, with three ordered panels in each of five Apple display buckets per locale. The optional 2048 × 2732 iPad exports remain in the downloadable set; they are excluded from upload because they share Apple's bucket with the larger 2064 × 2752 exports. The 75 files selected for upload are byte-identical copies of the approved local campaign.

The [ASO report](app-store-aso-2026-10-30.md) records copy limits, keyword intent, screenshot provenance and the distinction between localized listing text and the English image captions. The listing discloses the fresh cloud database and finite plan allowances. Changes are prepared for a manual-release draft, with `submit_for_review: false` explicitly enforced.

The metadata and screenshot upload was started by [workflow 41036860325](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41036860325). Readback verified all eight text fields per locale and the Business / Productivity draft categories. Twelve image uploads initially stalled. The waiting job was canceled without deleting Apple assets; [recovery workflow 41039118541](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41039118541) completed successfully with the same selected source files. [Readback 41039965919](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41039965919) confirms **75 COMPLETE assets**, five display buckets per locale, three panels per bucket, exact file sizes/dimensions and **01 → 02 → 03 order** throughout. Evidence is in `validation-2026-10-30/asc-screenshots-readback.json`.

The recovery follows [Fastlane 2.233.1's existing retry implementation](https://github.com/fastlane/fastlane/blob/2.233.1/deliver/lib/deliver/upload_screenshots.rb). The recovery lane sets a 120-second wait and `overwrite_screenshots: false`; ordinary new asset uploads now use a bounded 180-second wait before retrying. API-only metadata/status/attachment jobs run successfully on Ubuntu, while signed iOS builds retain macOS and the existing signing safeguards. No artwork was regenerated.

## Verification

All required PR checks passed on code head `79a16f8`: backend lint/typecheck/build/tests, website lint/build, iOS Simulator compilation, release signing safety and Vercel preview deployment. The 40 release helper checks cover 21 signing cases, five screenshot-staging cases, six draft-attachment cases and eight private-review-credential cases. Draft attachment requires an explicit build number, the exact iOS marketing-version train, a `VALID` unexpired build, and an unsubmitted editable version. It only selects the binary and enforces manual release; it has no review-submission or public-release endpoint.

The designated App Review account was absent from the fresh database and was recreated with an audited `ADMIN_OVERRIDE` / `PRO_MONTHLY` grant. No Apple transaction or purchase was fabricated. The previously public password was then invalidated and removed from current source. Its random replacement is stored in the Actions secret `APP_REVIEW_DEMO_PASSWORD` and an ignored local recovery file with mode `0600`. New-password login returned HTTP 200; the old value returned HTTP 401. The Pro grant was unchanged and all refresh sessions were revoked. Temporary private database access was removed and Postgres remained private. See the secret-free demo and credential-rotation evidence in `validation-2026-10-30`.

[Metadata-copy workflow 41041330913](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41041330913) successfully synchronized the protected reviewer credential and corrected review notes. [Final readback 41041691751](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41041691751) verified all 40 localized text fields, Business / Productivity categories, the exact valid build relationship, manual draft state, 75 complete ordered screenshot assets and review-note equality with source. Status queries never fetch reviewer passwords. The final check result is `allChecksPassed: true` in `validation-2026-10-30/asc-final.json`.

## Remaining evidence before App Review

- Real Apple and Google sign-in with the signed build, including the documented Apple credential/revocation lifecycle gaps.
- Real StoreKit purchase, restore, renewal, billing grace/retry, expiry and refund/revocation transitions. PostgreSQL integration tests and mocked Apple proof are separate evidence.
- Correspondence of generated iPhone marketing artwork to the actual app experience. Actual iPad capture provenance is recorded alongside the assets; the designated reviewer login has been verified.
- Missing APNs private key and optional authenticated App Store Server API cross-check credentials; Apple private-relay sender registration and real email delivery have not been verified.

See the [migration runbook](railway-migration.md), [billing audit](billing-audit-2026-10-30.md), [OAuth audit](oauth-audit-2026-10-30.md) and [iOS audit](ios-audit-2026-10-30.md) for the implementation and readiness limits.
