# Milestone 9: controlled pilot hardening

Verification date: 10 September 2026. Scope ends at Milestone 9.

## 1–3. Summary, repository and Git

Engineering hardening and the local pilot rehearsal passed. This is not an assertion that a public production deployment or native Android acceptance has occurred. Live pilot admission remains conditional on the operator requirements below.

Repository: `C:\Users\Administrator\Desktop\Zed-Biz`. Git was initialized at this root on branch `main`. Baseline commit `26dc7f7` is **Milestone 8 baseline before production hardening**. Implementation commit `0512f23` is **Milestone 9 controlled pilot hardening and verification** (47 files). A following documentation-only commit records that implementation hash; use `git log --oneline -3` to see both. No remote was configured or pushed. Commits use the explicit generic identity `ZedBiz Development <development@zedbiz.local>`, not an assumed personal identity. The final working tree is checked after the documentation commit.

The implementation changes production configuration, middleware/readiness/logging, targeted validation and concurrency behavior, Docker/operations files, Flutter environment/retry/signing settings, verification scripts and documentation. It adds no business features or domain migrations. Exact inventory: `git diff --stat 26dc7f7 HEAD`.

## 4–6. Environment, secrets and production validation

Development retains its existing Compose/runtime environment. `docker-compose.prod.yml` uses a separate `zedbiz-pilot` project and volume. `.env.production.example` contains placeholders only. Real rehearsal credentials live outside Git under `%LOCALAPPDATA%\ZedBiz-Local`, with restricted file permissions. Separate randomly generated PostgreSQL admin, migrator, application and JWT secrets were used. No secrets are built into Flutter or API images.

Production and staging reject weak/placeholder JWT values, unsafe database credentials, wildcard/non-HTTPS CORS, wildcard hosts, disabled limits, multiple workers and excessive token lifetimes. Pydantic suppresses input values in configuration errors. Validation cannot prove entropy; the deployment guide requires independent `secrets.token_urlsafe(32)` values. Runtime environment access still requires a trusted Docker/host administrator.

## 7–11. Authentication, limits and network boundary

Existing Argon2 password hashing, generic login failures, refresh rotation/revocation and authorization remain in place. Refresh/logout token inputs now have explicit length bounds. Defaults remain 15-minute access and 30-day refresh lifetimes. Passwords retain the existing 8–128 character/common-password checks.

The single-process pilot has bounded fixed-window limits per minute: API 600/IP, login 30/IP and 8/HMAC-normalized-account, registration 5/IP, refresh 60/IP. Rejections return 429 with Retry-After. Entries expire; account lockout is not permanent. Raw email identities are not limiter keys. Health probes are exempt. Flutter treats 429 as retryable and preserves pending intent. Limits are not shared across processes: multiple replicas require a shared atomic limiter first.

Production CORS requires exact HTTPS Web origins. TrustedHost middleware rejects unrecognized hosts. Caddy is the only trusted forwarded-header source, at private address `172.30.9.10`; Uvicorn does not trust arbitrary client forwarding headers. PostgreSQL and the API have no public host ports in production Compose. The local rehearsal adds only a loopback API port through an external override.

`deploy/Caddyfile` provides automatic HTTPS, HTTP redirection, HSTS, security headers and Web isolation headers. Its configuration validated successfully. Actual public DNS, certificate issuance and external HTTPS connectivity were **not** tested: the rehearsal uses example domains. No public proxy was started with those placeholders.

## 12–16. Errors, logs, audit and readiness

Unexpected responses expose a generic message and generated request ID; database failures return sanitized 503 responses. Validation excludes raw input/context. Decimal input and derived sale totals are bounded before database precision overflow; custom reports are bounded to 367 inclusive days and reject overflowing dates.

Structured JSON logs include environment, event, request ID, method, route, status and elapsed time. Query strings, request bodies, raw identities, SQL parameters and exception tracebacks are excluded from request failure logs. Unmatched paths are masked. Docker logs rotate at 10 MB with five files. This does not replace an external monitoring/retention service.

