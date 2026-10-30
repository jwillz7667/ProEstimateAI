# Railway account migration

Status recorded October 30, 2026. The replacement API, PostgreSQL 18, Redis 8.2, and website have been deployed into the destination account, `j.williams.33.33.66@gmail.com`. The user explicitly chose **“Connect the new empty database; start fresh.”** The destination contains a new application database with the production commerce catalog; previous customer records were not restored. The old PostgreSQL volume has been preserved and its contents have not been inspected.

The original API hostname now routes to the replacement API: <https://proestimate-api-production-75e5.up.railway.app>. Released iOS clients can continue using that hostname. At 08:11 UTC, `/health` reported `healthy`, PostgreSQL `connected`, and Redis `connected`. The replacement website at <https://proestimate-web-production.up.railway.app> returned `ok` from `/api/health`.

The website custom-domain cutover and the remaining integration checks below are still outstanding. A healthy website process does not establish correct browser API configuration: the serving website bundle was found to contain the superseded `75b9` API hostname and needs a successful rebuild.

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

The reviewed baseline source is commit `44a4c0b34ff8ec7bc862639628f89918bb018489`. It was uploaded using the authenticated Railway CLI from separate `git archive` staging directories containing only tracked backend or website files. Local `.env` files and credentials were excluded. The destination account could not attach the GitHub repository, so GitHub automatic deployments are **not configured**.

| Deployment at this review | Status and meaning |
| --- | --- |
| API `a1508c4b-7ca7-47e0-bc74-0307bcfe6ad4` | `SUCCESS`; serving the preserved `75e5` hostname |
| Website `f7f86f0a-ccfa-4e0d-b82e-87a06017f02e` | `SUCCESS`; serving website build |
| Website `beceb147-a46d-4f47-96c9-38edc24330cc` | `SKIPPED`; the attempted hostname-change rebuild did not replace the serving build |
| Website `39d3fd0a-557a-43af-91bd-6ffea84f30e9` | `SKIPPED`; a repeat upload also did not replace the serving build |

The public JavaScript loaded by `/proposal/migration-config-check` still embedded `https://proestimate-api-production-75b9.up.railway.app/v1` at this review. Rebuild the website with both API variables set to the preserved `75e5` origin and verify the proposal page's browser bundle before changing DNS. Billing, entitlement, generation-refund, and frontend audit changes in the working tree are separate from the baseline deployment; record their reviewed commit and successful deployment before claiming those fixes are live.

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
| Watch path | `/backend/**` | `/web/**` |

The API Dockerfile runs `prisma migrate deploy`, the production-only catalog bootstrap, concurrent entitlement-index setup, then the server. The catalog bootstrap uses transactional, create-only upserts and does not create demo users or customer records. The baseline creates the Free/Pro catalog; the billing audit adds retired Premium records for signed historical restores while keeping them unavailable for new sales. Do not replace the container start sequence with `npm start`, which skips migration/bootstrap/index setup.

PostgreSQL and Redis each have a destination persistent volume in `sfo`. The API uses private-network service reference variables. The website runs `node server.js` as the nonroot `node` user. The destination uses explicit service settings because Railway rejected the legacy config-file-path setting as deprecated; the repository `railway.toml` was retained for earlier deployments.

## Environment configuration

All 19 observed source API variables were copied using the authorized Railway Raw Editor. The database reference and public API origin were updated for the destination; `FAL_KEY`, `REDIS_URL`, and `PUBLIC_PROPOSAL_BASE_URL` were added. A CLI comparison verified 17 retained source values without logging their contents. Keep secret values in Railway/local ignored environment files, never in this document or Git.

| Purpose | Names and current configuration |
| --- | --- |
| Database and sessions | `DATABASE_URL=${{Postgres.DATABASE_URL}}`; copied `JWT_SECRET`, `JWT_REFRESH_SECRET` |
| Runtime | `PORT=3000`, `NODE_ENV=production`, copied `ADMIN_EMAILS` |
| Public API origin | `API_BASE_URL=https://proestimate-api-production-75e5.up.railway.app` — no `/v1` |
| Proposal links | `PUBLIC_PROPOSAL_BASE_URL=https://proestimate-web-production.up.railway.app/proposal` until branded-domain cutover is verified |
| Browser origins | Copied `CORS_ORIGIN`; verify final website origins, including apex and `www` |
| Image generation | New `FAL_KEY`; retained `GOOGLE_AI_API_KEY` and `PIAPI_API_KEY` fallbacks |
| Text AI | Copied `DEEPSEEK_API_KEY` |
| Distributed cache / limits | `REDIS_URL=${{Redis.REDIS_URL}}` |
| Maps / contractors / materials | Retained Google Maps/Places/SerpAPI values where configured |
| Google sign-in | Retained `GOOGLE_OAUTH_IOS_CLIENT_ID`, `GOOGLE_OAUTH_WEB_CLIENT_ID` |
| Email | `RESEND_API_KEY` was absent from the copied source variables; outbound email readiness is unverified |
| App Store server cross-checks | `APP_STORE_ISSUER_ID`, `APP_STORE_API_KEY_ID`, and `APP_STORE_API_PRIVATE_KEY` were absent; configure them and the correct environment to enable authenticated server API checks |
| Push | Source included APNs identifiers/production settings but lacked `APNS_PRIVATE_KEY`; actual push delivery is not configured/verified |

