# App Store listing and ASO — October 30, 2026

> **Historical snapshot.** Build numbers and free-credit/trial claims below describe the earlier release. The [current access and comparison report](access-and-comparison-2026-10-31.md) supersedes those policies and records the latest build: basic work stays free; AI requires an active Apple subscription or trial, with eligible three-day introductory offers.

## Prepared changes

The App Store Connect 1.0.8 draft now presents ProEstimate as a contractor estimating and renovation workflow: photo preview, editable estimate, client approval and invoice. The existing updated screenshot campaign was uploaded unchanged as the user requested. Final Apple readback verifies the localized copy, categories, exact valid build attachment, reviewer notes and all 75 ordered screenshot assets. The version remains an unsubmitted manual-release draft. See [app-store-release-2026-10-30.md](app-store-release-2026-10-30.md) for workflow and readback evidence.

The public Apple lookup returned version 1.0.7, iOS 26.4 minimum, English/Spanish support and Business / Graphics & Design categories. The source is prepared for version 1.0.8. The public lookup is informational; the authenticated App Store Connect version state must govern uploads.

## Search intent and conversion

- English name: **ProEstimate: AI Remodel Quotes**. This keeps the recognizable brand and adds the concrete AI/remodel/quote use case.
- English subtitle: **Estimates, Invoices & Previews**. It covers the related document and visualization workflow without repeating the name's standalone terms.
- The keyword fields cover relevant contractor, construction, renovation, proposal, material/labor and trade-specific intent. UK and Australian fields use regional terms and spelling. Keyword selection is based on product relevance and language, not claimed search-volume or ranking data.
- Spanish Mexico uses **ProEstimate: Cotizaciones IA**; Spain uses **ProEstimate: Presupuestos IA**. Their subtitles and descriptions use natural local terminology.
- Promotional text explains the workflow and starter credits. It is written for conversion, not keyword stuffing. Apple states that promotional text does not affect search ranking.
- Descriptions begin with the main use case, then use short feature sections. They disclose five lifetime starter preview credits, paid Pro features, finite rolling allowances, localized pricing/offer eligibility and renewal terms.
- Removed fixed 60-second turnaround, exact/current-price promises, unsupported outcome claims and broad sales language. AI output is described as a starting point that users can review and edit.
- Release notes name the user-facing fixes and disclose the new cloud service, possible account recreation/Restore Purchases, and the fact that previous cloud projects and invoices were not transferred.

