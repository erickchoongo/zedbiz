# Free pilot deployment preparation report

Dates: 11–12 September 2026. Scope: repository preparation for Cloudflare Pages Free, Render Free and Supabase Free PostgreSQL, using the existing Milestones 1–9 and Pilot 1. No external account or deployment success is claimed.

## 1. Git status

Initial checkout was clean; no remote existed. Changes are being committed on a separate preparation branch. Final clean status and build identity are recorded after release verification below. No push was performed.

## 2. Branch and HEAD

Started on `pilot/1-readiness` at `630d13dc148e1dd6de35159abfa529e0bc5ac532`. New branch: `pilot/free-deployment`. Implementation commit and final evidence commit will be recorded after the clean-source build; use `git log -2 --oneline` and `git rev-parse HEAD` to identify both.

## 3. Files changed

| Files | Purpose |
| --- | --- |
| `.gitignore`, `README.md` | Ignore PostgreSQL credential files; link the optional free path |
| `.env.free-pilot.example`, `deploy/render-free.yaml` | Unpopulated hosted environment and Render templates |
| `deploy/supabase-roles.sql` | Separate managed-database migration/runtime roles and verified grants |
| `backend/app/core/config.py` | Normalize standard PostgreSQL URLs and require verify-full when requested |
| `backend/ops/start_render.py` | PORT-based, one-worker production startup with hosted TLS enforcement |
| `backend/tests/test_free_pilot.py` | URL/SSL preservation and Render startup regressions |
| `mobile/lib/core/network/api_client.dart`, `mobile/test/api_client_test.dart` | Configurable timeout with delayed-response and timeout/session regression tests |
| `mobile/lib/features/auth/presentation/auth_screen.dart` | Connecting feedback during slow sign-in |
| `mobile/web/_headers`, `mobile/web/offline_shell.js` | Pages isolation/security/revalidation headers and new shell cache identity |
| `scripts/build-pilot.ps1` | Optional request-timeout build variable, default unchanged |
| Three `docs/free-pilot-*.md` files | Operator guide, unchecked remote checklist and this report |

No models, financial calculations, dependency locks or migrations were changed. VPS Compose, Dockerfile, Caddy, backup/restore scripts and disaster recovery documentation are retained.

## 4. Supabase compatibility

SQLAlchemy/psycopg remains the datastore interface; no Supabase SDK or browser DB connection. Ordinary PostgreSQL URLs normalize to the installed driver without altering encoded credentials or connection options. Session pooling on 5432 is the documented IPv4 path; direct connections require suitable network reachability. Transaction pooling on 6543 is not selected.

A disposable PostgreSQL 17 rehearsal executes the hosted-role script as a non-superuser administrator with schema grant authority, applies all existing Alembic migrations, verifies restricted runtime readiness, seeds Founder twice with one K79 plan remaining, and confirms runtime schema creation is denied. Full PostgreSQL suite results are recorded under tests. Existing NUMERIC, locks, constraints and idempotency are unchanged. Supabase's actual pooler, managed role permissions and TLS handshake still require account-based validation. Data API must be disabled so FastAPI remains the authorization boundary.

## 5. PostgreSQL SSL

`DATABASE_SSL_REQUIRED=true` rejects missing SSL mode and `disable`, `require` or `verify-ca`; it requires `verify-full`. The Render entrypoint forces this flag. psycopg receives the unchanged SSL query; `PGSSLROOTCERT` supplies the downloaded CA. libpq verifies the certificate and hostname at connection time. No global TLS disabling or change to the private VPS database transport was introduced. Hosted certificate verification is pending actual provider inputs.

## 6. Render configuration

Python Free Web Service; root `backend`; Python 3.12.14; uv 0.12.6; one worker; bounded pool 2 + 0 overflow; production/JWT/CORS/trusted-host/database-role guards retained. Actual Render PORT and commit metadata come from provider environment. Access logs and forwarded-header trust are disabled by the entrypoint. Proxy-aggregated IP limiting is documented as a small-pilot limitation.

## 7. Render build/start commands

Build: `uv sync --frozen --no-dev`.

Start: `.venv/bin/python ops/start_render.py`.

Health check: `/api/v1/health/ready`; liveness: `/api/v1/health`. Controlled workstation `alembic current`, `heads`, `upgrade head`, `current` precede manual backend deployment. No build/start migrations, reload, destructive initialization or paid-only hook.

## 8. Cloudflare Pages strategy

Build locally with Flutter 3.47.1 and Direct Upload `mobile/build/web` through the dashboard. GitHub retains reviewed source; Pages runs no provider build or Actions job. Upload the asset contents at root. Existing Navigator plus Pages default SPA fallback loads the app on refresh; no top-level 404 file is introduced. `_headers` carries worker isolation and security headers. The actual Pages upload/header/routing behavior remains on the external acceptance checklist.

