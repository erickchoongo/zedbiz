# Milestone 8 implementation and verification report

Review date: 9 September 2026. Scope: offline cached reads, durable paid-sale/expense synchronization, and device-generated receipt PDFs. PostgreSQL remains authoritative. Milestone 9 has not been started.

## 1. Files created and changed

The following is the functional change inventory. There is no Git repository in this checkout, so this is not a Git-generated diff; formatting and earlier uncommitted work cannot be attributed through Git history.

| Area | Files |
| --- | --- |
| New local persistence and synchronization | `mobile/lib/core/offline/local_database.dart`, `open_database.dart`, `offline_client.dart`, `sync_status_screen.dart` |
| Application integration and session handling | `mobile/lib/main.dart`, `app/app.dart`, `app/app_controller.dart`, `core/network/api_client.dart` |
| Business and cached-read UI | `features/businesses/presentation/business_shell.dart`, `features/products/presentation/products_screen.dart`, `features/customers/presentation/customers_screen.dart`, `features/debts/presentation/debts_screen.dart`, `features/reporting/presentation/dashboard_screen.dart`, `reports_screen.dart` (under `mobile/lib`) |
| Sales, expenses and product models | `features/sales/application/sale_cart_controller.dart`, `features/sales/domain/sale.dart`, `features/sales/presentation/sales_screen.dart`, `features/expenses/domain/expense.dart`, `features/expenses/presentation/expenses_screen.dart`, `features/products/domain/product.dart` (under `mobile/lib`) |
| New PDF implementation | `mobile/lib/features/sales/application/receipt_export.dart`, `mobile/assets/fonts/NotoSans-Regular.ttf`, `OFL.txt` |
| Flutter dependencies and Web assets | `mobile/pubspec.yaml`, `pubspec.lock`, `web/index.html`, new `web/flutter_bootstrap.js`, `web/offline_shell.js`, `web/sqlite3.wasm`, `web/drift_worker.dart.js` |
| Backend concurrency and recovery | `backend/app/models/product.py`, `schemas/product.py`, `schemas/sale.py`, `schemas/expense.py`, `services/sales.py`, `api/v1/routes/products.py`, `inventory.py`, `sales.py`, `expenses.py` |
| Backend tests and disposable runner | New `backend/tests/test_offline_sync.py`, `backend/scripts/verify_m8_postgres.py`; updated `tests/conftest.py` and plan-code fixtures in `test_sales.py`, `test_inventory.py`, `test_credit_sales.py`, `test_customers_and_debts.py`, `test_expenses_and_reporting.py` |
| Flutter verification | New `mobile/test/offline_sync_test.dart`, `offline_recovery_test.dart`, `receipt_export_test.dart`, `live_offline_integration_test.dart`, `mobile/tool/web_storage_check.dart`, `mobile/tool/verify_web_cdp.py` |
| Documentation | `README.md`, `docs/architecture.md`, `database.md`, `api.md`, `product-requirements.md`, new `offline-sync.md` and this report |

## 2. Dependencies added

Flutter direct dependencies: `drift 2.34.4`, `drift_flutter 0.3.1`, `crypto 3.0.7`, `connectivity_plus 7.3.1`, `pdf 3.13.0`, and `printing 5.15.0`. Compatible transitive versions are in `pubspec.lock`. Drift's matching Web worker/SQLite WebAssembly assets and the OFL-licensed Noto Sans font are bundled. No backend runtime dependency was added. Browser/PDF inspection tooling is installed outside the application dependency manifests.

## 3–6. Local database architecture, version and tables

Drift manages transactional SQLite, stored in application documents on native targets and persistent OPFS/IndexedDB on Web. Database name: `zedbiz_offline_v1`; schema version: **1**; queued payload version: **1**. SQL is parameterized. Decimal strings are retained; money calculations use minor units and quantities use thousandths.

`cached_reads` has a composite account/business/query key, JSON snapshot, update timestamp and stale flag. It stores verified membership/commercial context, catalogue, fetched histories/details/receipts and server aggregates. `sync_operations` stores account/business, operation UUID/type, versioned immutable payload/fingerprint, safe preview, state, retry timestamps/count, friendly error and accepted server ID. `sync_leases` coordinates concurrent runners across connections. No passwords or tokens are stored in these tables.

Fresh schema creation and reopen preservation are tested. This is the first schema release, not a tested upgrade from an older released SQLite schema. Unsupported future upgrades fail without deleting the database; unsupported queued versions are retained for review.

## 7. Queue state machine

PENDING moves to SYNCING, FAILED for incompatible payloads, or explicitly CANCELLED. SYNCING moves to SYNCED, PENDING after transient/authentication interruption, FAILED, or CONFLICT. Failed/conflicting operations require review and are not retried automatically. Cancellation requires a safe, explicit action; an ambiguous attempted write cannot be discarded before reconciliation. SYNCED and CANCELLED are terminal. Stranded SYNCING records recover after acquiring an expired lease. Successful sync prunes terminal metadata older than 30 days; unresolved financial intent is retained.

