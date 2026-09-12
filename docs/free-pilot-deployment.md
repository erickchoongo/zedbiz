# Free Pilot 1 deployment

This is a second deployment path: GitHub source, Render Free FastAPI, Supabase Free PostgreSQL and Cloudflare Pages Free Flutter Web. Existing Docker/VPS/Caddy, backup and disaster recovery files remain available for paid infrastructure. This guide prepares a small internal pilot, not a production availability guarantee. No provider accounts, deployments or URLs were created during repository preparation.

Use the actual values supplied by your dashboards. Uppercase values in `.env.free-pilot.example` are placeholders, not working credentials. Keep all passwords, certificates, dumps and operator configuration outside this checkout. No database or administrator secrets belong in Flutter.

## Before starting

Use PowerShell from the repository root. Install Git, Python 3.12, uv, Flutter **3.47.1** (the verified SDK), and PostgreSQL command-line tools (`psql`, `pg_dump`, `pg_restore`). Use a PostgreSQL client at least as new as the hosted server; the existing local Docker restore environment uses PostgreSQL 17. The [official PostgreSQL Windows download page](https://www.postgresql.org/download/windows/) links installers with command-line tools. A new local database server is not required. Keep Docker Desktop for local restore drills.

```powershell
git status --short
git branch --show-current
git rev-parse HEAD
git remote -v
uv --version
flutter --version
psql --version
pg_dump --version
```

Stop if the checkout contains unreviewed changes. Never run the backend test suite against Supabase or a business database: tests deliberately recreate test tables. Store deployment notes and secrets in a password manager/private directory outside Git. Do not use PowerShell transcription while entering secrets.

## A. Create and connect GitHub

1. Sign in to GitHub. Select **New repository**, choose your owner and a repository name, preferably **Private** for the internal pilot.
2. Leave initialization with README, `.gitignore` and license unchecked; the local repository already exists. Create the repository.
3. Copy its HTTPS clone URL from **Quick setup**. Run these commands yourself; preparation does not push code:

```powershell
git switch pilot/free-deployment
$repoUrl = Read-Host 'Paste the actual GitHub HTTPS clone URL'
git remote add origin $repoUrl
git remote -v
git push -u origin pilot/free-deployment
```

If `origin` already exists, inspect it instead of adding/replacing it blindly. Authenticate through Git Credential Manager/GitHub's normal sign-in flow; do not paste a token into a remote URL. The branch to deploy is `pilot/free-deployment`. Source, migrations, `backend/uv.lock`, `mobile/pubspec.lock`, documentation and templates are tracked. Environment files, credentials, local databases, dumps, keystores, generated builds and logs are ignored. Review `git diff --cached` before future commits.

## B. Create Supabase and prepare PostgreSQL

### Create a dedicated database project

1. Sign in to Supabase, create/select a Free organization and choose **New project**. Select a region near the future Render service. Save the strong generated project database password in your password manager.
2. Use a dedicated ZedBiz project. If offered an API connectivity choice, choose connection strings only. Otherwise open the dashboard's **Data API integration overview** (linked from the official guide) and turn **Enable Data API** off before creating ZedBiz tables. Do not add ZedBiz tables to Realtime publications. ZedBiz's authorization is in FastAPI; directly exposing its tables would bypass that boundary. No Supabase SDK, Auth or browser database access is used. See [Supabase API security](https://supabase.com/docs/guides/api/securing-your-api).
3. Wait for project provisioning. Open **Connect**, choose PostgreSQL connection information and **Session pooler**. Copy the exact host, database, port and project reference. Use **5432**, not the transaction pooler's **6543**. The direct connection is also usable where IPv6 works; session pooling supports IPv4 and suits the existing persistent SQLAlchemy connection pool. See [connection methods](https://supabase.com/docs/guides/database/connecting-to-postgres).
4. Download the database CA certificate from the project's connection/SSL settings, save it outside Git as `supabase-ca.crt`, and enable database SSL enforcement where the dashboard provides it. Clients below require certificate **and hostname** verification. Follow [Supabase SSL enforcement](https://supabase.com/docs/guides/platform/ssl-enforcement); never fix a certificate failure by switching to `disable` or disabling verification.

### Create separate migration and runtime roles

The managed `postgres` account is for setup only. Render must use `zedbiz_app`, which has table CRUD permissions but no schema ownership, role creation, database creation, superuser or RLS bypass permissions. `zedbiz_migrator` owns only ZedBiz tables and is used on the workstation for controlled migrations. The role script deliberately fails on existing role names: do not rerun it on a configured/shared project or drop roles to make it pass. It does not change Supabase-owned schema ownership. See [Supabase PostgreSQL roles](https://supabase.com/docs/guides/database/postgres/roles).

```powershell
$env:PGHOST = Read-Host 'Exact Supabase SESSION pooler hostname'
$env:PGPORT = '5432'
$env:PGDATABASE = 'postgres'
$projectRef = Read-Host 'Actual Supabase project reference'
$env:PGUSER = "postgres.$projectRef"
$env:PGSSLMODE = 'verify-full'
$env:PGSSLROOTCERT = (Resolve-Path (Read-Host 'Local path to downloaded CA certificate')).Path
psql -W -v ON_ERROR_STOP=1 -c 'SHOW server_version;'
if ($LASTEXITCODE -ne 0) { throw 'Connection/SSL verification failed' }
psql -W -v ON_ERROR_STOP=1 -f deploy/supabase-roles.sql
if ($LASTEXITCODE -ne 0) { throw 'Role setup failed; inspect before proceeding' }
psql -W
```

At the interactive `psql` prompt, set separate randomly generated passwords (at least 32 characters) using the password manager. `\password` prompts privately; do not write password SQL into the dashboard/history:

```text
\password zedbiz_migrator
\password zedbiz_app
\q
```

The session pooler login is `zedbiz_migrator.PROJECT_REF` or `zedbiz_app.PROJECT_REF`; PostgreSQL's `current_user` is the underlying role. Direct connections instead use the bare role name. Do not grant these roles to Supabase's `anon`, `authenticated` or `authenticator` roles.

### Run migrations deliberately from the workstation

Use the same Git commit as the impending backend deployment. Render Free has no remote shell or one-off job support, and pre-deploy commands are a paid feature. Therefore schema changes are an explicit workstation step, never a startup/build side effect. See [Render Free](https://render.com/docs/free) and [deployment stages](https://render.com/docs/deploys).

The connection-string format is:

```text
postgresql://zedbiz_migrator.PROJECT_REF:URL_ENCODED_PASSWORD@SESSION_POOLER_HOST:5432/postgres?sslmode=verify-full
```

Percent-encode reserved password characters. Existing `postgresql+psycopg://` URLs also work; ordinary `postgresql://` and `postgres://` normalize to the installed psycopg driver without changing the query/password. SQLAlchemy and Alembic preserve `sslmode` and use the `PGSSLROOTCERT` certificate file. A missing/untrusted certificate fails the actual connection.

Use this helper to avoid putting the complete URL into command history or console output:

```powershell
function Set-ZedBizDatabaseUrl {
    $secretUrl = Read-Host 'Paste the complete database URL privately' -AsSecureString
    $env:DATABASE_URL = [System.Net.NetworkCredential]::new('', $secretUrl).Password
}
Set-ZedBizDatabaseUrl # paste MIGRATOR URL
$env:DATABASE_SSL_REQUIRED = 'true'
# This workstation process runs CLI commands only, never an HTTP service.
# Render separately forces production validation at every startup.
$env:APP_ENV = 'development'
$env:REQUIRE_PRODUCTION = 'false'
Push-Location backend
uv sync --frozen
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
uv run alembic current
if ($LASTEXITCODE -ne 0) { throw 'Cannot read database revision' }
uv run alembic heads
uv run alembic upgrade head
if ($LASTEXITCODE -ne 0) { throw 'Migration failed; do not deploy' }
uv run alembic current
Pop-Location
```

The local CLI configuration above does not launch an API or relax the Render entrypoint. It allows schema administration before public URLs exist while still enforcing verified database TLS. Never copy its `APP_ENV`/`REQUIRE_PRODUCTION` values into Render. Do not use `create_all()`, reset the hosted database or run downgrade commands to resolve an unexplained error. Before later migrations, take a backup, review upgrade compatibility with the running version, and pause pilot use when needed.

### Seed the existing Founder Plan

Switch to the **APP** URL using the helper; keep the local CA and SSL settings:

```powershell
Set-ZedBizDatabaseUrl # paste APP URL, not postgres or migrator
Push-Location backend
uv run python -m app.cli seed-founder-plan
if ($LASTEXITCODE -ne 0) { throw 'Founder Plan seed failed' }
Pop-Location
```

This existing command creates the Founder Plan only when absent; rerunning it does not duplicate plans. K200 onboarding and K79/month remain unchanged. Verify the runtime role before deployment:

```powershell
$env:PGUSER = "zedbiz_app.$projectRef"
psql -W -v ON_ERROR_STOP=1 -c 'SELECT current_user, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls FROM pg_roles WHERE rolname=current_user;'
psql -W -v ON_ERROR_STOP=1 -c 'SELECT version_num FROM alembic_version;'
```

The four privilege flags must be false, and the revision must match `alembic heads`. Readiness also enforces these checks. Keep the Data API disabled; do not solve access errors by granting `anon`/`authenticated` access to ZedBiz tables.

### Bootstrap the platform administrator after deployment

Once the Web app and API work, register a separate administrator account through normal ZedBiz registration. Use its real email in the existing CLI against the **APP** URL:

```powershell
$adminEmail = Read-Host 'Email of the existing ZedBiz administrator account'
Push-Location backend
uv run python -m app.cli promote-admin --email $adminEmail
Pop-Location
```

Read the interactive confirmation before answering. The command is idempotent, requires an existing user and records an audit entry. There is no public administrator registration endpoint or default password. Ordinary business owners should remain ordinary owners. Log in again as the promoted account and use the existing authenticated platform-admin workflow to confirm/waive onboarding and activate the existing subscription. Select the existing business ID; do not create a second business or insert subscription rows directly. The API routes and request schemas are documented in the existing [onboarding guide](../README.md) and source `backend/app/api/v1/routes/admin.py`.

## C. Prepare the Render backend

1. Sign in to Render. Select **New → Web Service**, connect GitHub, authorize only the intended repository, and select it.
2. Select branch `pilot/free-deployment`, region near Supabase, runtime **Python**, instance type **Free**. Choose a service name; copy the actual generated URL from the dashboard after creation, never predict it.
3. Enter these settings:

| Setting | Value |
| --- | --- |
| Root Directory | `backend` |
| Build Command | `uv sync --frozen --no-dev` |
| Start Command | `.venv/bin/python ops/start_render.py` |
| Health Check Path | `/api/v1/health/ready` |
| Auto-Deploy | Off; deploy manually after migrations |

The optional `deploy/render-free.yaml` expresses the same settings; the first deployment is easier to inspect in the dashboard. It is a template, not an already provisioned service. Python and uv versions are pinned through the supported [Render version settings](https://render.com/docs/python-version).

4. Under **Environment**, set the following values. The example file is a checklist; fill real values in Render's secret environment UI, not in Git:

| Variable | Required value |
| --- | --- |
| `PYTHON_VERSION` | `3.12.14` |
| `UV_VERSION` | `0.12.6` |
| `APP_ENV` | `production` |
| `REQUIRE_PRODUCTION` | `true` |
| `DATABASE_SSL_REQUIRED` | `true` |
| `DATABASE_URL` | Actual `zedbiz_app` session-pooler URL with `?sslmode=verify-full` |
| `PGSSLROOTCERT` | `/etc/secrets/supabase-ca.crt` |
| `JWT_SECRET` | Independent password-manager-generated random secret, at least 32 characters |
| `CORS_ORIGINS` | Actual Pages HTTPS origin, no trailing path; set in E |
| `TRUSTED_HOSTS` | Actual Render hostname, followed by `,127.0.0.1,localhost` for probes |
| `DB_POOL_SIZE` | `2` |
| `DB_MAX_OVERFLOW` | `0` |
| `WEB_CONCURRENCY` | `1` |

5. Add a **Secret File** named `supabase-ca.crt` containing the downloaded CA certificate. Render places it under `/etc/secrets/`. No private certificate key is needed. Do not set `PORT`; Render supplies it. `RENDER_GIT_COMMIT` supplies source metadata automatically. Do not upload migration/admin credentials to the Web Service.
6. If the creation wizard starts an initial deploy before you know both provider URLs, it must fail closed while the required environment values are missing. Do not add fake origins, wildcards or development settings to force it through. Copy the assigned Render HTTPS URL, perform D, then complete the exact hosts/CORS and manually deploy in E. No running API is required to build/upload Flutter assets.

Startup binds `0.0.0.0` on Render's validated `PORT`, uses one worker, no reload, and forces production plus verified database TLS. Liveness is `/api/v1/health`; readiness is `/api/v1/health/ready`. Readiness requires a usable restricted database role and the exact migration head. Neither endpoint exposes credentials.

Forwarded headers are deliberately not trusted by this entrypoint. Per-IP limits may therefore aggregate users behind Render's proxy; account-based limits remain active. This conservative setting is suitable for the small internal pilot. Do not use `FORWARDED_ALLOW_IPS=*`; establish the provider's trusted proxy boundary before changing this for a larger deployment.

## D. Build and upload Flutter Web to Cloudflare Pages

Use **Pages Direct Upload**, building locally with the verified Flutter SDK. GitHub holds the source but Pages does not pull/build it in this workflow. This avoids depending on a provider image having Flutter or introducing Actions credentials. A Direct Upload project cannot later switch to Git integration in place; create another Pages project if you later choose that path. See [Cloudflare Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/).

1. Copy the real Render base URL from its dashboard, without `/api/v1` or any trailing route. The app appends existing API paths itself.
2. From the clean repository root, prepare dependencies and build:

```powershell
$apiUrl = (Read-Host 'Actual Render HTTPS base URL').TrimEnd('/')
Push-Location mobile
flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency installation failed' }
Pop-Location
& .\scripts\build-pilot.ps1 -Target web -Environment production -ApiUrl $apiUrl -RequestTimeoutSeconds 90
```

If Flutter is not on PATH, add `-Flutter C:\dev\flutter\bin\flutter.bat` to the last command. The helper invokes `flutter build web --release`, embeds version/build/Git metadata, and supplies `--dart-define=API_BASE_URL=...`, `--dart-define=APP_ENV=production` and `--dart-define=API_REQUEST_TIMEOUT_SECONDS=90`. Only public configuration is compiled. Default development/VPS request timeout remains 15 seconds. Development uses `http://127.0.0.1:8000`; a future custom HTTPS API uses the same `API_BASE_URL` mechanism.

3. Inspect `mobile/build/web`: `index.html`, `_headers`, `flutter_bootstrap.js`, `main.dart.js`, `offline_shell.js`, SQLite worker/WASM and assets must exist. Never upload the locally verified development build with a localhost API.
4. In Cloudflare, open **Workers & Pages → Create application → Get started → Drag and drop your files** (choose Pages if prompted). Create a project, upload the **contents** of `mobile/build/web` as the supported folder/ZIP, and select **Deploy site**. `index.html` must be at the upload root, not inside an extra `web/` directory. Choose a production deployment, then copy the actual production `https://…pages.dev` URL. No custom domain, Node installation or Cloudflare build command is needed. Dashboard uploads allow up to 1,000 files and 25 MiB per file; do not omit required assets to meet a limit.

| Pages item | Chosen workflow |
| --- | --- |
| Source repository | Your GitHub repository from A |
| Source branch | `pilot/free-deployment` |
| Build location | Local workstation, Flutter 3.47.1 |
| Build command | `scripts/build-pilot.ps1` command above |
| Output | `mobile/build/web` |
| Provider build variables/secrets | None; upload prebuilt assets |
| Public build variables | API origin, app environment/version/commit and 90-second timeout |

The checked-in `_headers` supplies content-type/frame/referrer protection, COOP/COEP for SQLite worker isolation, and revalidation for the shell. Pages defaults to an SPA fallback when no top-level `404.html` exists. This app uses Flutter Navigator rather than a URL-driven router: refresh loads the app and restored session; it does not promise restoration of every nested screen. No competing redirect rule is required. Verify a fresh browser load, a refresh and offline storage on the actual deployment. See [Pages serving behavior](https://developers.cloudflare.com/pages/configuration/serving-pages/) and [custom headers](https://developers.cloudflare.com/pages/configuration/headers/).

## E. Connect the two HTTPS origins and validate

1. In Render **Environment**, set `CORS_ORIGINS` to the exact Pages production origin copied in D. The configuration name is **CORS_ORIGINS**, not `ALLOWED_ORIGINS`. Set `TRUSTED_HOSTS` to the exact Render hostname (no `https://`, paths or port), plus the two probe hosts listed above. Save and manually deploy the prepared commit. Do not permit every `*.pages.dev` preview or wildcard CORS.
2. Wait for Render's deployment to become healthy. Copy the actual URLs into these public PowerShell variables and probe once:

```powershell
$apiUrl = (Read-Host 'Actual Render HTTPS base URL').TrimEnd('/')
$webUrl = (Read-Host 'Actual Cloudflare Pages HTTPS origin').TrimEnd('/')
Invoke-RestMethod "$apiUrl/api/v1/health" -TimeoutSec 120
Invoke-RestMethod "$apiUrl/api/v1/health/ready" -TimeoutSec 120
$preflight = Invoke-WebRequest "$apiUrl/api/v1/auth/login" -Method Options -Headers @{ Origin=$webUrl; 'Access-Control-Request-Method'='POST'; 'Access-Control-Request-Headers'='content-type' } -UseBasicParsing -TimeoutSec 120
$preflight.Headers['Access-Control-Allow-Origin']
```

The allow-origin value must equal the exact `$webUrl`. If readiness fails, inspect Render logs for missing certificate, invalid role, migration revision, incorrect hostname/port or a paused database; never publish secrets in support screenshots. Do not disable checks to obtain a green response.
3. Open the Pages URL, register/login, then perform B's existing-user platform-admin promotion. Reopen the separate administrator session. Activate the intended existing pilot business using the existing admin API workflow; the K200 fee may be legitimately waived for internal testing and the K79 Founder subscription activated without changing pricing or duplicating rows.
4. Log in as the normal OWNER and select that business. Verify Home, Sales, Products and More, plus the implemented destinations in the [deployment checklist](free-pilot-deployment-checklist.md). Use customer credit/repayments online; verify offline queue/replay and PDF receipts separately. Local `Brown_ent-Tech` data is not automatically present in a new hosted project; this guide does not copy or recreate it. If migrating existing pilot data, stop and plan a reviewed restore rather than making a duplicate business.
5. After testing, record the deployed Git commit, both actual URLs, checklist evidence and backup location in private operator notes. Future updates require a reviewed commit, backup, controlled migrations, manual backend deploy and rebuilt/uploaded Web artifacts when public build configuration changes.

## F. Manual free-pilot backups and local restore drills

Free projects may pause after inactivity, and free backup access is not a paid production backup guarantee. Keep a manual custom-format PostgreSQL dump outside Git and a protected copy off the laptop before significant testing/migrations. See [Supabase free-project pausing](https://supabase.com/docs/guides/platform/free-project-pausing) and [database backups](https://supabase.com/docs/guides/platform/backups).

Use the **migrator** role, the actual session-pooler host and the certificate variables from B. `-W` prompts for its password. This dumps the dedicated project's ZedBiz `public` schema; it intentionally excludes Supabase-managed Auth/Storage schemas. Do not use this procedure on a project that mixes unrelated applications.

```powershell
$env:PGUSER = "zedbiz_migrator.$projectRef"
$backupDir = Read-Host 'Absolute private backup directory OUTSIDE the Git checkout'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backupFile = Join-Path $backupDir ('zedbiz-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.dump')
pg_dump -W --format=custom --schema=public --file $backupFile
if ($LASTEXITCODE -ne 0) { throw 'Backup failed; do not use this archive' }
pg_restore --list $backupFile | Set-Content "$backupFile.catalogue.txt"
if ($LASTEXITCODE -ne 0) { throw 'Backup catalogue verification failed' }
(Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash | Set-Content "$backupFile.sha256"
```

Catalogue and checksum checks detect some archive/copy failures; they do not prove recoverability. Record `alembic current`, source commit, PostgreSQL version, timestamp and domain counts during a quiet testing period in a private manifest. Keep role setup separately; archives do not preserve role passwords. Encrypt/protect backups and restrict access because they contain business data.

Periodically run the existing guarded restore script against your **local Docker database**, using the local Docker environment file, never Supabase credentials. It creates a new disposable database, rejects the live name, verifies checksum, restores in a transaction, queries domain counts and reports the migration revision. Use PostgreSQL matching or newer than the dump server. The local setup's command is:

```powershell
$localEnv = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local\runtime.env'
$restoreName = 'zedbiz_restore_free_' + (Get-Date -Format 'yyyyMMddHHmmss')
& .\scripts\restore-postgres.ps1 -EnvFile $localEnv -ComposeFile .\docker-compose.yml -BackupFile $backupFile -RestoreDatabase $restoreName -RemoveAfterVerification
```

For other machines supply that machine's actual local Docker env file. Add `-ExpectedCountsFile` with your private count manifest when available; compare the reported migration revision with the recorded head and reconcile financial totals before declaring a drill complete. Restoring a managed `public` schema into a normal local database may require review if unrelated extensions/objects were added; do not edit/drop live hosted objects to fix a drill. Existing VPS backup, scheduled managed backup and disaster recovery tooling is retained. This manual process is only the temporary pilot strategy.

Remove the workstation's database URL after operator commands and close the terminal:

```powershell
Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
```

## Free-tier operational limits

Render Free can spin down after 15 minutes without inbound traffic; waking commonly takes around a minute. The free Web build waits up to 90 seconds per API request and shows a connecting message while signing in. Existing transient-error/offline handling and idempotent sync are retained; there is no extra automatic request replay or keep-alive polling. A provider timeout can still occur earlier; wait for service recovery and retry through the existing UI. Render's filesystem is ephemeral, so do not store business data/backups there. These are small-pilot constraints, not an uptime commitment. See [Render Free restrictions](https://render.com/docs/free).

If Supabase is paused, resume it in its dashboard and wait for readiness before testing online-only workflows. Existing cached/queued functionality is limited to what Milestones 1–9 already support. Check current provider quotas before each pilot session and avoid selecting paid upgrades. The retained VPS production path remains the intended migration route when reliable availability, scaling and automated off-host recovery are needed.
