# Pilot 1 execution guide

Pilot 1 validates the M1–9 system; it adds no business feature milestone. Read [deployment](deployment.md), [recovery](disaster-recovery.md) and [operations](operations-runbook.md) first. Existing code already provides Caddy HTTPS, a private PostgreSQL 17 volume, separate admin/migrator/application roles, explicit migrations, application readiness and external Android signing configuration.

## Inputs still required for a real deployment

The operator confirmed that hosting details, a phone and signing keystore are not yet available. Supply API and Web DNS names, hosting provider, server public IP and OS, SSH username and local key path, ACME contact email, an off-host encrypted backup destination and monitoring owner. Supply secrets through protected files on the host, never chat: four independent PostgreSQL admin/migrator/application/JWT values. Allowed Web origin is the exact HTTPS Web address. Android needs the operator-owned keystore path, alias and locally entered passwords. The existing `pilot.env` is **only the isolated localhost rehearsal**, with example domains; do not repurpose it silently for public production.

Do not create a paid hosting account, public DNS entry, remote business or upload backups without the corresponding operator inputs. No public TLS or physical-device result can be inferred from local test success.

## Production release and identity

Use a reviewed clean commit and set `GIT_COMMIT` in the protected production environment to `git rev-parse HEAD`. The production Compose file fixes `APP_ENV=production` and sets `REQUIRE_PRODUCTION=true`; a contradictory development environment fails validation. `/api/v1/health/version` returns only backend version, commit and environment. More → Pilot diagnostics shows app version/build/commit/environment, backend identity and aggregate retained queue counts for the current account/business. It contains no personal identity, tokens, request payloads or customer notes. `unknown` means build identity was not supplied; do not represent it as a traceable release.