## 8–10. Offline read/write matrix and exclusions

| Resource/action | Offline support |
| --- | --- |
| Product catalogue and search | Complete last successful paginated catalogue; projected availability |
| Customers, debts and payment history | Previously cached recent lists/details; no inferred live balances |
| Sales, expenses and receipts | Cached server records and separately labelled local pending records |
| Dashboard | Cached today/week/month snapshots, timestamp/staleness label |
| Reports | Previously fetched query results only |
| Paid sale | CASH, MTN/AIRTEL/ZAMTEL money, bank transfer and OTHER; durable queue |
| Expense | Durable queue with existing role restrictions |
| Customer Credit and repayments | Online only |
| Sale/expense voids and stock administration | Online only |
| Product/customer mutations and commercial/platform administration | Online only |

An uncached read requires connectivity. Offline availability is not a promise of current server data. No offline credit, automatic conflict merging, inventory mutation, accounting expansion or Milestone 9 functionality was added.

## 11–13. Sale/expense workflows and operation IDs

Completing a paid cart validates cached authorization and catalogue versions, calculates exact totals, persists the payload and provisional preview, then attempts synchronization. The UI confirms device storage and pending status. Optional payment reference, discount and internal notes are retained. Local quantities reserve projected stock. An accepted response replaces the temporary identifier with the canonical sale number and server ID.

Expense capture uses the same durable-before-network path with category, amount, date, payment method and description. Cashier restrictions remain enforced. Accepted records are retained in cached history even if a subsequent refresh loses connectivity.

Each user intent receives one UUID, reused on all retries. Canonical JSON and SHA-256 detect altered replay payloads. Server list responses expose the operation ID so accepted/local records can be deduplicated. A retry first reconciles possible prior acceptance, protecting against a committed request whose response was lost.

## 14–18. Runner, ordering, retries, errors and connectivity

`syncPendingOperations()` provides one in-process flight plus a SQLite business lease. Operations run sequentially by creation time, with UUID as the tie-breaker. A transient error stops that pass. Business requests arriving during another run are processed afterward. Leases last two minutes and renew between operations; server idempotency remains the final duplicate protection.

Network/timeouts and HTTP 500/502/503/504 return operations to PENDING with persistent exponential backoff, starting at 10 seconds and capped at 15 minutes. HTTP 404/409 become CONFLICT; domain failures including 402/403/422 become FAILED. Authentication failures pause rather than destroy work. Permanent conflicts do not loop indefinitely.

Startup/business opening, foreground resume, connectivity restoration, online capture and manual Sync Now trigger synchronization. Connectivity is a hint, verified through API requests. There is no background service or continuous retry timer. Manual sync can retry before the automatic retry deadline. The last successful refresh timestamp is recorded only if connectivity and account identity remain valid after refresh.

## 19–20. Authentication, subscription and role policy

Tokens remain in the existing secure storage. Transient refresh failure retains tokens and the queue. Offline recording requires verified membership and commercial snapshots no older than 24 hours, a permitted OWNER/MANAGER/CASHIER role, ACTIVE/GRACE_PERIOD subscription and writes allowed. Future-dated snapshots fail closed. `OFFLINE_AUTH_HOURS` is configurable at build time. The server always rechecks current rights and subscription when accepting mutations.

Historical reads/export remain available under normal read permissions after subscription expiry. Read-only reconciliation can recover an operation accepted before expiry without granting permission to create a new transaction.

## 21–23. Product conflicts, stock projection and review UX

The backend computes `sale_version` from product/business identity, selling price, inventory tracking and active status. The sale request carries this token; the server compares it while holding existing product row locks before mutating inventory. Stock, cost and cosmetic fields are excluded. Legacy callers without a token retain their original fingerprint behavior.

Projected stock equals cached authoritative stock less PENDING/SYNCING quantities. It is a local estimate; only PostgreSQL determines acceptance. Price or stock changes produce a review state with a friendly reason. The app never silently replaces captured prices or quantities. Staff can refresh products and cancel safely rejected local intent, then record a reviewed replacement. Accepted records use the normal online void workflow.

## 24–26. Refresh, isolation and logout

Catalogue refresh follows every 100-item page and only replaces the complete snapshot after success. Core refresh covers recent 20-item histories/details, customer/debt data, receipts and dashboard periods. Other report queries cache when read. Writes invalidate business snapshots; pending values remain separate from server reporting totals.

