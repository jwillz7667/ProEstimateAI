# Access, purchase and image comparison corrections — October 31, 2026

The confirmed policy is **active Apple subscription or introductory trial for new AI work; basic workspace access stays free**. There is no account-age trial and no starter-credit bypass. Apple decides eligibility for its three-day introductory offer, once per subscription group.

## What caused the reported behavior

The server granted unlimited Pro to email addresses on `ADMIN_EMAILS`, independently of actual purchases, and the client could allow paid actions before its gate was configured. Historical credits could also be mistaken for permission to generate. These paths now fail closed; operational admin access is separate from billing. Only the designated, audited reviewer grant has finite Pro access without a purchase.

Free and lapsed users could encounter a paywall while making an ordinary project because the creation flow always entered AI generation. Manual creation now saves the project/photos without any AI or mapping request, and manual projects no longer consume a paid two-project allowance. The photo step explicitly makes photos optional and hides AI-specific controls when AI is off.

The purchase path cached empty StoreKit results, skipped StoreKit when the backend catalog failed, and did not quietly reconcile finished purchases after login. It now retries actual StoreKit products, only enables checkout with Apple's live products/prices, recovers current purchases and protects against old account/refresh responses granting access to a different session. Historical valid Apple purchases can bind once in the fresh database; an existing destination owner cannot be replaced, even after expiration.

The slider had implicit sizing/mask coordinates and competing fullscreen drag recognizers. Both views now use an explicit comparison canvas, a stable reveal fraction and one fullscreen drag owner. Separately, the actual generated bitmap had a white center divider baked into it. The image prompt mentioned comparison sliders/dividers and included administrative project text. Every image provider now receives a positive contract for one continuous, full-frame completed-scene photo, with design facts retained and administrative labels excluded. This fixes new renders; an old image that already contains a painted divider needs regeneration.

## App Store configuration

Both actual products remain approved in subscription group `22041326`:

| Product | US recurring price | Three-day free-trial coverage |
| --- | --- | --- |
| `proestimate.pro.monthly` | $19.99 / month | 175 / 175 available countries |
| `proestimate.pro.annual` | $149.99 / year | 175 / 175 available countries |

Previously only monthly had a seven-day offer, limited to the US; annual had none. The Apple API required an explicit territory despite the optional schema field. The first rejected global request changed nothing. The successful operation proved annual USA first, verified prices/availability, filled annual countries, then replaced monthly USA and filled the remaining monthly countries. It can resume without duplicating valid offers and compensates for a rejected monthly replacement. Customer transactions, signed trial deadlines, base prices and availability were not changed. Existing signed seven-day trials retain their actual expiration.

Mutation workflow `41169747961` and independent readback `41170422641` verified the 350 country-specific introductory offers. See `validation-2026-10-30/apple-three-day-trials.json`. Apple documents that subscription metadata changes can take up to an hour to reach the sandbox: [introductory-offer API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-subscriptionintroductoryoffers).

## Production and verification

API deployment `15aebd27-5182-4e92-8acf-5c28a543375f` is successful, including the access policy, continuous-photo prompts and paid PDF upload check. Website deployment `0ee8cf66-13b1-4043-9b71-9a878aa1b054` is successful, with matching free/basic and three-day-trial copy. Health confirms the API, PostgreSQL, Redis and website are available. Deployments used tracked archives without local secrets.

- CI: **229 unit tests and 118 PostgreSQL 18 integration cases**, plus build, integration typecheck and lint. A CI-only `psql` URL issue was fixed by removing Prisma's `schema` option while retaining SSL/libpq options; migration preservation assertions remain intact.
- iOS: **134 regressions and 38 comparison geometry checks**, actual SwiftUI SDK typecheck, integrated plugin build/run and signed archive/upload. The final manual-photo copy correction also compiled and launched through the plugin. Native UI confirmed Free dashboard access, a manual Kitchen project saved without a photo/AI, the Generate Vision paywall, and the optional Photos & Notes screen (`policy-free-dashboard.jpg`, `policy-free-manual-optional.jpg`).
- Release tooling: **77 offline cases** covering signing, credentials, attachment, screenshots, trial configuration, narrow age-rating changes and empty review-draft reuse. CI workflow `41173352790` passed all cases on the successful submission source; these include partial failures, compensation, per-country resume, price drift, ambiguous responses and preservation of questionnaire answers.
- Website: **20 tests**, lint with zero errors/two existing warnings, production build and live copy checks.
- Live Free QA: zero spendable AI; image, text-only and direct AI-estimate requests return HTTP 402 before jobs/provider calls; three manual projects and a manual estimate succeed. New stored PDF uploads return 402; existing saved-file reads remain available. Local PostgreSQL cases verify owned historical PDF bytes after lapse.
- Live image QA: original bytes preserved, two completed application jobs total, finite reviewer usage **2 / 20** with **18 remaining**. The corrected production image is continuous, with green cabinetry across the frame and no baked divider. Two additional local pipeline validations independently produced clean images. No cropping/filtering or lifecycle/refund weakening was introduced.