Successful login/logout, business creation/update field names and repayments now add transactional audit events, complementing existing product audit events and immutable financial/inventory records. Refreshes and ordinary reads do not generate audit noise. Audit retention and operator access remain documented operational responsibilities.

Liveness measures process availability. Readiness checks database connectivity, exact Alembic heads and production database-role safety. Production startup performs these checks and fails with sanitized diagnostics; it never runs migrations or creates tables. A real isolated rehearsal confirmed liveness 200/readiness 503 during database outage, recovery to 200, and startup refusal for an incompatible schema. All seven migrations upgraded a fresh PostgreSQL database to `20260903_0007`.

## 17–20. PostgreSQL and concurrency

The explicit bootstrap service creates `zedbiz_migrator` as schema owner and `zedbiz_app` with schema usage/table CRUD/sequence privileges and future-table default privileges. Neither has administrative role attributes. PUBLIC privileges are restricted. Only one-shot operations receive admin/migration credentials. The actual application role was verified as `zedbiz_app`, without schema CREATE privilege. PostgreSQL is private in production Compose.

SQLAlchemy uses pre-ping, a five-second connect timeout, pool size 5, overflow 5, pool timeout 10 seconds and recycle 1,800 seconds. The supported single worker uses at most ten pooled application connections.

**97 backend tests passed on SQLite and on PostgreSQL.** Additional actual HTTP/PostgreSQL races passed:

| Race | Observed result |
| --- | --- |
| Two different sales consume the last unit | One 201, one 409; no negative stock |
| Same sale operation UUID consumes the last unit | Two 201 responses, same accepted sale ID |
| Same expense UUID | Two 201 responses, same expense ID |
| Two repayments exceed remaining balance | One 201, one 409 |
| Same settlement UUID | Two 201 responses, same payment ID |

The sale service now rechecks a previously accepted operation after acquiring product locks, preventing a legitimate duplicate retry from failing the last-stock check. Operation uniqueness remains enforced by PostgreSQL constraints.

## 21–23. Backup and restore

`scripts/backup-postgres.ps1` creates a custom-format pg_dump, validates its catalogue, copies it as binary and writes a SHA-256 sidecar. It reads an external environment file and never prints credentials. It removes only its unique temporary container file. There is no automatic deletion of older backups.

`scripts/restore-postgres.ps1` requires a new `zedbiz_restore_...` database, verifies the checksum, restores in one transaction and compares expected domain counts when supplied. It cannot overwrite an existing destination. Optional cleanup drops only the successfully verified disposable restore database; failed restores remain available for inspection.

The final populated backup was `zedbiz_2026-09-10_092722_46fbf733.dump`. Restore passed with matching counts: users 2, businesses 3, products 508, inventory movements 34, sales 5,026, sale items 5,026, debts 301, debt payments 3, expenses 1,012 and audit logs 9. Source and restored disposable databases were removed after verification. Working business data was not used for this drill. A separate backup of the empty restricted production rehearsal also passed.

Backups and evidence are outside Git in `%LOCALAPPDATA%\ZedBiz-Local`. Scheduled execution, encrypted off-host storage and independent recovery on another host are not configured. RPO 24 hours/RTO two hours are proposed operational targets, not measured guarantees. Restoring an older database can lose accepted operation IDs; the recovery guide requires reconciliation before resuming device sync.

## 24–28. Containers and Flutter/platform verification

The production image builds successfully with locked runtime dependencies, a non-root user, readiness healthcheck, one Uvicorn worker and no reload/access-log leakage. Compose adds a read-only API filesystem, tmpfs, dropped capabilities, no-new-privileges, separate networks, private PostgreSQL, explicit bootstrap/migration services and a Caddy proxy. No development source mount is used. Patch image tags still require recording/reviewing release digests.

Flutter production/staging require an explicit non-local HTTPS API URL. Development fallback remains available. The offline shell cache is versioned `zedbiz-shell-m9-v1`. Android release signing uses an external ignored `key.properties`; missing credentials now produce unsigned output instead of silently using a debug key.

