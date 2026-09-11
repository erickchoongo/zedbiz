# Pilot Milestone 1 preparation and validation

Date: 11 September 2026. Scope: the existing M1–9 system, one controlled internal rehearsal and operational preparation. No Pilot Milestone 2 or large feature milestone was started.

## 1–3. Executive summary, source and environment

**Overall verdict: FAIL / BLOCKED for real pilot acceptance.** Local preparation and substantial production-configured rehearsal succeeded, but the operator confirmed that deployment details, an Android phone and signing keystore are unavailable. Public deployment and physical Android outcomes are not claimed.

Root: `C:\Users\Administrator\Desktop\Zed-Biz`. Work is on `pilot/1-readiness`, starting from `342af08` on clean `main`. The implementation and final evidence commits are recorded in Git; no push is authorized or performed. A final report-only commit records the reviewed implementation hash after release validation.

Existing M9 Compose/Caddy/role bootstrap/migration/signing/backup architecture was reused. Development remains a separate `zed-biz` project; Brown_ent-Tech was not duplicated or moved. The local `zedbiz-pilot` rehearsal uses separate PostgreSQL storage, independent protected credentials outside Git, production validation and a loopback API override. There is one controlled business in that rehearsal. Example domains in its environment are not real production inputs.

## 4. HTTPS

Production Caddy configuration validates. An external, uncommitted loopback override exercised the same routing/security configuration with `tls internal`, synthetic example hostnames and a local CA. Certificate validation was enabled using that CA, without installing it in the host trust store. API liveness/readiness/version returned 200; Web root and `/sales/history` returned the Flutter shell; `/.git/config` and `/.env` returned 404. HSTS/nosniff and Web COOP headers were verified. Ports were limited to `127.0.0.1:18443` and `127.0.0.1:18080`.

**This is not publicly trusted HTTPS, public DNS or outside-localhost acceptance.** No real domain/server was supplied. The repository configuration continues to use the actual Caddy ACME architecture when those inputs become available. Dot-path rejection and sensitive static-file hiding were added without breaking Web route fallback. The static root is release assets, not the checkout.

## 5–7. PostgreSQL, migrations and secrets

The rehearsal runs PostgreSQL 17 on persistent private storage, with separate admin, migrator and non-superuser application roles. The API uses the restricted application credential. No production database host port is published. No development credential was copied into this environment.

Executed `alembic current`, `alembic heads`, `alembic upgrade head`, then `alembic current` before starting the updated API. Result: `20260903_0007`; no new domain migration and no downgrade or startup `create_all`.

Existing weak/missing JWT, unsafe database and wildcard/non-HTTPS CORS tests remain. Production Compose now also sets `REQUIRE_PRODUCTION=true`; contradictory development mode is rejected. A new regression verifies that guard. Public release identity exposes only backend version, commit and environment; tests verify the exact safe response shape. Runtime secrets, temporary session fixtures, dump archives and signing inputs remain outside source control.

## 8–11. Web and Android

The app now offers More → Pilot diagnostics with app version, build number, source commit and environment, backend release identity, and counts of retained queue states for the selected account/business. It does not display tokens, payloads, personal identity or private notes. Counts describe retained device state, not lifetime or cross-device totals.

The release wrapper reads app version/build from `pubspec.yaml`, identifies the clean Git commit, injects public Dart defines, refuses template production URLs and checks for Android signing configuration. Actual production Web compilation/deployment is waiting for the real HTTPS API origin. Local Web release/build/browser evidence is recorded after the implementation commit.

`flutter devices` detected Windows, Chrome and Edge only. No Android phone is attached and `mobile/android/key.properties` is absent. No signed APK/AAB was built or installed, and no physical launch/offline restart/network interruption/share-sheet result is claimed. Existing unsigned M9 artifacts are not a signed Pilot 1 release. The [execution guide](pilot-1-operations.md) provides the exact interactive keytool command, safe keystore handling, APK/AAB build commands and device acceptance sequence. Operator passwords/identity were not invented.

## 12–14. Backups, restore and monitoring

