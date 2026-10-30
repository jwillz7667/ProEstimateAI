# Railway account migration

Status recorded October 30, 2026: the destination project now exists, with healthy PostgreSQL 18 and Redis 8.2 services. All 19 observed source API variables were copied through the authorized Railway Raw Editor. `DATABASE_URL` now references the destination PostgreSQL service; `API_BASE_URL` is `https://proestimate-api-production-75b9.up.railway.app`. `FAL_KEY`, `REDIS_URL`, and `PUBLIC_PROPOSAL_BASE_URL` were added. The application deployment and end-to-end verification remain pending at the time of this update. **Existing database records have not been restored.**

The old `ProEstimate-API` project's API and PostgreSQL 18 services remain offline, with no active deployment returned. The dashboard shows historical deployments marked removed, so the project was previously deployed. Its PostgreSQL volume is 500 MB in `sfo`; no Redis service is present, and the source workspace trial is expired. The existing project description states that configuration was staged for migration from an expired workspace, while database restoration and hostname cutover remain pending. The old volume's contents have not been inspected, so production data presence is unverified; data loss is not established.

The original API hostname remains attached to the old service but has no running route: `https://proestimate-api-production-75e5.up.railway.app/health` returns Railway HTTP 404, “Application not found.” No local source database credentials or backup were found. The OAuth connection exposes variable names rather than secret values; copying used the authorized dashboard instead. Source variable names omitted `APNS_PRIVATE_KEY`, `RESEND_API_KEY`, and the App Store verification credentials. Those integrations require recovered or newly configured credentials before complete readiness can be claimed.

Inspect the existing database volume or recover its complete backup and original production configuration before treating a deployment as a completed migration. Creating an empty database would not recover existing accounts, purchases, photos, estimates, or invoices.

## Selected method: copy configuration and restore database separately

The user explicitly declined project transfer and requested copying variables to the new account. Continue with the new project and preserve the source project/volume. A project ownership transfer is not authorized.

### Prepare and preserve data

Complete this step once a source database connection or complete backup can be recovered. Copied environment values and the new database's commerce catalog do not contain existing customer records.

- The observed source service is PostgreSQL 18. Verify the actual recovered production database version, provision a matching destination version initially with sufficient volume capacity, and add a separate Redis service. Confirm any required PostgreSQL extensions. Use a compatible `pg_dump` client; do not use an older client against a newer server.
- Keep destination application services stopped until restore and verification finish. Use a new, empty target application database; the commands below intentionally do not drop or overwrite an existing database.
- If the replacement API has already initialized its catalog or accepted writes, restore into a separate empty database and reconcile any new destination records before switching connections. Do not run this restore over an already populated application database.
- Copy the complete application database, including `_prisma_migrations`, all 27 application tables, constraints, indexes, and sequence values. A schema migration or seed is not a substitute for the source data.
- Preserve user/password/OAuth identities, refresh tokens, device tokens, company numbering counters, project/client records, estimates and lines, proposals/share tokens, invoices and lines, pricing, activity, subscription products/events/entitlements, usage buckets/events, purchase attempts, and paywall history.
- Preserve `Asset.imageData`, `AIGeneration.imageData`, `Company.logoImageData`, their MIME types, and `EstimateExport.pdfData`. These contain the actual photos, generated previews, logos, and saved PDFs as base64 text in PostgreSQL. No application object bucket or upload volume was found in the repository.
- Redis contains disposable cache and rate-limit counters. Start the new Redis empty. AI generation runs in the API process without a durable queue: stop new writes and let active generations finish before the final dump. Reconcile any interrupted generation and its usage reservation after restore.
- Retain the original `JWT_SECRET` and `JWT_REFRESH_SECRET` to preserve existing sessions. Copy existing provider, email, Apple, push, and Google credentials securely; preserve private-key newlines. Generate replacement credentials only when the original cannot be recovered, and record the resulting session/integration impact.

### Dump and restore

