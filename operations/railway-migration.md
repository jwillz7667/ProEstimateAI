# Railway account migration

Status recorded October 30, 2026. The replacement API, PostgreSQL 18, Redis 8.2, and website have been deployed into the destination account, `j.williams.33.33.66@gmail.com`. The user explicitly chose **“Connect the new empty database; start fresh.”** The destination contains a new application database with the production commerce catalog; previous customer records were not restored. The old PostgreSQL volume has been preserved and its contents have not been inspected.

The original API hostname now routes to the replacement API: <https://proestimate-api-production-75e5.up.railway.app>. Released iOS clients can continue using that hostname. At 08:11 UTC, `/health` reported `healthy`, PostgreSQL `connected`, and Redis `connected`. The replacement website at <https://proestimate-web-production.up.railway.app> returned `ok` from `/api/health`.

The branded website cutover is complete. Both <https://proestimateai.com> and <https://www.proestimateai.com> now serve the Railway website with verified ownership, propagated DNS, and valid TLS certificates. The website was rebuilt after a stale browser API origin was found; the checked proposal scripts contain the preserved `75e5` API origin and zero references to the superseded `75b9` origin. The redesigned password recovery page is live on both branded hosts and returns HTTP 200 with private/no-store caching, `no-referrer`, and `noindex, nofollow, noarchive` headers. Integration limits below remain explicit.

## Deployment record

| Resource | Destination ID or address |
| --- | --- |
| Project | `3ed10d99-04a7-4f9b-babb-94a7071024c6` — ProEstimate-API |
| Production environment | `0117903d-f058-4712-a55e-3407b6d89c01` |
| API service | `51b3f663-7ff9-4ea9-b4a8-3861e3d90f4f` |
| PostgreSQL 18 service | `4094f94b-b513-4c30-9ef1-23e774231a51` |
| Redis 8.2 service | `0ad60048-263f-49a5-939a-b6dd55607cdb` |
| Website service | `5f67e8f7-ddff-4aab-ab5c-e9a8e2df0f65` |
| API public origin | `https://proestimate-api-production-75e5.up.railway.app` |
| Website replacement origin | `https://proestimate-web-production.up.railway.app` |
| Branded website origins | `https://proestimateai.com`, `https://www.proestimateai.com` |

The reviewed baseline source is commit `44a4c0b34ff8ec7bc862639628f89918bb018489`. It was uploaded using the authenticated Railway CLI from separate `git archive` staging directories containing only tracked backend or website files. Local `.env` files and credentials were excluded. The destination account could not attach the GitHub repository, so GitHub automatic deployments are **not configured**.

| Deployment at this review | Status and meaning |
| --- | --- |
| API `a1508c4b-7ca7-47e0-bc74-0307bcfe6ad4` | `SUCCESS`; serving the preserved `75e5` hostname |
| Website `f7f86f0a-ccfa-4e0d-b82e-87a06017f02e` | `SUCCESS`; serving website build |
| Website `beceb147-a46d-4f47-96c9-38edc24330cc` | `SKIPPED`; the attempted hostname-change rebuild did not replace the serving build |
| Website `39d3fd0a-557a-43af-91bd-6ffea84f30e9` | `SKIPPED`; a repeat upload also did not replace the serving build |
| Website `473db366-8906-4ee7-b073-ca2c9fb03b95` | `SUCCESS`; rebuilt with the preserved API origin, browser bundle verified |
| API `33228806-1753-4a53-bbf7-b7c13096da41` | `SUCCESS`; reviewed billing/refund fixes from `a2341ed` |
| API `97a13dd4-5734-488f-9d9d-f1e0c8b78ec2` | `SUCCESS`; reviewed Apple/Google OAuth verification and first-login fixes from `7f86ea8` |
| Website `4e868dcc-7787-4b5f-a874-822118b8808a` | `SUCCESS`; redesigned password recovery and corrected website copy from `57af10d` |
| API `494deecd-93a8-48ac-9a59-29427480d973` | `SUCCESS` at 09:50:29 UTC; secure password recovery and production email configuration from `57af10d`; health verified afterward |

