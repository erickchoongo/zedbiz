# Pilot disaster recovery

PostgreSQL is authoritative; a device's unsynchronized SQLite queue is not an off-device backup. Target an initial **24-hour RPO** with daily backups and a **2-hour RTO** for a small pilot. These are operating targets, not guaranteed or measured SLAs. Assign a named operator and keep a protected off-host copy.

## Daily/manual backup

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
$pilotEnv = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local/pilot.env'
$backupDir = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local/pilot-backups'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/backup-postgres.ps1 -EnvFile $pilotEnv -BackupDirectory $backupDir
```

The script creates a timestamp/unique-suffix custom-format `pg_dump`, checks archive readability, copies binary data without a PowerShell text pipe, writes a SHA-256 sidecar and fails on command errors. It does not delete old backups. It invokes PostgreSQL tools inside the existing database container using its administrative local connection; passwords are not added to command history. Access to Docker is privileged.

Use Windows Task Scheduler (or the host's scheduler) daily at a quiet time to execute the same script under the protected operator account, capturing exit status and timestamp. Alert if the last successful backup is older than 25 hours. Keep at least 14 daily and 4 weekly backups according to storage capacity; review retention deliberately. Encrypt backups at rest/off-host, restrict access and test recovery monthly. A local-only backup does not protect against host loss. The dump contains personal/business data, not PostgreSQL roles or application environment/signing secrets; protect and back up those separately.

## Disposable restore drill

```powershell
$backup = Get-ChildItem $backupDir -Filter '*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$restoreDb = 'zedbiz_restore_' + [guid]::NewGuid().ToString('N')
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/restore-postgres.ps1 -EnvFile $pilotEnv -BackupFile $backup.FullName -RestoreDatabase $restoreDb
```

The script verifies the checksum, creates a **new** `zedbiz_restore_` database (existing names fail), runs `pg_restore --exit-on-error --single-transaction --no-owner --no-privileges`, checks migration version and domain counts, and retains the result for inspection. Supply `-ExpectedCountsFile` for a known fixture's JSON counts and `-RemoveAfterVerification` only when the validated disposable result should be removed. Failed restores are not silently deleted. The pilot verification runner uses expected counts for users, businesses, products, inventory movements, sales/items, debts, repayments, expenses and audits, including offline-synced records.

This drill proves archive/data recovery, not a production cutover. For a real restore, stop writes, retain the damaged database and backup, create a new target database, configure roles/schema, restore with the migration owner (using `pg_restore --role=zedbiz_migrator` under authorized administrative access), and reapply application grants. Review exact migration compatibility and restart readiness before changing the API connection. Restore scripts intentionally refuse overwriting production.

## Outage response

1. **API unavailable:** inspect container status and sanitized logs/request IDs; test liveness/readiness. Roll back a broken image to the last compatible version. Do not reset device caches.
2. **PostgreSQL unavailable:** check container, disk/volume, credentials and network. Keep the API stopped or unready until storage is healthy. Readiness must return 503, not a connection string. Restart services only after diagnosing storage exhaustion or corruption.
3. **Failed migration:** stop rollout. Record the starting/actual Alembic heads and error type. Review transactional state; do not run `create_all` or guess a downgrade. Restore into a new database if the migration cannot safely be completed or rolled forward.
4. **Corrupted deployment/host loss:** rebuild the pinned application image, recover protected environment/roles, restore the latest tested backup to a new volume/database, and run readiness and smoke checks before DNS/traffic cutover.

Offline clients may continue permitted paid sale/expense capture within their existing 24-hour verified authorization window. They must preserve operation IDs and queues. Expired authorization requires reconnection; credit, repayments, voids and inventory administration remain online-only. Do not promise acceptance: the recovered server rechecks stock, price, role and subscription.

**Restoring an older backup can lose server idempotency records for writes accepted after that backup.** An apparently pending device may then replay a transaction absent from the restored database, while a synced device may not replay it at all. Stop automatic client reconnection during cutover, inventory post-backup transactions and receipts with operators, reconcile them deliberately, and only then resume sync. Database restore is not multi-device financial reconciliation.

## Recovery acceptance

Verify schema head, restricted app role, health/readiness, login and business isolation, recorded sale/stock/debt/repayment/expense counts, report totals, receipt privacy, pending queue recovery and absence of duplicate operation IDs. Record backup filename/hash, recovery time, database counts and operator sign-off. Preserve incident logs and the original database until the incident is closed; never put credentials or private receipts in the public report.