Use a secure operator session. Populate libpq connection environment variables `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, and the source's supported TLS settings from recovered connection information. Set `PGPASSFILE` to a password file outside the repository with mode `0600`, supplied through the secret manager. `PGDATABASE` must contain only the database name, never a credential-bearing URI. Do not put passwords, connection URLs, or private keys into command arguments, shell history, logs, or this document. See [PostgreSQL connection environment variables](https://www.postgresql.org/docs/current/libpq-envars.html).

Freeze source application writes and incoming webhook processing for the final snapshot; preserve webhook deliveries for replay. In the source connection environment, set `MIGRATION_DUMP_PATH` to a new absolute file path outside the repository, then run:

```sh
umask 077
psql --no-psqlrc --set=ON_ERROR_STOP=1 --command='SELECT current_database(), current_user, version();'
pg_dump --format=custom --no-owner --no-acl --file="${MIGRATION_DUMP_PATH:?Set a new backup path outside the repository}"
pg_restore --list "$MIGRATION_DUMP_PATH" > "$MIGRATION_DUMP_PATH.toc"
shasum -a 256 "$MIGRATION_DUMP_PATH"
```

Check every exit status and retain the archive and checksum in protected backup storage. The archive contains customer data and authentication records. A normal full [custom-format dump](https://www.postgresql.org/docs/current/app-pgdump.html) includes schema and data; do not add table, schema, or data-only filters.

Switch the libpq environment and `PGPASSFILE` to the **empty destination database**. Confirm its identity and absence of application tables before running:

```sh
psql --no-psqlrc --set=ON_ERROR_STOP=1 --command='SELECT current_database(), current_user, version();'
pg_restore --exit-on-error --single-transaction --no-owner --no-acl --dbname="${PGDATABASE:?Set the destination database name}" "${MIGRATION_DUMP_PATH:?Set the verified source backup path}"
```

The restore uses destination connection credentials from libpq settings; its database argument is a plain database name. [Transactional restore](https://www.postgresql.org/docs/current/app-pgrestore.html) aborts on errors. Verify the complete restore before starting the API. Do not seed production data over the restored database. Recreate any separately required database roles/grants deliberately: `pg_dump` does not export cluster-global roles.

### Backend service settings

| Setting | Value |
| --- | --- |
| Source | This repository, reviewed deployment commit |
| Root directory | `/backend` |
| Configuration | Service settings; legacy `railway.toml` is retained for existing deployments |
| Builder / Dockerfile | Dockerfile / `Dockerfile` relative to the backend build context |
| Build and start overrides | Unset; use the Dockerfile |
| Runtime | Node 24, defined by the Dockerfile |
| Health path / timeout | `/health` / 300 seconds |
| Restart policy | On failure, maximum 3 retries |
| Port | `PORT=3000`, public domain target port 3000 |
| Storage | PostgreSQL and Redis have persistent volumes; API needs no upload volume |

The current Railway API rejects assigning a legacy config-file path as deprecated. The destination uses explicit service settings instead; future infrastructure-as-code changes should follow [Railway's migration guidance](https://docs.railway.com/infrastructure-as-code#migrating-from-config-as-code).

The Dockerfile runs `npx prisma migrate deploy`, `node dist/scripts/bootstrap-catalog.js`, `node dist/scripts/pre-deploy-indexes.js`, then `node dist/index.js`. The catalog bootstrap creates only the three Free/Pro plans and two Pro subscription products from the current seed catalog. Its transactional, create-only upserts preserve existing/restored rows and never create demo users or customer data. This makes an empty database usable for registration and catalog reads; it does not restore accounts or purchase history. Allow startup to apply pending migrations and create the entitlement index concurrently. Do not replace it with `npm start`, which would skip those steps. Use the target database and Redis service's **private-network reference variables** in the API; operator dump/restore connections require a separately reachable endpoint or tunnel.

### Backend environment inventory

Set optional variables only when a real value exists; omit unused keys rather than inserting blank values. Never copy old database/Redis hostnames into the new references.

| Purpose | Names and configuration |
| --- | --- |
| Database and sessions | `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET` |
| Runtime | `PORT` (3000), `NODE_ENV` (production), `ADMIN_EMAILS` |
| Public URLs | `API_BASE_URL` (public HTTPS API origin, **without** `/v1`), `PUBLIC_PROPOSAL_BASE_URL` (public website origin plus `/proposal`) |
| Browser origins | `CORS_ORIGIN` (comma-separated public website origins, including apex and `www` where used) |
| Image generation | `FAL_KEY` for the new fal image integration; `GOOGLE_AI_API_KEY` and `PIAPI_API_KEY` only if retaining those fallbacks |
| AI estimates, materials, labor | `DEEPSEEK_API_KEY` |
| Distributed cache / limits | `REDIS_URL` |
| Email | `RESEND_API_KEY`, `RESEND_FROM_EMAIL` |
| Maps / contractors / materials | `GOOGLE_MAPS_API_KEY`, `GOOGLE_PLACES_API_KEY`, `SERPAPI_API_KEY` |
| Google sign-in | `GOOGLE_OAUTH_IOS_CLIENT_ID`, `GOOGLE_OAUTH_WEB_CLIENT_ID` |
| App Store verification | `APP_STORE_ISSUER_ID`, `APP_STORE_API_KEY_ID`, `APP_STORE_API_PRIVATE_KEY`, `APP_STORE_ENVIRONMENT` (Production for the production service) |
| Push notifications | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` (`Res.ProEstimate-AI`), `APNS_PRIVATE_KEY`, `APNS_PRODUCTION` (true for App Store/TestFlight) |