| Check | Result |
| --- | --- |
| Flutter tests | 70 passed; three live-only tests skipped in the ordinary suite. The two M9 live test files ran separately, including all three capture/sync policy pairs; the legacy M8 live file was not rerun as a separate M9 check |
| Flutter analysis | No issues |
| Web release | Passed for production configuration and the local development endpoint |
| Headless Chrome on final Web assets | Persistent SQLite/queue, account/business isolation, browser process restart and offline app shell passed; no page errors |
| Android debug APK | Built successfully |
| Android release APK | Built successfully; **unsigned**, confirmed by apksigner rejection |
| Android execution/share sheet | Attempted target discovery; no attached device or configured emulator was available; not executed |

Build outputs are under `mobile/build`, excluded from Git. Production smoke builds use `https://api.example.com`; they must be rebuilt with the real endpoint. An unsigned APK with a template URL is not a distributable pilot release. The local M9 Web snapshot is served at `http://localhost:8080`, with the development API ready on port 8000.

## 29–30. Offline stress and policy changes

The real HTTP/PostgreSQL/Flutter SQLite runner captured 20 paid sales, ten expenses and one deliberately conflicting sale. It reopened the durable database, refreshed invalid access, ran overlapping sync triggers and simulated lost financial responses. Thirty operations synced exactly once; the conflict remained reviewable and did not block later work. Stock fell from 100 to 80. Another account could not read the queue.

Separate capture/sync Flutter processes verified authoritative subscription expiry, removed cashier membership and product deactivation. Rejected intent survived as failed/conflict state, was not silently deleted and did not retry indefinitely. Existing fixture coverage also verifies throttling, backoff, logout/account isolation and conflict handling. This is foreground synchronization, not a promise of unattended background sync.

## 31–34. Security, dependencies, tenancy and privacy

A practical source scan covered tracked and new files for actual external runtime secret values, private-key/token patterns, non-template environment files and merge markers. No findings were returned. Follow-up source review found no new debug endpoints, default production account or startup table creation. Safe example/development settings and intentional test fixtures are distinguished from production credentials. This is not a formal penetration test or comprehensive secret-history certification.