Apple identifies text relevance and user behavior as search factors. These changes improve the relevance and clarity of the listing; they do not establish or guarantee a particular rank or download volume. See [Apple's App Store search guidance](https://developer.apple.com/app-store/search/).

## Categories and links

Primary category remains **BUSINESS**. Secondary category changes to **PRODUCTIVITY** because the app organizes project information, estimates, approvals, invoices and follow-up work; this matches [Apple's category definition](https://developer.apple.com/app-store/categories/).

Every localization uses:

- Marketing: https://proestimateai.com
- Support: https://proestimateai.com/support
- Privacy: https://proestimateai.com/privacy
- Terms in the description: https://proestimateai.com/terms

The support, privacy and terms pages each returned HTTP 200 during this task. Root separately verified the website is served by Railway with valid HTTPS.

## Metadata validation

Counts exclude file-ending newlines, as imported metadata fields should. All keyword fields are measured in UTF-8 bytes, including commas.

| Locale | Name / 30 | Subtitle / 30 | Keywords / 100 bytes | Promo / 170 | Description / 4000 | Release notes / 4000 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| en-US | 30 | 30 | 100 | 155 | 2440 | 670 |
| en-GB | 30 | 30 | 95 | 158 | 2444 | 670 |
| en-AU | 30 | 30 | 96 | 158 | 2444 | 670 |
| es-MX | 28 | 28 | 95 | 147 | 2506 | 737 |
| es-ES | 28 | 24 | 97 | 142 | 2534 | 747 |

Validation checked required files, nonempty fields, character/byte ceilings, comma formatting, duplicate keyword terms, minimum keyword length and HTTPS URLs. `git diff --check` passed. The constraints come from [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) and [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/). [Apple's product-page guidance](https://developer.apple.com/app-store/product-page/) informed the concise name, subtitle, first paragraph and feature structure.

## Selected screenshot campaign

Source: `artifacts/app-store-listing/2026-10-30`. Keep filename order **01 → 02 → 03** within each family so the single orange/charcoal background flows across adjacent images.

| Family | Dimensions | Files |
| --- | --- | ---: |
| iPhone Dynamic Island medium | 1206 × 2622 | 3 |
| iPhone Dynamic Island large | 1320 × 2868 | 3 |
| iPhone Face ID large | 1284 × 2778 | 3 |
| iPad 13 inch | 2064 × 2752 | 3 |
| iPad 12.9 inch | 2048 × 2732 | 3 |
| iPad 11 inch | 1668 × 2420 | 3 |

The campaign includes the current required medium iPhone and 13-inch iPad families; the other families are additional tailored exports. Root validated all 18 PNGs as exact-dimension RGB without alpha. See [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

The metadata and screenshot-only lanes stage this selected campaign rather than the older `fastlane/screenshots` folder. The upload selection includes the 1206, 1320 and 1284-pixel-wide iPhone families and the 2064 and 1668-pixel-wide iPad families. The optional 2048-pixel-wide iPad export remains in the downloadable set; it is excluded from the upload because it shares an App Store display bucket with the 2064-pixel-wide export. This prevents duplicate panels from interrupting the continuous background. Each of the five listing locales receives the same selected English artwork: 15 images per locale, 75 files in total. Existing screenshots are replaced within the selected buckets, with filenames retaining the 01 → 02 → 03 order.

The staging helper checks the campaign manifest, panel order, file containment and PNG header dimensions/8-bit RGB format before copying any files. Its regression cases cover the exact locale/family selection, duplicate panels, incorrect dimensions, alpha channels and paths escaping the campaign. These checks do not establish screenshot content accuracy or Apple acceptance.

## Draft build attachment and readback

The metadata workflow also supports an `attach` scope with an explicit `build_number` input. The corresponding lane verifies the exact iOS marketing version, an editable unsubmitted draft, the exact build number and matching pre-release version, and `VALID` / unexpired processing state before making changes. It sets the release type to `MANUAL`, then uses [Apple's build relationship endpoint](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstoreversions-_id_-relationships-build) and reads back both the relationship and draft state. It has no review submission or public release operation. Regression cases cover invalid input, review/released states, incorrect versions/trains, expiration and incomplete processing.

The read-only `asc_status` lane includes recent build uploads when that optional API is supported. For the current version it reads back the build relationship, localized version metadata and screenshot filenames/delivery states by display bucket. This separates accepted upload transport from successful Apple processing and confirms the selected screenshot sets after upload.

## App Review demo login restored

The existing configured reviewer credentials initially returned HTTP 401 against the fresh backend. A private database check confirmed that the designated account was absent. It was recreated through the normal signup API, initially using the already-configured password. That task-created account's password was subsequently secured as described below; no pre-existing account was changed. No credentials are included in this report or the evidence.

Only that designated account received the existing supported `ADMIN_OVERRIDE` state for `PRO_MONTHLY`, with source `APP_REVIEW_DEMO`. A `PRODUCT_CHANGED` subscription audit event records this administrative grant and explicitly records that it is not a purchase. Store product and Apple transaction identifiers remain empty. Login and the public entitlement API both returned HTTP 200; the returned plan/source/state matched the grant and every paid feature flag was enabled. No Apple purchase, receipt, renewal or trial was invented or tested by this setup.

The database remained private. The one-time access channel used an isolated task key and a task-only first-use SSH host file with `accept-new`, retaining rejection of changed host keys. The observed public `ssh.railway.com` host fingerprint was `SHA256:+S1xg92FrnHz6pY3bpkmh1OGtWQGNANXilPzlxA7B1g`. The exact registered task key was removed and its absence was read back; both local key files, the temporary SSH wrapper and the task host file were removed. Existing SSH settings, keys and the user's agent were not changed. Both temporary app sessions were revoked.

Secret-free evidence is in `operations/validation-2026-10-30/app-review-demo.json`. No email or AI generation was requested, and this task did not submit the app for review. The demo account works on the new backend; its subsequent credential protection and completed Apple synchronization are documented below. Actual StoreKit purchase/restore lifecycle verification remains a separate release check.

The previous reviewer notes referenced sample data, a fixed seven-day trial and obsolete image-provider/queue behavior. They were replaced with instructions for the fresh, empty review workspace, the administrative Pro grant and the current finite rolling/daily/weekly limits. The notes name fal.ai as the primary image provider, defer introductory offers to App Store eligibility, distinguish review access from a real Apple purchase and retain a concrete client → project → estimate → quote/proposal → invoice review path. Metadata-copy workflow 41041330913 applied these revised notes and the secured credential; final readback 41041691751 confirms the notes match source.

## Reviewer credential protection

The repository was subsequently confirmed public, so the previously tracked demo password could not remain valid. The designated account created by this task was checked against its creation time, exact review company, `APP_REVIEW_DEMO` source, Pro override and administrative grant audit. Only that account's password was rotated to a strong random replacement, hashed with the app's existing bcrypt cost of 12. An activity audit records the rotation without credentials. No other account was changed.

The replacement is stored as the GitHub Actions secret `APP_REVIEW_DEMO_PASSWORD`. An ignored local recovery file at `.secrets-staging/app-review-demo-password` has mode `0600`; it is not a repository artifact. The new password returned login HTTP 200; the old public password returned HTTP 401. Pro entitlement remained unchanged, and a private readback confirmed zero remaining refresh sessions. The verification session was revoked. Temporary SSH registration, local key files, wrapper and task host file were all removed and checked again. The relay host key was pinned against the public fingerprint recorded above before the private operation.

The plaintext metadata password file is removed from current source. Metadata and future explicitly authorized review uploads load the password from the Actions secret and stop before Apple writes if it is missing. Fastlane's pinned Deliver implementation masks `app_review_information.demo_password`; status reads continue to exclude credential fields. Metadata-copy workflow 41041330913 synchronized Apple's reviewer credential with the rotated backend password. This credential protection did not submit the app for review or release it.

The first phone panel explains the preview, the second shows job organization, and the third connects estimates to invoices. The tablet panels use actual dashboard/project/preview captures and truthful project-detail copy. All use the selected brand badge and continuous background. English artwork remains English in this selected set; the five store-copy localizations do not by themselves localize image captions or app UI.

The user explicitly selected these updated screenshots. Their provenance is recorded in `sources.json`: the iPhone device artwork is generated marketing UI, while the iPad captures are actual app screenshots. [Apple's accurate-metadata and screenshot rules](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) require submitted images to represent the actual experience. Review that correspondence before App Review submission; metadata length and image dimensions alone do not prove review acceptance. Apple processed all 75 selected assets as COMPLETE; dimensions, file sizes and 01 → 02 → 03 order match the selected campaign. No replacement artwork was generated during upload.

## After release

Use App Store Connect Analytics to compare App Store Search impressions, product-page views, first-time downloads and conversion by storefront/language against the previous version. Keep those observations separate from this metadata validation. A later product-page optimization test can measure a specific screenshot or icon alternative while preserving a clear control; no experiment, ad campaign, ratings manipulation or ranking promise is part of this change.