The build wrapper reads version/build from `pubspec.yaml` and commit from Git, refuses a dirty checkout, rejects template production URLs and requires signing configuration for Android:

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
$apiUrl = Read-Host 'Actual production HTTPS API origin'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-pilot.ps1 -ApiUrl $apiUrl -Target web -Flutter C:\dev\flutter\bin\flutter.bat
# After operator signing configuration:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-pilot.ps1 -ApiUrl $apiUrl -Target apk -Flutter C:\dev\flutter\bin\flutter.bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-pilot.ps1 -ApiUrl $apiUrl -Target appbundle -Flutter C:\dev\flutter\bin\flutter.bat
```

Deploy only `mobile/build/web` as the Caddy static root. Do not mount the repository. No directory browsing is enabled; dot paths and sensitive file extensions are blocked/hidden while normal Web paths fall back to index.html. Rebuild after any source changes; preserve browser SQLite and pending queues through updates.

## Migration and health sequence

Set `$pilotEnv` to the protected environment path for the **intended** host. Reuse the existing bootstrap process only for initial role setup or deliberate rotation. Quiesce writes and take a verified backup before migration on an existing deployment. Do not downgrade or use `create_all`.

```powershell
docker compose --env-file $pilotEnv -f docker-compose.prod.yml config --quiet
docker compose --env-file $pilotEnv -f docker-compose.prod.yml build api
docker compose --env-file $pilotEnv -f docker-compose.prod.yml up -d db
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic current
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic heads
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic upgrade head
docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate alembic current
docker compose --env-file $pilotEnv -f docker-compose.prod.yml up -d api proxy
Invoke-RestMethod "$apiUrl/api/v1/health"
Invoke-RestMethod "$apiUrl/api/v1/health/ready"
Invoke-RestMethod "$apiUrl/api/v1/health/version"
```

Expect liveness/readiness 200 and the deployed production commit in version metadata. Verify externally with certificate checking enabled. Check API upstream and Web login/business/dashboard/sales/products/customers/expenses/reports/sync in a browser on another network. Neither PostgreSQL nor the API should have a public published port. The local rehearsal override is outside Git and must not be used remotely.

## Android signing and device acceptance

This safe generation command prompts for the operator's own password and certificate identity. It does not invent or display them:

```powershell
$signingDir = Join-Path $env:USERPROFILE '.zedbiz-signing'
New-Item -ItemType Directory -Force -Path $signingDir | Out-Null
$operator = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls $signingDir /inheritance:r /grant:r "$($operator):(OI)(CI)(F)"
& 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\keytool.exe' -genkeypair -v -storetype JKS -keystore "$signingDir\zedbiz-upload.jks" -alias zedbiz-upload -keyalg RSA -keysize 3072 -validity 10000
```

Create ignored `mobile/android/key.properties` locally with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`, using the real values. Use forward slashes for an absolute Windows keystore path; follow Java Properties escaping rules for password backslashes/non-ASCII characters. Restrict that file to the operator and back up the keystore/passwords separately in protected storage. Do not put passwords in command arguments or Git. For direct APK distribution this certificate signs the installed app; if adopting Play App Signing, distinguish the upload key from the Play-managed app-signing key. See [Android signing guidance](https://developer.android.com/studio/publish/app-signing).

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0\apksigner.bat" verify --verbose --print-certs mobile/build/app/outputs/flutter-apk/app-release.apk
& C:\dev\flutter\bin\flutter.bat devices
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
# Only after selecting the attached operator-approved device:
$serial = Read-Host 'Android device serial'
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s $serial shell getprop ro.build.version.release
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s $serial install -r mobile/build/app/outputs/flutter-apk/app-release.apk
```

Record model/Android version/build/commit and execute launch, login, selection, products/opening stock, cash/mobile-money/online-credit sale, repayment, expense, reports, receipt/share and logout/login. Then cache products, disconnect both network transports, capture an ordinary sale and expense, force-close/reopen offline, inspect retained operations, reconnect/sync, and compare server sale/expense IDs and stock. Repeat with interruption during sync; preserve UUIDs and verify exactly-once acceptance. Record actual steps in the issue tracker; host-side transport simulation is not Android testing. No physical device was available at preparation time.

## Daily backup and monitoring

`run-pilot-backup.ps1` wraps the existing tested pg_dump script, serializes executions with a file lock, records success/failure without exception text, writes a SHA-256 latest-backup manifest, and optionally retains the newest archive for each of 14 dates plus four weeks. Only archives recorded in its own managed catalogue are eligible for pruning; unrelated/unmanaged backups are untouched. Symlink/reparse and path checks precede deletions. It does not prune on dump failure. A retained local archive is not proof of off-host disaster recovery.

```powershell
$backupDir = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local/pilot1-managed-backups'
$monitorDir = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local/pilot1-monitor'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/run-pilot-backup.ps1 -EnvFile $pilotEnv -BackupDirectory $backupDir -Prune
& backend/.venv/Scripts/python.exe scripts/pilot_monitor.py --env-file $pilotEnv --api-url $apiUrl --backup-directory $backupDir --output-directory $monitorDir
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/register-pilot-tasks.ps1 -EnvFile $pilotEnv -BackupDirectory $backupDir -OutputDirectory $monitorDir -ApiUrl $apiUrl -Python (Resolve-Path backend/.venv/Scripts/python.exe)
Get-ScheduledTask -TaskName 'ZedBiz-Pilot1-*' | Get-ScheduledTaskInfo
```

Windows tasks run daily at 02:00 and every five minutes, respectively; overlapping instances are ignored. The supplied registration uses the current interactive operator because Docker Desktop requires that session. It is useful for this workstation rehearsal, **not unattended production reliability**. On the chosen Linux host, run the backup wrapper with PowerShell 7 (`pwsh -NoProfile -File ...`) under a restricted operational service account and a systemd timer/cron, and monitor with Python 3.12 every five minutes. Configure persistent timers, environment/volume access and external alerts for the actual host before acceptance. Do not assume a logged-out laptop will run Docker backups.

The monitor checks liveness/readiness, production identity, latest successful backup checksum/age (25-hour threshold), last backup failure and five minutes of sanitized API log counters. It emits daily JSONL plus `monitor-latest.json`; nonzero exit means attention is required. Counters include 5xx, database exceptions, rejected writes and write conflicts. They are window counts capped by 10,000 log lines, not cumulative unique incidents. Readiness covers silent database outages. Server write conflicts are **not necessarily offline sync failures**: collect actual device pending/synced/failed/conflict counts from Pilot diagnostics/Sync Status. Crashes and support requests are entered in the issue tracker. No personal analytics or external message sender is installed. Operator alert routing and an independent external uptime probe remain deployment inputs. Review/delete monitor logs after 30 days under the agreed retention policy; Docker logs already rotate.

## Off-host option and restore

One practical option is an encrypted restic repository on a separately controlled SFTP host with restricted SSH keys and host-key verification. Set it up only after the destination/credentials are supplied. Keep repository password and SSH key in protected external files. Back up the managed-backup directory, verify repository snapshots, run `restic check`, and test restoring a dump to a different host. Never use `StrictHostKeyChecking=no`. Retain at least 14 daily/four weekly snapshots; repository pruning requires explicit operator review. No off-host upload has been performed. See [restic SFTP documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#sftp).

Use the existing `restore-postgres.ps1` with a new `zedbiz_restore_...` database and expected counts for a quiesced pilot fixture. Verify business/users/products/inventory/sales/debts/payments/expenses and migration head. Never target the live pilot database. Financial reconciliation after an older restore remains mandatory as documented in disaster recovery.

## Pilot scope, UX and metrics

Use one internal business only on the isolated rehearsal; no external onboarding. `verify_pilot_business.py` uses real registration/admin CLI/admin APIs and owner APIs for onboarding, K79 Founder activation, catalogue/stock, sales/credit/repayment/expense/receipt/reports, then the existing Flutter durable-queue stress check. It cannot target a remote origin and refuses more than one rehearsal business. Test credentials and its journal stay outside Git. A started-but-interrupted offline test requires manual journal/data review before another run; do not erase the journal and replay it blindly.

The existing development business Brown_ent-Tech stays in the development database. Its owner already confirmed the main dashboard and four tabs after legitimate activation. Inventory lives under Products, repayments under Customer Credit, receipts under sale details, and Sync Status in the banner. Dedicated business settings/subscription/account-detail screens are absent; record that UX gap rather than starting a feature milestone. Record sales/expense totals and device queue counts, plus 5xx window counts/issues/support requests, without personal tracking. See [pilot issues](pilot-issues.md) and the [Pilot 1 report](pilot-milestone-1-report.md).

Primary operational references: [Caddy static serving](https://caddyserver.com/docs/caddyfile/directives/file_server), [Windows task registration](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask).