Every cache/queue access includes account and business. Business/account/verified-role changes reset scoped navigation and invalidate affected cached context. Another account cannot retrieve the prior account's queue through the application. Logout clears authentication and in-memory context while preserving queued work for the same returning account. SQLite is not encrypted by this milestone; this is application isolation, not protection against a person with filesystem/browser-profile access.

## 27–28. Pending and sync-status UI

The business shell shows online/offline status and pending/review counts. Sale/expense history and details label local status. Pending receipts are provisional; local identifiers cannot be mistaken for official sale numbers. Sync Status provides Sync Now, product refresh, summaries, friendly errors and confirmed safe cancellation. Customer Credit, repayments and stock administration cannot submit offline. Cached aggregates show freshness and keep pending transactions separate.

## 29–30. Receipt PDF and sharing/export

`ReceiptExport` maps customer-safe receipt data into a locally generated, paginated A4 PDF with bundled Noto Sans. It includes business contact, receipt number, Lusaka date/time, seller, item quantities/prices, discount, totals, payment/reference, status and footer. Internal notes, cost and profit are excluded. Provisional exports prominently say PENDING SYNC and NOT SERVER-CONFIRMED. Filenames use `ZedBiz_Receipt_<sanitized-number>.pdf`.

Native Share calls the platform share sheet; native Export calls system printing/Save as PDF. Web share/export downloads the PDF. Copyable text is retained as fallback. Tests exercise the platform abstraction and long multi-page content. A PDF from the live PostgreSQL sale was generated, extracted and visually inspected. Native share-sheet interaction has not been exercised without an Android target.

## 31. Backend changes

Added computed product tokens, optional request tokens, response operation IDs and read-only sale/expense reconciliation endpoints. Existing sale row locking, atomic stock deduction, commercial/role gates and idempotency remain authoritative. No PostgreSQL schema migration was required. Test subscription-plan codes were shortened to fit the actual PostgreSQL `varchar(32)` constraint; assertions were not weakened.

## 32–39. Executed verification and source-control status

| Check | Result and scope |
| --- | --- |
| Backend SQLite suite | **79 passed** on 9 September |
| Backend PostgreSQL suite | **79 passed** on 8 September against a disposable PostgreSQL database |
| PostgreSQL migrations | All seven applied to fresh disposable databases; latest live run 9 September |
| Flutter suite | **68 passed, 1 skipped** on 9 September; the skipped live test ran separately below |
| Flutter analyze | **No issues found** |
| Live API + Flutter SQLite | **Passed** on 9 September: K250 CASH capture, file reopen, one sale/stock deduction, canonical history, expense reopen/lost response/reconciliation, price and stock conflicts, PDF generation. Dashboard and sales report verified after sync: K250 sales, K100 gross profit, K79.99 expenses, K20.01 after expenses. Disposable database and credentials removed |
| Flutter Web | JavaScript release build passed; WebAssembly application compilation is not supported by the existing secure-storage Web dependency |
| Installed Chrome | Persistent SQLite values/queue and account/business isolation passed across browser-process restart with network disabled; offline app rendered and screenshot inspected. Both COOP/COEP and plain local-server headers passed. No page exceptions |
| Android | Debug APK build passed; emulator API address is `http://10.0.2.2:8000` |
| Android target execution | Not executed: no configured emulator or attached phone |
| Source control | No `.git` repository in this directory or its parents. No commit, branch, push or Git initialization performed |

The Flutter tests cover exact decimal/quantity serialization, local schema creation/reopen, account/business separation, stale authorization, payload compatibility, queue ordering/leases, immutable retry intent, lost responses, conflicts, offline controls and pending UI, catalogue pagination beyond 100 products, stale labels, PDF safe mapping, names and pagination. The backend tests cover token conflicts, unchanged legacy/cosmetic/cost behavior, receipt safety and recovery after commercial expiry. Mocked network failures are identified as such; the live runner uses actual HTTP and PostgreSQL with transport disconnection/lost-response injection.

Browser verification found and corrected competing service workers: the custom Flutter bootstrap now leaves the application scope to `offline_shell.js`. The Chrome check uses an isolated disposable profile and the installed browser through CDP, with the backend's existing `websockets` dependency. It does not require Playwright or a browser download. Browser storage and shell startup were exercised directly; authenticated sales UI behavior was exercised by Flutter widget tests and the separate live API integration test, not a browser login automation.

## 40. Limitations

Android compilation is verified; physical/emulator operation and native sharing still need device acceptance. Web durability depends on browser storage support and site-data retention; unsafe/in-memory storage refuses offline capture. Initial online asset/cache preparation is required. HTTPS is required outside localhost. Local cache is not encrypted or an off-device backup. Deleting app/site data can lose unsynchronized intent. Lease recovery may require waiting up to two minutes and triggering sync again. Some arbitrary historical queries are unavailable offline until fetched. Reports use server acceptance timestamps and authoritative totals, not device capture times. Production signing, hosting and device rollout are outside this local milestone verification.