Source/evidence: `subscription-gates-2026-10-30.md`, `validation-2026-10-30/subscription-policy-final-live.json`, `image-prompt-verification.json`, `comparison-source.jpg` and `comparison-complete-photo.png` in that validation directory.

Normal-API cleanup removed the complete temporary Free tenancy, including its fourth project saved through the UI; prior access, refresh and login all return 401. Only the temporary comparison project was deleted from the reviewer workspace; both generations and its source asset now return 404. The reviewer account, grant and usage **2 / 20** remain unchanged. The known test refresh session was revoked (401 on reuse). Its stateless access JWT retains its normal expiry (`2026-10-31T05:37:13Z`); local credential/context/script copies were removed. No blanket immediate access-JWT revocation is claimed. No emails or Apple purchases were created. See `validation-2026-10-30/subscription-policy-cleanup.json`.

## Release and remaining boundaries

Build 13 contains the final manual-mode copy correction (source `6c1514c`), was signed/uploaded by workflow `41171240188`, and independently read back as **VALID** (`22faba99-5116-4a64-8cab-c00eb82faed7`) by workflow `41171998512`. Attachment workflow `41172071414` succeeded. It was initially left as a manual-release draft. The user subsequently explicitly authorized App Review submission; workflow `41173348790` successfully submitted **1.0.8 (13)** at `2026-10-31T05:38:31Z` (12:38 a.m. America/Chicago, October 31). No public release was performed; existing public app installations need the released update to receive client-side fixes.

Pre-submission status workflow `41172145850` confirmed build 13 attached to version `b045e36c-4b2a-4806-9eb5-1fc0988dc4dd`, state `PREPARE_FOR_SUBMISSION`, release type `MANUAL`. All 40 listing fields across five locales matched source, reviewer notes matched source, and all 75 selected screenshots were `COMPLETE`, in the expected order, with matching source byte sizes and exact dimensions. See `validation-2026-10-30/asc-policy-final.json`. Existing screenshot selection was preserved.

Apple first rejected the submission because the new `socialMedia` age-rating answer was missing. A narrow preflight filled only that answer as `false`, consistent with this private project-management app having no social feed/discovery, and independently verified all other questionnaire answers unchanged. The retry also exposed an older cancellation bug and an overly strict new guard: an empty, unsubmitted `READY_FOR_REVIEW` draft cannot be canceled, and its informational version relationship may still reference the previously released version. The final helper proves app ownership, iOS platform, unsubmitted state and empty items, then lets pinned Fastlane reuse the draft and adds the exact validated target; nonempty or in-progress submissions are protected. Binary selection is explicitly pinned to build 13 for this submission. The successful run records declaration `0f37ee70-8bdb-44e1-9f15-42662500f61c`, `socialMedia=false`, other answers preserved, and review submission `6a95cf5d-cda0-4496-834b-042f36317bcf`.

Post-submission readback workflow `41173425577` independently confirms **WAITING_FOR_REVIEW**, build **13** still `VALID`/unexpired/attached, and release type **MANUAL**. All 40 localized listing fields and review notes match source; all 75 screenshots remain complete, ordered and matched to the selected source dimensions/byte sizes. See `validation-2026-10-30/asc-review-submission.json`. Apple has received the submission; it has not been approved or publicly released by this work.

The unsigned simulator verified Free dashboard/manual access and an AI paywall, with subscription checkout disabled when StoreKit products were unavailable. That is fail-closed behavior, not proof of a completed Apple purchase. Actual native sandbox purchase/restore/renewal/refund confirmation still requires a signed TestFlight/device account and Apple's confirmation. No Apple purchase or charge was made by this work.

The user asked to stop opening simulators, and all simulator/native UI interaction stopped. Actual comparison edge/reversal, pinch/pan and double-tap runtime checks were not completed. The comparison changes have geometry regression coverage, actual component SDK typechecking and successful integrated builds; these are not substituted for touch-interaction proof. No further source changes were made based on unverified gesture concerns.

Accounts that exist only in the preserved offline source database are not recreated by these changes. Under the previously approved fresh start, those users need a destination account and a valid Apple restore; prior cloud projects/invoices were not recovered. Apple account-deletion token revocation, missing APNs/server cross-check credentials and other previously recorded integration limits remain separate audit items.

New PDF uploads now require Pro without double-counting the existing iOS quota pre-approval. A malicious paid client can still omit that separate pre-approval when directly uploading an externally rendered PDF; a receipt-bound render/upload contract remains future hardening. This is distinct from the now enforced unpaid-AI and unpaid-export gates.