The new backup wrapper reuses the existing custom-format pg_dump implementation. It adds an execution lock, success/failure event records, latest successful checksum manifest, latest-attempt status and optional 14 daily/four weekly retention limited to its own managed archives. A synthetic 40-day regression found and fixed a Windows PowerShell JSON-array parsing issue; the test also verifies unmanaged-file preservation and rejection of path escape. A corrected real backup succeeded.

Local tasks `ZedBiz-LocalPilot1-Backup` (02:00 daily) and `ZedBiz-LocalPilot1-Monitor` (every five minutes) were registered under the current interactive operator. The scheduled backup was manually triggered and returned task result 0. This verifies the registered action, not a completed overnight schedule or unattended server operation. A sleeping/logged-out laptop with Docker Desktop is not an adequate production backup host.

The populated pilot backup restored into a new disposable database and matched: users 2, businesses 1, products 3, inventory movements 27, sales/items 23 each, debts 1, repayments 1, expenses 11 and audit events 14. The verified restore database was removed; the live rehearsal was not overwritten. The latest corrected-wrapper archive is `zedbiz_2026-09-11_105818_7fd6bbef.dump`. Daily retention can later supersede the initially restored archive; logs retain the drill evidence. A separate disposable M9 PostgreSQL regression fixture also passed backup/restore.

Monitoring checks health/readiness/production identity, recent backup checksum and age, last backup failure, and five-minute log counts for 5xx/database errors/write conflicts/rejections. It writes daily JSONL plus `monitor-latest.json`, and returns nonzero when attention is required. During the deliberate offline conflict rehearsal it correctly reported `WRITE_REVIEW_REQUIRED` with two server 409 responses, zero 5xx and zero database errors. Those server conflict counts are not represented as two unique failed syncs. Device metrics come from diagnostics/Sync Status; crashes and support incidents require issue entries. No external notifications or personal analytics are sent.

Off-host upload, independent-host restore, external uptime checks, alert ownership and unattended production scheduling are still missing. The guide documents one encrypted restic/SFTP option; no credentials or authorization for remote upload exist.

## 15–16. One business and metrics

`ZedBiz Internal Pilot 1`, ID `bc67942e-45a8-4af0-b5f4-7554c2d7f9de`, is the sole business in the isolated production-configured rehearsal. The runner uses normal registration, the existing platform-admin promotion/Founder seed CLI, protected onboarding/subscription APIs and authenticated owner business APIs. No financial table shortcut was used. Onboarding is WAIVED/COMPLETED; subscription ACTIVE at unchanged K79/month with an explicitly labelled no-cash local-test reference. The owner is not a platform admin.

The workflow created products/opening stock, added stock, cash/mobile-money/online-credit sales, a partial repayment and expense; fetched dashboard/reports/receipt; and exercised the existing Flutter SQLite offline runner against the actual production-configured API. Twenty sales and ten expenses synchronized once after database reopen, invalid-access refresh, overlapping triggers and lost-response simulation. One deliberately price-conflicting sale remained reviewable. Offline item stock was 100 → 80.

| Metric | Observed |
| --- | ---: |
| Server sales | 23 |
| Server expenses | 11 |
| Device operations captured in stress fixture | 31 |
| Synced operations | 30 |
| Review conflicts | 1 deliberate fixture |
| Failed operations after that run | 0 |
| 5xx / database errors in observed monitor window | 0 / 0 |
| Physical Android runs | 0; device unavailable |

The offline test uses real HTTP/PostgreSQL and host SQLite with simulated transport loss. It is not a physical-device result. The temporary test queue is distinct from users' live queues. No existing device storage was cleared. A generated PDF receipt is retained outside Git in the pilot evidence directory. Crashes/support requests were not instrumented as lifetime metrics; the issue register is the reporting mechanism.

The development owner previously confirmed that Brown_ent-Tech enters its dashboard and displays Home/Sales/Products/More after legitimate activation. Its current database was not used as a benchmark fixture. No external business was onboarded.

## 17–19. Issues and fixes

See [pilot issues](pilot-issues.md) for ID/date/area/severity/device/business/description/steps/expected/actual/status/fix fields. No confirmed P0 was discovered. Three P1 acceptance blockers remain: public deployment inputs, Android identity/device, and off-host recovery/production alerting. P2 items: release diagnostics added, retention failure fixed, dedicated settings/subscription/account-detail screens deferred. P3: local onboarding/admin handoff confusion documented and resolved for Brown_ent-Tech through legitimate activation.