## 9. Flutter Web API configuration

Use `scripts/build-pilot.ps1 -Target web -Environment production -ApiUrl $apiUrl -RequestTimeoutSeconds 90`. This supplies `API_BASE_URL` through Dart defines, with public release metadata and environment. Existing development and future custom-domain builds use the same API configuration. Default timeout remains 15 seconds; the free build uses 90 and displays connecting feedback. No credential is compiled into Flutter.

## 10. CORS

Existing environment variable is `CORS_ORIGINS`. Enter the exact actual production Pages HTTPS origin, with no wildcard or preview-domain blanket permission. Localhost development stays separately configured. The guide supplies a preflight check; no actual provider origin was invented.

## 11. Trusted hosts

`TRUSTED_HOSTS` contains the actual generated Render hostname plus `127.0.0.1,localhost` for local probes. Production rejects wildcard/URL-valued hosts. Missing provider URLs must leave initial deployment failing closed until configured, never temporarily disable validation.

## 12. Backup procedure

The guide provides prompted-password PostgreSQL `pg_dump --format=custom --schema=public`, archive catalogue and SHA256 checks outside Git, protected off-laptop copies and the existing guarded `restore-postgres.ps1` drill against a new local disposable database. Hosted backup/restore is not claimed. Existing VPS backup automation and recovery documentation remain intact.

## 13. Free-tier limitations

Temporary free-service sleep, slow cold requests, possible Supabase inactivity pausing, ephemeral Render storage, manual migration/admin operations, quotas and weaker backup guarantees are documented with official provider references in the setup guide. There is no aggressive polling or provider-specific keepalive. Existing offline scope is preserved; online-only credit/repayments do not become offline features.

## 14. Tests

Backend full SQLite suite: **110 passed**. Backend full PostgreSQL 17 suite: **110 passed**. Flutter ordinary full suite: **73 passed, 3 existing live-environment tests skipped**. A first backend run found the new startup test leaking environment changes into later tests; its environment is now isolated, and the full rerun passed. The disposable PostgreSQL rehearsal additionally verified migrations, role grants, runtime readiness, idempotent seeding and DDL rejection. Its container was removed. No existing business database was used by tests.

## 15. Flutter analyze

**PASS: No issues found** from `flutter analyze --no-pub`. The initial process completed successfully after a slow startup; a diagnostic retry was also launched before its completion result was retrieved.

## 16. Web build

Pending clean-source release build. With no actual Render URL available, local verification must use the real local development origin, never publish a localhost build or invent a provider endpoint. The operator must rebuild with the actual Render HTTPS origin before upload.

## 17. Manual external-account steps remaining

Create GitHub repository and push deliberately; create dedicated Supabase Free project and certificate/roles; configure actual database URLs; migrate and seed; create Render Free service; build and upload Pages; configure actual CORS/hosts; deploy and verify; register/promote administrator; activate the intended existing business; complete workflow and backup/restore acceptance. No account credentials, remote, external URLs or real deployment were supplied/created by this task.

## 18. Exact operator order

Follow guide A (GitHub), B (Supabase setup/migrations/seed), C (Render creation and assigned URL), D (build/upload Pages), E (final exact environment and backend deployment), deferred B admin promotion, then E workflow checks and F backup/restore. The initial Render creation may fail closed while URLs are pending; the guide explicitly explains this dependency. Do not upload the local verification artifact.

## 19. Exact commands

The [setup guide](free-pilot-deployment.md) contains executable PowerShell blocks for private database input, role setup, Alembic, seed, admin bootstrap, release build, health/preflight and backup/restore. GitHub connection, after creating an empty repository yourself:

```powershell
git switch pilot/free-deployment
$repoUrl = Read-Host 'Actual GitHub HTTPS clone URL'
git remote add origin $repoUrl
git push -u origin pilot/free-deployment
```

Local test equivalents:

```powershell
Push-Location backend
uv run pytest
Pop-Location
Push-Location mobile
flutter test --no-pub
flutter analyze --no-pub
Pop-Location
& .\scripts\build-pilot.ps1 -Target web -Environment development -ApiUrl http://127.0.0.1:8000 -RequestTimeoutSeconds 90
```

Keep test environments separate from operator migration credentials and never aim test fixtures at a business database.

## 20. Verdict

**PENDING final local verification for FREE PILOT DEPLOYMENT PREPARATION.** External deployment is not performed and all remote checklist boxes remain unchecked. This report will be finalized after analyzer, PostgreSQL suite, clean release build and final Git checks. No new feature milestone was started.