The website's `API_BASE_URL` and `NEXT_PUBLIC_API_BASE_URL` are configured to `https://proestimate-api-production-75e5.up.railway.app/v1`; both must agree. `NEXT_PUBLIC_API_BASE_URL` is embedded during the Docker build, so changing runtime variables alone does not repair an existing browser bundle. Its server-only `DEEPSEEK_API_KEY` was copied, along with `NODE_ENV=production` and `PORT=3000`. Never expose a provider key under a public-prefixed variable.

## Website DNS cutover

The existing `proestimateai.com` website remains on Vercel. Its authoritative nameservers are Vercel DNS. The replacement Railway website has custom domains attached, but Railway ownership/routing verification remains pending. The owning Vercel team is `js-projects-995e4cf4` (`team_zcqDaSEKB4NwoC90nc0leWKG`). Both currently connected Vercel accounts returned an empty team list during this review, so DNS access to that team is still unavailable. The user said they would reconnect the owner account; successful owner access has not been demonstrated.

Once the serving website bundle is rebuilt and the owner account is connected, read the full existing DNS zone, change only the website routing records, and add the Railway verification TXT records. Preserve MX, mail/authentication TXT, and all unrelated records.

| Host | Type | Railway target/challenge |
| --- | --- | --- |
| `www` | CNAME | `na21yduc.up.railway.app` |
| `_railway-verify.www` | TXT | `railway-verify=66f612c8e4741b587ea29e10c92c790b64fcffabe2071467a00ce4e67dc84e47` |
| Apex | CNAME/ALIAS supported by DNS provider | `uyiu0ftl.up.railway.app` |
| `_railway-verify` | TXT | `railway-verify=2c10ad9228bca6ca9402648abe103511c4ab427ad0cb359bd35044a3dbe79a56` |

Re-read Railway's current required records immediately before the change in case the challenges changed. Verify ownership, HTTPS certificates, apex/`www` routing, proposal loading/approval, and browser API requests after propagation. Then set `PUBLIC_PROPOSAL_BASE_URL` to the verified branded origin plus `/proposal` and verify newly generated links. The preserved API hostname already serves existing iOS clients; no iOS URL change is required for this cutover.

## Verification evidence and remaining work

The deployed baseline passed the following live HTTP checks using a disposable QA account, which was removed afterward:

- API health with PostgreSQL and Redis connected; signup, login, refresh-token rotation, and authenticated identity.
- Sale catalog containing Pro monthly/annual, Free entitlement, paid-feature denial, and five starter credits.
- Project creation and image upload/download with exact stored bytes from PostgreSQL.
- A real fal.ai photo edit, generation polling, persisted preview download, and exactly one starter credit consumed. The preview completed in about 13 seconds at 1182 × 886 pixels.
- Website process health and successful Docker builds for API and website.

Direct fal.ai generation and edit checks also succeeded. The selected FLUX.2 Flash provider is billed by input/output megapixels; see the [fal.ai model page](https://fal.ai/models/fal-ai/flux-2/flash/edit) for current pricing. Keys and full provider responses are excluded from deployment evidence.

The following remain separate from the successful infrastructure/API cutover:

1. **Website build and branded DNS:** successfully rebuild the website, then perform the scoped DNS cutover once Vercel owner access exists. Process health alone did not catch the stale public API origin.
2. **DeepSeek credit:** the copied key was accepted, but direct service checks returned HTTP 402 “Insufficient Balance.” The user said they would add credits; funding is not confirmed. AI estimates, material/labor suggestions, and website support chat need a successful post-funding check. The live material-suggestion check returned no suggestions before its deadline.
3. **Billing and frontend audit release:** review, test, commit, and deploy the audit fixes. A baseline `/v1/usage/check` request returned HTTP 404 `NOT_FOUND` for a paid quote flow; the audit addresses entitlement/usage gates, Apple lifecycle handling, and iOS paywall/state decoding. Working-tree fixes are not live until their deployment succeeds.
4. **Apple purchase validation:** real sandbox/TestFlight purchase, restore, renewal, billing grace/retry, expiry, revocation/refund, original-transaction ownership, and notification delivery still need end-to-end evidence. Automated tests with mocked Apple proof and real PostgreSQL are not real StoreKit validation. Confirm App Store Connect's notification URL is `https://proestimate-api-production-75e5.up.railway.app/v1/commerce/webhooks/app-store` and configure missing server API credentials if authenticated cross-checks are required.
5. **Other integrations and recovery:** configure missing outbound-email/APNs credentials and test delivery; check Google sign-in/API restrictions, proposal approval, PDFs/invoice totals, and website CORS. Schedule destination volume backups and verify a restore into an isolated database; backup scheduling and restoration have not been verified.

Starting fresh is the authorized data outcome, so an old-data restore is no longer a prerequisite. The pending items above must remain explicit when reporting overall application readiness.

## Optional future source recovery

If the old volume or a backup becomes available and the user requests recovery, use a PostgreSQL 18-compatible `pg_dump`/`pg_restore` client and restore into a **separate empty database**. A full custom-format dump must include schema, all application tables, `_prisma_migrations`, constraints, indexes, and sequence values; a migration or catalog seed is not a data backup. Preserve every image/PDF text column and original commerce identity. Never restore over destination records accepted since this fresh start.

Keep connection secrets outside Git in a protected operator session and a mode-`0600` libpq password file. Use [libpq environment variables](https://www.postgresql.org/docs/current/libpq-envars.html), a verified [custom-format dump](https://www.postgresql.org/docs/current/app-pgdump.html), and an [error-aborting transactional restore](https://www.postgresql.org/docs/current/app-pgrestore.html). Verify source/restore table counts, critical IDs and monetary totals, binary-column checksums, constraints, and index validity before reconciliation or traffic changes. Preserve the source volume until recovery is deliberately resolved.