## 41. Exact local PowerShell commands

Run from this workstation. Credentials remain in the existing external runtime environment file; do not paste it into logs.

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
$runtimeDir = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local'
$flutterExe = 'C:\dev\flutter\bin\flutter.bat'
$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
docker desktop start
docker compose --env-file "$runtimeDir/runtime.env" up -d --build
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health

Push-Location backend
uv sync --frozen
Remove-Item Env:ZEDBIZ_TEST_DATABASE_URL -ErrorAction SilentlyContinue
& .venv/Scripts/python.exe -m pytest -q
Pop-Location

Push-Location mobile
& $flutterExe pub get
& $flutterExe analyze
& $flutterExe test --no-pub
& $flutterExe build web --no-pub --no-wasm-dry-run --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8000
& $flutterExe build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8000
& $flutterExe devices
& $flutterExe emulators
Pop-Location

& backend/.venv/Scripts/python.exe backend/scripts/verify_m8_postgres.py --runtime-env "$runtimeDir/runtime.env" --flutter $flutterExe --output-directory $runtimeDir

# Serve the built app using the existing external launcher/snapshot.
New-Item -ItemType Directory -Force "$runtimeDir/web" | Out-Null
Copy-Item mobile/build/web/* "$runtimeDir/web" -Recurse -Force
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\Desktop\Start-ZedBiz.ps1
```

The APK targets the Android emulator's host alias. For a physical phone, rebuild with the workstation's reachable LAN API URL; do not use `10.0.2.2` on a physical phone. Logs and generated verification artifacts are in `%LOCALAPPDATA%\ZedBiz-Local`.

Browser restart verification uses a separate copy of the built Web assets; the verification page is not shipped with the served app:

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
$runtimeDir = Join-Path $env:LOCALAPPDATA 'ZedBiz-Local'
Push-Location mobile
& C:\dev\flutter\bin\dart.bat compile js tool/web_storage_check.dart -o "$runtimeDir/storage-check.js"
Pop-Location
New-Item -ItemType Directory -Force "$runtimeDir/web-verification" | Out-Null
Copy-Item mobile/build/web/* "$runtimeDir/web-verification" -Recurse -Force
Copy-Item "$runtimeDir/storage-check.js" "$runtimeDir/web-verification" -Force
Set-Content "$runtimeDir/web-verification/storage-check.html" '<html><body>Running...<script src="storage-check.js"></script></body></html>' -Encoding UTF8
& backend/.venv/Scripts/python.exe mobile/tool/verify_web_cdp.py --web-dir "$runtimeDir/web-verification" --chrome 'C:\Program Files\Google\Chrome\Application\chrome.exe' --output-directory $runtimeDir
& backend/.venv/Scripts/python.exe mobile/tool/verify_web_cdp.py --web-dir "$runtimeDir/web-verification" --chrome 'C:\Program Files\Google\Chrome\Application\chrome.exe' --output-directory $runtimeDir --no-isolation-headers
```

To repeat the full backend suite on a new disposable PostgreSQL database, without touching the working business database:

```powershell
Set-Location C:\Users\Administrator\Desktop\Zed-Biz
@'
import os, subprocess, sys, uuid
from pathlib import Path
import psycopg
from psycopg import sql
runtime = Path(os.environ['LOCALAPPDATA'])/'ZedBiz-Local/runtime.env'
cfg = dict(line.split('=', 1) for line in runtime.read_text().splitlines() if '=' in line and not line.startswith('#'))
name = 'zedbiz_test_' + uuid.uuid4().hex
with psycopg.connect(host='127.0.0.1', user=cfg['POSTGRES_USER'], password=cfg['POSTGRES_PASSWORD'], dbname=cfg['POSTGRES_DB'], autocommit=True) as admin:
    admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
    try:
        url = f"postgresql+psycopg://{cfg['POSTGRES_USER']}:{cfg['POSTGRES_PASSWORD']}@127.0.0.1:5432/{name}"
        env = dict(os.environ, ZEDBIZ_TEST_DATABASE_URL=url)
        subprocess.run([sys.executable, '-m', 'pytest', '-q'], cwd='backend', env=env, check=True)
    finally:
        assert name.startswith('zedbiz_test_')
        admin.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(name)))
'@ | & backend/.venv/Scripts/python.exe -
```

Local evidence: `m8-flutter-tests.log`, `m8-analyze.log`, `m8-postgres-tests.log`, `m8-live-final.log`, `m8-web-build.log`, `m8-android-final.log`, `m8-browser.log`, `m8-browser-plain.log`, `m8-live-receipt.pdf`, and `m8-web-offline-startup.png` under the external runtime directory. The local API is running at `http://127.0.0.1:8000`; the updated application is served at `http://localhost:8080`.
