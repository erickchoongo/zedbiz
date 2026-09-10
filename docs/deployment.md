# Controlled pilot deployment

Use the separate production Compose project. The development database and launcher remain useful for development. A successful local rehearsal is not authorization to send pilot credentials over public HTTP.

## Prerequisites and release inputs

Docker Engine/Desktop with Compose, PowerShell, Git, Flutter with the locked dependencies, Python 3.12/uv for local checks, and an Android SDK for APK builds. The production API image installs locked runtime dependencies only and runs as `zedbiz`, without root, autoreload, writable source mounts or unnecessary capabilities. PostgreSQL 17 and Caddy 2 run as separate services. Record tested image digests at each release; the patch tags can move, so do not pull unreviewed images during rollback.

Before external deployment, obtain API/Web DNS names, operator email, an HTTPS-capable host with ports 80/443, and a protected off-host backup destination. Replace the example domains. No real deployment domain or Android release-signing identity is supplied by this repository.

## Configuration and secrets

Copy `.env.production.example` **outside Git**. Generate four independent values using `python -c "import secrets; print(secrets.token_urlsafe(32))"` for PostgreSQL administrator, migrator, application and JWT credentials. Transfer directly into the protected file; do not put values into a shell command, screenshot or chat. URL-safe generated secrets avoid connection-URL escaping problems. On this Windows workstation:

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
$pilotEnv = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local/pilot.env'
# Only for a NEW deployment: copy the template to a new path, then edit locally.
# Copy-Item .env.production.example $pilotEnv
$operator = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls $pilotEnv /inheritance:r /grant:r "$($operator):(F)"
docker compose --env-file $pilotEnv -f docker-compose.prod.yml config --quiet
```

Do not use plain `docker compose config` in shared logs: it expands secrets. Docker daemon/host administrators can inspect injected environment values; protect that access. Secrets are injected at runtime, not copied into images. Flutter only receives public environment/API/offline-policy settings.

Production/staging reject placeholder, short or low-diversity JWT secrets; unsafe database credentials; wildcard/non-HTTPS CORS; wildcard hosts; disabled limits; multiple workers; or token lifetimes exceeding 30 minutes/30 days. These checks cannot prove entropy; always use the generator. Configuration errors suppress input values. The default access/refresh lifetimes remain 15 minutes/30 days.

Set `TRUSTED_HOSTS` to the API hostname and `127.0.0.1` for the container health probe. Use exact HTTPS Web origins in `CORS_ORIGINS`. `WEB_ROOT` must be an absolute path to the intended Web release. Database URLs target private `db:5432`. PostgreSQL has no production host port mapping.

## First database setup and migration

```powershell
docker compose --env-file $pilotEnv -f docker-compose.prod.yml build api
docker compose --env-file $pilotEnv -f docker-compose.prod.yml up -d db
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm bootstrap
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic current
docker compose --env-file $pilotEnv -f docker-compose.prod.yml up -d api
docker compose --env-file $pilotEnv -f docker-compose.prod.yml exec -T api python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health/ready').status)"
```

`bootstrap` is an explicit privileged operation, never an API startup hook. It creates `zedbiz_migrator` (schema owner, no superuser/role/database creation) and `zedbiz_app` (schema usage and table CRUD/sequence access, no schema ownership or administrative privileges). Default privileges cover future migrations. The API receives only the application credential; migration/admin credentials are passed only to their one-shot services. Re-running bootstrap updates role passwords from the configured file: treat it as credential rotation, not a routine restart.

The API checks connectivity, exact Alembic heads and role safety on production startup and readiness. It does not run migrations or `create_all`. A missing/behind schema fails startup with a sanitized error.

For later releases: quiesce writes and stop the API, back up, build/tag the new image, run the migration once, inspect `alembic current`, start the new image, then check readiness and smoke-test. Do not run competing migration jobs. There is no new domain migration in Milestone 9.

## HTTPS and proxy trust

`deploy/Caddyfile` terminates HTTPS, redirects public HTTP, serves Web assets and forwards API requests. Start it only after real DNS/environment/Web assets are ready:

```powershell
docker compose --env-file $pilotEnv -f docker-compose.prod.yml up -d proxy
```

Only Caddy's fixed private address `172.30.9.10` is trusted for forwarding headers. Uvicorn does not trust arbitrary `X-Forwarded-For` values. If this subnet conflicts with the deployment network, change both the Caddy address and Uvicorn allow-list together. Do not add `*`. Direct API and PostgreSQL ports are not publicly published. Allow 80/443 through the host firewall; protect Docker/SSH administrative access.

HSTS, nosniff, frame restrictions and no-referrer apply at the proxy. The API also sends no-store, nosniff, frame and request-ID headers. Web gets COOP/COEP for persistent SQLite/CanvasKit workers. A restrictive CSP has intentionally not been guessed: validate worker/CanvasKit/PDF behavior before adding one. TLS issuance and public DNS must be verified on the actual host, not inferred from local Compose validation.

One API process/replica is the supported pilot topology. Limits are process-local, bounded fixed windows: 600 API requests/minute/IP, 30 login/minute/IP, 8 login/minute/HMAC-account key, 5 registration/minute/IP and 60 refresh/minute/IP. Limits include unsuccessful attempts and cool down automatically; no permanent account lockout. Health probes are exempt. Mobile retries HTTP 429 safely. Shared atomic limits (for example Redis) must replace the local store before scaling horizontally. Keep the proxy trust boundary intact.

SQLAlchemy uses pool size 5, overflow 5, timeout 10 seconds, recycle 1800 seconds, pre-ping and a 5-second connect timeout. One worker therefore consumes at most ten pooled application connections. Review database capacity before changing these values.

## Web and Android builds

```powershell
Push-Location mobile
& C:\dev\flutter\bin\flutter.bat pub get
& C:\dev\flutter\bin\flutter.bat analyze --no-pub
& C:\dev\flutter\bin\flutter.bat test --no-pub
& C:\dev\flutter\bin\flutter.bat build web --no-pub --no-wasm-dry-run --no-web-resources-cdn --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com --dart-define=OFFLINE_AUTH_HOURS=24
& C:\dev\flutter\bin\flutter.bat build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8000
& C:\dev\flutter\bin\flutter.bat build apk --release --no-pub --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com
Pop-Location
```

Replace the example HTTPS endpoint for a real pilot build. Production configuration fails visibly without an explicit HTTPS API URL. The local debug address is emulator-only; a physical device needs a reachable development LAN URL or the real HTTPS endpoint.

Provide `mobile/android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, `keyPassword` referencing the operator's protected release keystore. Neither file nor key is committed. Without it, release output is unsigned; it is not a pilot-distributable signed APK. Debug keys are no longer silently used for release. Do not invent a production signing identity. Verify the final APK with Android `apksigner verify --print-certs` before distribution and record certificate ownership/backup.

Publish Web assets atomically from a release directory. The custom Flutter bootstrap leaves service-worker ownership to `offline_shell.js`. Bump its cache version for a new asset release. Preserve SQLite site data and pending queues across updates. First online asset preparation is required before offline use. HTTPS is required outside localhost.

## Backup, rollback and deployment acceptance

See [disaster recovery](disaster-recovery.md), [operations](operations-runbook.md) and the [pilot checklist](pilot-checklist.md). Select an immutable previous image tag to roll application code back only if it is compatible with the current schema. A migration rollback may require restoring into a new database and a reviewed cutover; do not assume financial migrations can be downgraded safely. Never erase the only database/volume to repair a deployment.

Primary references: [Uvicorn proxy trust](https://www.uvicorn.org/settings/), [Starlette middleware](https://www.starlette.io/middleware/), [PostgreSQL pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html), [pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html).