The stale website origin was corrected by clearing the service watch filter and uploading the tracked website archive again. Its successful build now embeds `https://proestimate-api-production-75e5.up.railway.app/v1`; the public proposal page and scripts were checked after deployment. The website is deployed from `57af10d`. Backend billing/refund and OAuth fixes were deployed from `7f86ea8`; the password-recovery API deployment from `57af10d` is successful. At 09:50:58 UTC, the preserved API hostname returned HTTP 200 with `healthy`, PostgreSQL `connected`, and Redis `connected`. A signed iOS 1.0.8 build 11 was successfully uploaded to App Store Connect by [TestFlight workflow 41035118104](https://github.com/jwillz7667/ProEstimateAI/actions/runs/41035118104). Upload acceptance does not establish Apple processing success; a read-only App Store Connect status check at 09:50 UTC did not yet list build 11, so indexing/processing, listing upload, and build attachment are still being verified. No App Review submission or public release was requested or performed.

## Data decision and preserved source

The user declined project transfer and requested copying configuration, then authorized starting with the new empty database when the old database could not be reached. Existing accounts, project records, photos, invoices, sessions, and purchase history were not restored. Returning users need a new account; App Store restore handling must be validated against the fresh-database ownership rules before promising paid-account continuity.

The source project is `40f80dd8-57fd-492f-aeed-ebd93b1ec016`. Its PostgreSQL 18 service is `e86363a1-292e-4cdb-bc7b-f4f13bf4fec3`, with preserved 500 MB volume `9e2df961-cc0b-4ab1-a3f1-c0916713c2d9` in `sfo`. The source workspace trial is expired, API and PostgreSQL are offline, and historical deployments are marked removed. That state does not establish whether its volume contains records or whether data was lost. Its API domain was renamed to `proestimate-api-legacy-75e5.up.railway.app` to free the original client hostname for the replacement.

No source service or volume was deleted. Do not restore an old backup over the now writable destination database. If recovery is requested later, recover the complete backup into a separate database and reconcile users, original App Store transaction ownership, numbering counters, usage, and new destination records before switching traffic.

Application binary content lives in PostgreSQL as base64 text: `Asset.imageData`, `AIGeneration.imageData`, `Company.logoImageData`, and `EstimateExport.pdfData`. Their MIME types and metadata must travel with any future full backup. No authoritative application object bucket or API upload volume was found. Redis contains disposable caches and rate limits and was intentionally started empty.

## Service configuration

| Setting | API | Website |
| --- | --- | --- |
| Root directory | `/backend` | `/web` |
| Builder | Dockerfile | Dockerfile |
| Dockerfile path in build context | `Dockerfile` | `Dockerfile` |
| Runtime | Node 24 | Node 24 / Next.js standalone |
| Build/start overrides | Unset; use Dockerfile | Unset; use Dockerfile |
| Health path / timeout | `/health` / 300 seconds | `/api/health` / 300 seconds |
| Restart policy | On failure, maximum 3 retries | On failure, maximum 3 retries |
| Public target port | 3000 | 3000 |
| Watch path | `/backend/**` | Empty during CLI-driven migration rebuilds |

The API Dockerfile runs `prisma migrate deploy`, the production-only catalog bootstrap, concurrent entitlement-index setup, then the server. The catalog bootstrap uses transactional, create-only upserts and does not create demo users or customer records. The baseline creates the Free/Pro catalog; the billing audit adds retired Premium records for signed historical restores while keeping them unavailable for new sales. Do not replace the container start sequence with `npm start`, which skips migration/bootstrap/index setup.

PostgreSQL and Redis each have a destination persistent volume in `sfo`. The API uses private-network service reference variables. The website runs `node server.js` as the nonroot `node` user. The destination uses explicit service settings because Railway rejected the legacy config-file-path setting as deprecated; the repository `railway.toml` was retained for earlier deployments.

## Environment configuration

All 19 observed source API variables were copied using the authorized Railway Raw Editor. The database reference and public API origin were updated for the destination; `FAL_KEY`, `REDIS_URL`, and `PUBLIC_PROPOSAL_BASE_URL` were added. A CLI comparison verified 17 retained source values without logging their contents. Keep secret values in Railway/local ignored environment files, never in this document or Git.

| Purpose | Names and current configuration |
| --- | --- |
| Database and sessions | `DATABASE_URL=${{Postgres.DATABASE_URL}}`; copied `JWT_SECRET`, `JWT_REFRESH_SECRET` |
| Runtime | `PORT=3000`, `NODE_ENV=production`, copied `ADMIN_EMAILS` |
| Public API origin | `API_BASE_URL=https://proestimate-api-production-75e5.up.railway.app` — no `/v1` |
| Proposal links | `PUBLIC_PROPOSAL_BASE_URL=https://proestimateai.com/proposal`; deployed and confirmed through the authenticated CLI |
| Password recovery | `PUBLIC_WEB_BASE_URL=https://proestimateai.com`; deployed and confirmed through the authenticated CLI |
| Browser origins | Copied `CORS_ORIGIN=*` is permissive and supports both branded website origins; this is not an origin allowlist |
| Image generation | New `FAL_KEY`; retained `GOOGLE_AI_API_KEY` and `PIAPI_API_KEY` fallbacks |
| Text AI | Copied `DEEPSEEK_API_KEY` |
| Distributed cache / limits | `REDIS_URL=${{Redis.REDIS_URL}}` |
| Maps / contractors / materials | Retained Google Maps/Places/SerpAPI values where configured |
| Google sign-in | Retained `GOOGLE_OAUTH_IOS_CLIENT_ID`, `GOOGLE_OAUTH_WEB_CLIENT_ID` |
| Email | New domain-restricted, sending-only `RESEND_API_KEY`; `RESEND_FROM_EMAIL=ProEstimate AI <noreply@proestimateai.com>`; deployed and confirmed through the authenticated CLI |
| App Store server cross-checks | `APP_STORE_ISSUER_ID`, `APP_STORE_API_KEY_ID`, and `APP_STORE_API_PRIVATE_KEY` were absent; configure them and the correct environment to enable authenticated server API checks |
| Push | Source included APNs identifiers/production settings but lacked `APNS_PRIVATE_KEY`; actual push delivery is not configured/verified |

The website's `API_BASE_URL` and `NEXT_PUBLIC_API_BASE_URL` are configured to `https://proestimate-api-production-75e5.up.railway.app/v1`; both must agree. `NEXT_PUBLIC_API_BASE_URL` is embedded during the Docker build, so changing runtime variables alone does not repair an existing browser bundle. Its server-only `DEEPSEEK_API_KEY` was copied, along with `NODE_ENV=production` and `PORT=3000`. Never expose a provider key under a public-prefixed variable.

## Website DNS cutover

The owning Vercel account `jwillschool7667@gmail.com` approved access to team `js-projects-995e4cf4` (`team_zcqDaSEKB4NwoC90nc0leWKG`). Vercel remains the authoritative DNS provider. The original zone was captured before changes in `validation-2026-10-30/dns-before.json`. Custom apex ALIAS and `www` CNAME records now route website traffic to Railway; verification TXT records were added. Existing system CAA/ALIAS and unrelated records were preserved. Custom records override the provider's system defaults.

Railway reports both custom domains verified with `DNS_PROPAGATED` and `CERTIFICATE_STATUS_TYPE_VALID`. Live HTTPS requests to both branded hosts returned HTTP 200 and the Railway server header. The preserved API hostname serves existing iOS clients, so the cutover requires no iOS API URL change.

| Host | Type | Railway target/challenge |
| --- | --- | --- |
| `www` | CNAME | `na21yduc.up.railway.app` |
| `_railway-verify.www` | TXT | `railway-verify=66f612c8e4741b587ea29e10c92c790b64fcffabe2071467a00ce4e67dc84e47` |
| Apex | CNAME/ALIAS supported by DNS provider | `uyiu0ftl.up.railway.app` |
| `_railway-verify` | TXT | `railway-verify=2c10ad9228bca6ca9402648abe103511c4ab427ad0cb359bd35044a3dbe79a56` |

`PUBLIC_PROPOSAL_BASE_URL` and `PUBLIC_WEB_BASE_URL` were changed to the branded website origin, applied by the successful API deployment, and confirmed through the authenticated CLI. Public host routing and the reset page are verified; a complete customer proposal creation/approval journey and newly generated branded links still require live end-to-end verification.

## Outbound email and password recovery

Resend verified sending domain `proestimateai.com` (`6be524ae-b5f7-4451-8dce-da4fdd9ed7e1`). Sending is enabled; receiving, click tracking, and open tracking are disabled. The DNS changes add DKIM at `resend._domainkey`, SPF and bounce MX under `send`, a Resend routing CNAME at `rsend`, and monitoring-only DMARC (`v=DMARC1; p=none`) at `_dmarc`. Required records were checked through independent public resolvers and Resend reports them verified. No unrelated mailbox routing was replaced.

A new Resend API key is restricted to sending for this domain and stored only in Railway's API environment; no key value is recorded here. The configured sender is `ProEstimate AI <noreply@proestimateai.com>`. The successful API deployment `494deecd-93a8-48ac-9a59-29427480d973` applies these variables; the authenticated CLI confirmed the branded sender and that the key is present without logging its value. No test email was sent, so provider configuration is verified but recipient delivery is not. This sending-domain setup does not provide a support inbox. Apple Hide My Email delivery also requires the sender to be registered for Apple's private email relay; that registration has not been verified.

The redesigned reset form handles requesting a link, validating matching passwords, expired links, completion, and network failures. New links carry the token in the URL fragment; the page reads and removes it without sending it in the HTTP request URL or referrer. Legacy query links remain supported and are scrubbed. Backend reset tests cover single use and concurrent redemption. See [password-reset-2026-10-30.md](password-reset-2026-10-30.md) for UI and regression evidence.

## Verification evidence and remaining work

The deployed baseline passed the following live HTTP checks using a disposable QA account, which was removed afterward:

- API health with PostgreSQL and Redis connected; signup, login, refresh-token rotation, and authenticated identity.
- Sale catalog containing Pro monthly/annual, Free entitlement, paid-feature denial, and five starter credits.
- Project creation and image upload/download with exact stored bytes from PostgreSQL.
- A real fal.ai photo edit, generation polling, persisted preview download, and exactly one starter credit consumed. The preview completed in about 13 seconds at 1182 × 886 pixels.
- Website process health and successful Docker builds for API and website.

Post-billing-deployment checks passed again: real fal preview in 6.05 seconds, exact one-credit consumption, quote-export and property-map requests returning HTTP 402 for a Free user, and QA cleanup. Post-OAuth-deployment checks rejected invalid Apple and Google signing keys with HTTP 401 `UNAUTHORIZED` rather than accepting a session or failing with HTTP 500. This rejection check is not a real interactive provider login.

DeepSeek funding is now confirmed: its balance endpoint returned HTTP 200 with an available positive balance. A subsequent isolated app generation exposed 23 persisted material/labor suggestions through the normal generation-materials API; the real iPad UI showed an AI estimate and subtotals. That QA tenancy was deleted after capture. The Railway website's support chat endpoint also returned HTTP 200 with a nonempty streamed response after funding. These observations replace the earlier insufficient-balance blocker.

Direct fal.ai generation and edit checks also succeeded. The selected FLUX.2 Flash provider is billed by input/output megapixels; see the [fal.ai model page](https://fal.ai/models/fal-ai/flux-2/flash/edit) for current pricing. Keys and full provider responses are excluded from deployment evidence.

The following remain separate from the successful infrastructure/API cutover:

1. **Release completion:** signed iOS 1.0.8 build 11 was accepted for upload. Confirm Apple processing reaches `VALID`, upload the reviewed ASO text and selected screenshots, and attach the build to the editable 1.0.8 version. Keep manual release and do not submit for review without authorization.
2. **Regression evidence:** backend billing/refund/OAuth fixes passed 221 unit tests, 93 distinct billing/database integration cases and nine focused OAuth/auth cases across the relevant runs; the password-reset changes passed the subsequent 226-test unit suite and focused real-PostgreSQL single-use/concurrent-reset coverage. Counts overlap and must not be summed. A baseline paid quote check returned HTTP 404 `NOT_FOUND`; its post-fix live check returns the expected HTTP 402. iOS regression checks and plugin compilation pass. The new password API deployment is successful and its public health endpoint confirms PostgreSQL and Redis are connected.
3. **OAuth lifecycle:** Google client-ID configuration matches the iOS app, invalid-token HTTP checks pass, and automated nonce/account-creation regressions pass. Real signed-app Apple/Google logins and Apple token revocation during account deletion remain unverified/unimplemented respectively. See [oauth-audit-2026-10-30.md](oauth-audit-2026-10-30.md).
4. **Apple purchase validation:** real sandbox/TestFlight purchase, restore, renewal, billing grace/retry, expiry, revocation/refund, original-transaction ownership, and notification delivery still need end-to-end evidence. Automated tests with mocked Apple proof and real PostgreSQL are not real StoreKit validation. Confirm App Store Connect's notification URL is `https://proestimate-api-production-75e5.up.railway.app/v1/commerce/webhooks/app-store` and configure missing server API credentials if authenticated cross-checks are required.
5. **Other integrations and recovery:** verify recipient email delivery and Apple private-relay sender registration; configure missing APNs credentials and test push delivery; check Google sign-in/API restrictions, proposal approval, PDFs/invoice totals, and website CORS. Schedule destination volume backups and verify a restore into an isolated database; backup scheduling and restoration have not been verified.

Starting fresh is the authorized data outcome, so an old-data restore is no longer a prerequisite. The pending items above must remain explicit when reporting overall application readiness.

## Optional future source recovery

If the old volume or a backup becomes available and the user requests recovery, use a PostgreSQL 18-compatible `pg_dump`/`pg_restore` client and restore into a **separate empty database**. A full custom-format dump must include schema, all application tables, `_prisma_migrations`, constraints, indexes, and sequence values; a migration or catalog seed is not a data backup. Preserve every image/PDF text column and original commerce identity. Never restore over destination records accepted since this fresh start.

Keep connection secrets outside Git in a protected operator session and a mode-`0600` libpq password file. Use [libpq environment variables](https://www.postgresql.org/docs/current/libpq-envars.html), a verified [custom-format dump](https://www.postgresql.org/docs/current/app-pgdump.html), and an [error-aborting transactional restore](https://www.postgresql.org/docs/current/app-pgrestore.html). Verify source/restore table counts, critical IDs and monetary totals, binary-column checksums, constraints, and index validity before reconciliation or traffic changes. Preserve the source volume until recovery is deliberately resolved.