Existing operational navigation is functional. Inventory, repayments and receipts are nested workflows, not separate primary tabs. No redesign or broad new feature was undertaken.

## 20–21. Tests and builds

The full backend suite passed 102 tests on SQLite after the retention fix. The PostgreSQL runner also exercised real concurrency, offline policy changes, tenant isolation, migrations and a populated restore drill. Final PostgreSQL suite count and Web/build evidence are recorded after the implementation commit. Flutter passed 71 tests, with three live-only files skipped by the ordinary suite; the two M9 live files ran through their separate runners. Flutter analysis reported no issues. Caddy config, local certificate-verified proxy checks, backup/restore and monitor checks passed as described above.

No signed Android build or real-production-origin Web test is substituted with a placeholder result. No off-host backup, external notification or public hosting action was performed.

## 22–23. Remaining inputs and commands

Supply real API/Web domains, hosting provider/server IP/OS, SSH username/local key path, ACME email, protected production environment values, off-host encrypted repository and alert operator/destination. Supply an Android device and operator-generated signing keystore/passwords locally. Exact signing/build/deploy/device/off-host procedures are in [Pilot 1 operations](pilot-1-operations.md).

Core local commands used (runtime files contain rehearsal credentials; never print them):

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
$runtime = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local'
$pilotEnv = Join-Path $runtime 'pilot.env'
git switch -c pilot/1-readiness  # creation already performed; do not repeat
docker compose --env-file $pilotEnv -f docker-compose.prod.yml build api
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic current
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic heads
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic upgrade head
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic current
docker compose --env-file $pilotEnv -f docker-compose.prod.yml -f "$runtime\pilot-local.yml" up -d api
& backend/.venv/Scripts/python.exe backend/scripts/verify_pilot_business.py --env-file $pilotEnv --credentials-file "$runtime\pilot1-business\credentials.json" --output-directory "$runtime\pilot1-business" --flutter C:\dev\flutter\bin\flutter.bat
& backend/.venv/Scripts/python.exe backend/scripts/verify_m9_postgres.py --runtime-env "$runtime\runtime.env" --flutter C:\dev\flutter\bin\flutter.bat --output-directory "$runtime\pilot1-postgres"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/run-pilot-backup.ps1 -EnvFile $pilotEnv -BackupDirectory "$runtime\pilot1-managed-backups" -Prune
& backend/.venv/Scripts/python.exe scripts/pilot_monitor.py --env-file $pilotEnv --api-url http://127.0.0.1:18000 --backup-directory "$runtime\pilot1-managed-backups" --output-directory "$runtime\pilot1-monitor" --local-rehearsal
Push-Location backend
& .venv/Scripts/python.exe -m pytest -o addopts='' -q tests
Pop-Location
Push-Location mobile
& C:\dev\flutter\bin\flutter.bat test --no-pub
& C:\dev\flutter\bin\flutter.bat analyze --no-pub
Pop-Location
git status --short
```

Evidence is outside Git under `%LOCALAPPDATA%\ZedBiz-Local`: `pilot1-backend-final.log`, `pilot1-postgres.log`, `pilot1-postgres-suite-final.log`, `pilot1-flutter.log`, `pilot1-analyze.log`, `pilot1-image.log`, `pilot1-migrations.log`, `pilot1-business.log`, `pilot1-business/pilot-business-results.json`, `pilot1-expected-counts.json`, `pilot1-restore.log`, `pilot1-backup-final.log`, `pilot1-local-tls-results.json`, `pilot1-caddy-validation.log` and `pilot1-monitor/`. Raw output is not committed because operational directories can also hold credentials and business exports.

## 24. Verdict

**FAIL / BLOCKED for full Pilot Milestone 1 acceptance until the confirmed external inputs and physical-device tests are supplied and executed.** The available local preparation is implemented and tested. Do not describe this as a publicly deployed, signed, physical-Android-validated pilot. Do not start Pilot Milestone 2.