### Web service settings

The website's existing production domain currently runs outside Railway. Its replacement service uses `/web` as the build context and the included Node 24 multi-stage `Dockerfile`. It builds Next.js standalone output and runs `node server.js` as the nonroot `node` user. Set `PORT=3000`, `NODE_ENV=production`, domain target port 3000, and health path `/api/health`.

Set `NEXT_PUBLIC_API_BASE_URL` and `API_BASE_URL` to the public API origin **with** `/v1`; they should agree. `NEXT_PUBLIC_API_BASE_URL` is baked into the client build, so rebuild after changing it. Set `DEEPSEEK_API_KEY` for server-side support chat; keep it out of public-prefixed variables. Attach the website's existing custom domains and change DNS only after the replacement service is ready. Preserve the proposal path and existing share tokens.

## Hostnames and final verification

The released iOS app uses the old Railway hostname from `ProEstimate AI/App/AppConstants.swift`. Existing installations will continue using that hostname until an app update. A new Railway-generated domain does not redirect those clients automatically. Preserve or restore routing for the original hostname if Railway allows it; otherwise an iOS release is required. Prefer a controlled custom API domain for future deployments after DNS access is available.

Changing `API_BASE_URL` only affects newly constructed URLs. If the origin changes, inspect and transactionally rewrite **only URLs hosted on the old API origin** in `Asset.url`/`thumbnailUrl`, `AIGeneration.previewUrl`/`thumbnailUrl`, `Company.logoUrl`, `Proposal.heroImageUrl`, and relevant JSON snapshots. Keep external supplier/user URLs untouched. Existing PDFs may embed old links and cannot be repaired by changing database URL fields alone.

Before accepting traffic:

1. Compare source and target table counts, IDs, `_prisma_migrations` history, critical monetary/usage totals, and checksums/byte totals for every image and PDF column. Check constraints and index validity. Compare against the frozen source snapshot, not a source that has resumed writes.
2. Confirm `/health` reports PostgreSQL **and Redis** connected; inspect migration, image-runtime, and startup logs without exposing secrets. Schedule target volume backups and verify restore procedures.
3. Validate existing-user login/token refresh, Apple/Google login, old photos/logos/PDF downloads, entitlements, free/paid usage, one image preview, AI estimate/material/labor output, proposal approval, invoice totals, transactional email, and push registration/delivery.
4. Restore or update the App Store Server Notifications URL to `/v1/commerce/webhooks/app-store` on the public API origin. Reconcile notifications received during the write freeze and confirm transaction idempotency. Check Google API restrictions and website CORS against the new origins.
5. Switch website/API routing and release any required iOS update. Keep source data and the verified backup until the destination is stable. Once target writes begin, rolling traffic back to an old snapshot requires reconciling those writes; do not run two independent writable copies.

Completion evidence must include the deployed commit, service health, backup/restore verification, preserved-data comparisons, working integration checks, and hostname/client cutover status. Until those checks pass, report migration as incomplete.
