# Pilot operations runbook

Use the commands below from the repository root. Keep `$pilotEnv` outside source control. Local rehearsal uses a separate database volume and an optional loopback-only API port; it does not establish public HTTPS readiness.

```powershell
$pilotEnv = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local/pilot.env'
docker compose --env-file $pilotEnv -f docker-compose.prod.yml ps
docker compose --env-file $pilotEnv -f docker-compose.prod.yml up -d db api
docker compose --env-file $pilotEnv -f docker-compose.prod.yml logs --tail 100 api
docker compose --env-file $pilotEnv -f docker-compose.prod.yml exec -T api python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health/ready').status)"
# Stop services while retaining all data volumes:
docker compose --env-file $pilotEnv -f docker-compose.prod.yml stop api proxy
```

Do not use `down -v`, delete browser site data, or delete application SQLite to troubleshoot financial queues.

## Monitoring and logs

Poll public HTTPS liveness every minute and readiness every minute; alert on three consecutive failures. API JSON logs include timestamp, level, environment, generated request ID, route template, method, status and duration. Query strings, raw payloads, passwords, tokens and exception text are not logged by request handling. Give support the request ID; do not send credentials or private notes. Unknown routes log as `<unmatched>` to avoid reflecting arbitrary path content. Authentication outcomes use a separate event name; successful login/logout and business/financial administration have database audit records where implemented.

Watch 5xx counts, readiness failures, sustained latency, authentication 401/429 spikes, low disk space and backup age. Review sale/expense POST 402/403/409/429 trends as signals for sync restrictions/conflicts; the server does not receive full device queue telemetry. Ask affected staff to inspect Sync Status. No paid monitoring platform or public metrics endpoint is required. Deploy an external uptime probe/log collector when an operator/host is selected; none is silently configured locally.

Docker JSON logs rotate at 10 MB with five files per service. Review centralized retention if local rotation is insufficient. Backups and audit records have separate retention requirements. On Windows check `Get-PSDrive -PSProvider FileSystem`; also use `docker system df`. Alert before free disk falls below 20%; never prune database volumes as a space-recovery shortcut.

## Migration, backup and restore

Stop writes/API, run `scripts/backup-postgres.ps1`, build the new image, run `docker compose --env-file $pilotEnv -f docker-compose.prod.yml run --rm migrate`, inspect `alembic current`, start API and check readiness. The [deployment guide](deployment.md) contains exact commands. Restore only into a new database using [the recovery procedure](disaster-recovery.md). Record expected counts and any transactions captured after the backup.

## Founder plan and platform administrator

```powershell
docker compose --env-file $pilotEnv -f docker-compose.prod.yml exec api python -m app.cli seed-founder-plan
docker compose --env-file $pilotEnv -f docker-compose.prod.yml exec api python -m app.cli promote-admin --email operator@example.com
```

Replace the example email with an existing, verified operator account. Promotion is an explicit server CLI action with confirmation and an audit event; there is no public promotion endpoint or default admin password. Use `--yes` only for a reviewed noninteractive operation. The seed is idempotent and preserves K200 onboarding and K79/month Founder pricing. Production startup does not create demo users/businesses or seed plans automatically.

For the first pilot business: register a normal account, create the business, use the platform-admin workflow to record onboarding payment or an authorized waiver and activate the Founder subscription, sign in as the business operator, add products/opening stock, and run a supervised sale/receipt. Keep platform-admin and normal business accounts separate. Confirm staff understand commercial expiry and offline restrictions before independent operation.

## Sync support

Keep the device and its stored queue intact. Check connectivity and authentication, then Sync Now. HTTP 429/network/5xx retry with bounded backoff; price/stock/permission/subscription failures remain reviewable. Never edit the serialized payload or change the UUID to force acceptance. Resolve ambiguous accepted requests through reconciliation. A rejected local intent may be cancelled safely after review; accepted records use audited online voids. Customer Credit and repayments remain online-only.

## Secret rotation

Back up the protected environment file securely before changes. JWT rotation invalidates current access/refresh tokens; arrange re-login and verify pending queues remain under the same account. Do not clear queues. Database password rotation must update the actual role and its matching runtime URL together; changing the Compose file alone does not change an existing PostgreSQL role. Use the explicit bootstrap tool only after reviewing all three role passwords and schedule the API restart. Protect Docker access because it can reveal injected secrets. Keep Android signing key rotation/backup under the release owner's procedure.

## Privacy and retention

Customer business-purpose fields are name, phone/email and optional notes; do not collect national IDs, PINs, OTPs or bank credentials. Notes can still contain operator-entered personal data: minimize them and restrict access. SQLite caches are account/business scoped but not encrypted by this milestone. Device/profile access controls are required. Logout clears tokens/navigation and retains unresolved intent for the same account; it is not an OS-level secure erase. Customer PDFs omit cost, margins, internal notes and tokens, but exported PDFs/share destinations become the operator's responsibility.

Agree data/backup/audit retention and deletion responsibilities before real customer onboarding. Financial records use preservation and void patterns; there is no new destructive admin deletion feature. End pilot access deliberately, reconcile outstanding device queues, and retain or remove exported/cache data under the agreed policy.