Python audit initially identified a pytest development-dependency issue. Only pytest was upgraded, from 8.4.2 to locked 9.1.1 with constraint `>=9.0.3,<10`; the final pip-audit reported no known vulnerabilities. No backend runtime dependency or Flutter dependency was added. See the [upstream pytest issue](https://github.com/pytest-dev/pytest/issues/13669). Flutter outdated review found nine lockfile-upgradable and six constraint-limited packages, plus discontinued transitive `js` and `flutter_secure_storage_macos`; broad dependency upgrades were deferred. The existing secure-storage dependency also prevents an application Wasm build; the verified JavaScript Web release works. Outdated review is not a comprehensive Flutter vulnerability audit.

Existing role/subscription/tenant tests pass. Additional cross-business UUID requests returned 404 across five domains; an ordinary owner received 403 at the platform-admin boundary. Server authorization remains authoritative for queued writes. No offline customer-credit, repayment, stock administration or void feature was added.

An accepted offline sale generated `ZedBiz_Receipt_ZB-20260910-000006.pdf`. Text and rendered-page inspection confirmed the canonical receipt number, Brown Mini Mart identity, item, quantities and ZMW 10.00 total. It contains no cost, profit, private expense notes, credentials or internal queue identifiers. Native Android sharing remains unverified. Browser/local cache privacy continues to depend on access to the user's device and browser profile; the queue is not represented as an encrypted vault.

## 35–38. Operator documentation

- [Deployment](deployment.md): secrets, roles, migration order, HTTPS/proxy trust, build/signing, rollback.
- [Disaster recovery](disaster-recovery.md): backup, verification, safe restore/cutover, queue reconciliation and recovery targets.
- [Operations](operations-runbook.md): health/logs, onboarding/admin separation, credential rotation, sync support, monitoring and privacy retention.
- [Pilot checklist](pilot-checklist.md): deployment and device acceptance items intentionally remain unchecked until performed on the real pilot environment.

## 39–41. Blockers, limitations and verdict

Before enrolling real businesses, the operator must provide real domains/host and verify public HTTPS; configure scheduled protected off-host backups and monitoring/alert ownership; supply and safeguard Android release signing credentials; and execute the documented native device/offline/share acceptance checks with the real endpoint. These are not completed by the local rehearsal.

Non-blocking pilot limitations include one API worker/replica, process-local rate limits, foreground-only sync, no comprehensive external penetration test, mutable container patch tags, deferred Flutter dependency maintenance and no validated application Wasm build. Retention and recovery targets need operator adoption.

Basic disposable-dataset performance was measured with 500 additional products, 500 customers, 5,000 sales/items, 1,000 expenses and 300 debts. Five sequential reads per endpoint yielded the following local timings; these are not production load-test guarantees:

| Endpoint | Median ms | Maximum ms |
| --- | ---: | ---: |
| Dashboard today | 40.23 | 47.98 |
| Sales report today | 429.29 | 565.91 |
| Expenses report today | 25.88 | 35.62 |
| Debt summary | 13.70 | 13.83 |
| Products, first 100 | 18.39 | 19.07 |

Existing tenant/date/operation indexes and validated constraints were inspected. No speculative indexes were added. Sales-by-day currently materializes the bounded date-range result and aggregates in Python; monitor it as pilot volume grows. An earlier run under concurrent build load was substantially slower, reinforcing that these are workstation measurements.

**Verdict: Milestone 9 engineering and local verification are complete, with live pilot rollout conditional on the documented external deployment and device requirements. Milestone 10 has not started.**

## 42. Exact local PowerShell commands and evidence

Run from the repository root. The existing external runtime files contain workstation-specific credentials; do not replace them with placeholders or display them in shared output.

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
$runtime = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local'
$devEnv = Join-Path $runtime 'runtime.env'
$pilotEnv = Join-Path $runtime 'pilot.env'
git status --short
git log --oneline -3
docker compose --env-file $devEnv up -d --build api
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\Start-ZedBiz.ps1"
Invoke-WebRequest http://localhost:8000/api/v1/health/ready -UseBasicParsing
# Open http://localhost:8080 in your browser.

Push-Location backend
uv sync --frozen
uv run pytest -q
Pop-Location
& backend/.venv/Scripts/python.exe backend/scripts/verify_m9_postgres.py --runtime-env $devEnv --flutter C:\dev\flutter\bin\flutter.bat --output-directory $runtime

Push-Location mobile
& C:\dev\flutter\bin\flutter.bat analyze --no-pub
& C:\dev\flutter\bin\flutter.bat test --no-pub
Pop-Location
docker compose --env-file $pilotEnv -f docker-compose.prod.yml config --quiet
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/backup-postgres.ps1 -EnvFile $pilotEnv -BackupDirectory (Join-Path $runtime 'pilot-backups')
```

The PostgreSQL runner creates and removes its own disposable database, applies migrations, runs the backend suite and real races, invokes Flutter stress/policy tests, benchmarks and performs the populated restore drill. Do not interrupt it unnecessarily; inspect any retained disposable database after a failure. The separate runtime outage verifier must only target the empty local rehearsal, never an active pilot; see its safety guard and the deployment guide. Exact production migration, Web/APK build, signing and standalone restore commands are in the linked guides.

Local evidence under `%LOCALAPPDATA%\ZedBiz-Local`: `m9-postgres-final.log`, `m9-postgres-results.json`, `m9-runtime-results.json`, `m9-backend-final.log`, `m9-flutter-final.log`, `m9-analyze-final.log`, `m9-browser-final.log`, `m9-web-build.log`, `m9-web-local-build.log`, `m9-android-release.log`, `m9-release-signing.log`, `m9-image-build.log`, `m9-proxy-validation.log`, `m9-python-audit-final.log`, `m9-flutter-dependencies.log` and the receipt PDF. Browser harness screenshots retain their historical `m8-web-...` filenames but were regenerated against M9 assets. Native-command stderr banners in PowerShell logs are not failure verdicts; exit status and test assertions determine the reported result.
