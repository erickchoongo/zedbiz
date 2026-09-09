# Milestone 8: offline storage, synchronization, and receipt export

The local SQLite database is an offline cache and mutation queue. PostgreSQL remains the authoritative business datastore.

PostgreSQL remains the authoritative datastore. Flutter's local SQLite database is a cache and durable synchronization queue.

An offline transaction is not server-confirmed until synchronization succeeds.

Offline sale synchronization may fail if authoritative product, inventory, permission, or subscription state changed while the device was disconnected.

Customer Credit and debt repayments remain online-only in Milestone 8.

## Scope

| Operation | Offline behavior |
| --- | --- |
| Business, membership, commercial status | Last verified account-scoped snapshots |
| Products/services | Full paginated catalogue refresh; local search, prices and projected stock |
| Customers and debts | Previously fetched recent lists/details/balances; debt payment history when cached |
| Sales and receipts | Recent cached server history/details/receipts plus separately labelled local transactions |
| Expenses | Recent cached history and local transactions |
| Dashboard | Cached today/week/month server snapshots with last-update information |
| Reports | Only previously fetched query/date-range results; no local reporting engine |
| Paid sale creation | Durable queue: CASH, MTN_MONEY, AIRTEL_MONEY, ZAMTEL_MONEY, BANK_TRANSFER, OTHER |
| Expense creation | Durable queue; cashier note restrictions retained |
| Customer Credit sale, repayment | Internet required; credit is never changed to another payment method |
| Voids, stock add/adjust/damaged/lost, product lifecycle/edit/create | Internet required |
| Customer mutations, subscription/platform administration | Internet required |

## Local database

Drift manages SQLite connections, transactions and schema migration. Native devices use the application documents directory; Web uses Drift's OPFS/IndexedDB implementations. The database name is `zedbiz_offline_v1`, schema version **1**, payload version **1**. Explicit parameterized SQL keeps the cache schema independent of backend ORM models; generated Drift model code is not required.

`cached_reads` contains `user_id`, `business_id`, `cache_key`, `data_json`, `updated_at`, and `stale`. Its composite primary key isolates account, business, and query. It holds business/membership/commercial snapshots, the complete product catalogue, recent domain lists/details and immutable receipt data, and server aggregate snapshots. JSON is stored inside transactional SQLite records, not in ad-hoc files. Decimal strings are preserved unchanged.

`sync_operations` contains the account/business scope, stable `client_operation_id`, known `operation_type`, `payload_version`, canonical `payload_json`, SHA-256 `payload_fingerprint`, customer-safe `preview_json`, explicit state, attempt count, last attempt, next retry, created/updated timestamps, last error code/message and accepted server resource ID. Its composite primary key prevents duplicate local insertion. `sync_leases` coordinates runners sharing the same database; expired leases permit process-restart recovery.

Future upgrades must add explicit, non-destructive migration steps. Unsupported database schema upgrades fail without deleting the file. Incompatible queued payload versions enter FAILED for review; they are not submitted or discarded. Never reset a production database to resolve an upgrade error. For development, reset only a disposable test database after verifying it contains no unsynchronized financial activity. App uninstall, browser site-data deletion, private browsing and OS storage loss can erase local data; the local queue is not an off-device backup.

## Authorization and isolation

Offline creation requires both membership and commercial verification within **24 hours**, configurable with `--dart-define=OFFLINE_AUTH_HOURS=24`. Both snapshots must be no later than the current clock; backward clock jumps fail closed. The last verified role must be OWNER/MANAGER/CASHIER and commercial state ACTIVE/GRACE_PERIOD with writes allowed. Stale verification displays “Connect to the internet to verify your subscription before recording new transactions.” PostgreSQL checks current membership, permissions and commercial state again when accepting a write.

Authentication tokens remain in the existing secure-storage implementation. SQLite never stores passwords, access/refresh tokens, JWT signing secrets, PINs, OTPs or card credentials. The secure token's subject selects a cache namespace; a decoded subject alone does not establish authorization. Previously verified server identity and business membership snapshots establish offline context.

Logout clears tokens and closes authenticated navigation. It retains unsynchronized records, which only the same signed-in account can access again. Another account receives a distinct cache and queue scope. Business switching resets the screen scope; replay always uses the persisted original business ID. Verified role changes invalidate cached business records and update membership context. Existing historical data may remain on disk even after access is revoked; it is not exposed through another account's UI.

Operational data is sensitive and SQLite is not encrypted by this milestone. No custom cryptography or new password store was introduced. Device access controls and browser profile protection matter. Web capture is refused for Drift's in-memory or unsafe IndexedDB fallback modes.

## Capture and state machine

The cart remains editable in memory until completion. On completion, the client persists the financial intent and preview transactionally **before** sending it. Sale/expense creation uses the same durable path online, protecting against a lost HTTP response. A UUID is generated once for each user intent and reused with identical serialized payload on every attempt. Exact money uses integer minor units/decimal strings; quantities use integer thousandths/decimal strings. Floating-point arithmetic is not used for financial serialization.

| Current state | Allowed next states |
| --- | --- |
| PENDING | SYNCING, FAILED (unsupported payload), CANCELLED |
| SYNCING | SYNCED, PENDING (transient/auth), FAILED, CONFLICT |
| FAILED / CONFLICT | CANCELLED after safe explicit review |
| SYNCED / CANCELLED | Terminal locally |

SQLite stores lower-case enum names; UI shows explicit labels. A crashed SYNCING operation recovers to PENDING after acquiring the queue lease. Pending sale display numbers use `Pending #...`, never a fabricated backend receipt number. UI metadata `local_sync_state` is separate from backend COMPLETED/VOIDED or RECORDED/VOIDED status. Confirmation says “Sale saved on this device — waiting to sync.” or “Expense saved on this device — waiting to sync.” An accepted result replaces the local identifier with its server ID/number. Server responses expose `client_operation_id` to avoid duplicate pending/server history entries.

## Runner, retry and conflict handling

`syncPendingOperations()` is the explicit entry point. Startup/business opening, app resume, connectivity restoration, new online capture, and manual Sync Now trigger foreground synchronization. Connectivity is a hint; actual requests determine reachability. There is no background Android service or continuous polling. Backoff metadata survives restart; automatic retries occur at the next eligible foreground trigger, and manual Sync can retry early.

Requests run sequentially per business in `(created_at, client_operation_id)` order. In-process single flight and SQLite leases prevent concurrent runners. A transient failure stops that ordered pass. Queued business requests arriving while another business is syncing are handled afterward. Leases expire after two minutes and renew between operations; server idempotency remains the final protection against crashes and clock anomalies.

Network errors/timeouts and HTTP 500/502/503/504 return to PENDING with bounded exponential delays (10 seconds on the first attempted failure, capped at 15 minutes). HTTP 404/409 become CONFLICT; other domain failures such as 402/403/422 become FAILED. Permanent failures are not automatically retried. Authentication uses the existing single-flight refresh path; unavailable/revoked sessions pause the queue. A transient refresh failure retains tokens instead of clearing them.

On repeated attempts, read-only `POST /sales/reconcile` or `/expenses/reconcile` first checks whether the identical operation was already accepted. These endpoints validate the original request fingerprint and current read permissions without requiring an active subscription. This recovers a lost response even if the subscription expired after acceptance. A missing operation falls back to the normal canonical create endpoint. These are domain recovery reads, not an alternate offline datastore.

Sync Status shows connectivity, pending/review counts, saved operation summaries, friendly error reasons, Sync Now, product refresh and confirmed local cancellation. Quantities and prices are never changed automatically. An attempted transaction with ambiguous acceptance cannot simply be cancelled; it must first be reconciled. Accepted transactions use the normal server void workflow. There is no raw JSON editor or automatic conflict merge. Failed/conflict records are never automatically pruned; terminal SYNCED/CANCELLED queue metadata is retained for 30 days before pruning during successful sync.

## Sale-critical product token and stock

Product responses expose a computed SHA-256 `sale_version` over a version prefix, product/business IDs, two-decimal selling price, inventory-tracking flag and active flag. No PostgreSQL migration is necessary. Optional sale-item `sale_version` is included in request fingerprinting only when supplied, preserving legacy online fingerprints. The server checks it under the existing product row locks before changing anything. A price or relevant setting mismatch returns HTTP 409. It never changes a K100 offline sale into a K120 accepted sale.

Stock, cosmetic fields and cost are excluded from this token. Cosmetic edits do not reject a sale; costs snapshot the authoritative server value at acceptance, preserving existing profitability behavior. Stock is still checked separately under row locks.

Projected availability is cached server stock minus PENDING/SYNCING quantities. The unsynced effect is not written into the authoritative stock snapshot. Failed/conflict/cancelled transactions cease reserving projected stock. Successful acceptance updates local stock and refreshes authoritative catalogue data; cache uncertainty is conservative and the server always performs final stock validation.

Canonical `sold_at`/`created_at` use existing server acceptance time. Device capture time is retained locally for staff information, not trusted for reports. Therefore a sale captured before midnight but accepted after midnight belongs to the server acceptance period. No `occurred_at` field or Milestone 7 reporting semantic change was introduced.

## Cache refresh and receipt export

Product refresh follows every backend page (100 per request) before replacing the complete catalogue. Core refresh fetches recent 20-item histories/details, debt summary/payment history, receipts, and today/week/month dashboard snapshots. Previously fetched queries are cached; arbitrary uncached reports require connectivity. Pending values are never added to server dashboard totals. Mutations mark the business cache stale; aggregate UI includes timestamps and stale labels.

PDF receipts are generated locally from the customer-safe `ReceiptData` mapping using `pdf`, bundled OFL-licensed Noto Sans, and `printing`. A4 pagination supports long names/multiple pages. They include business contacts, SALES RECEIPT, canonical number/date in Lusaka, seller, quantities/prices/totals/discount, payment/reference, status and Thank you. Cost, profit and internal notes are excluded. Pending previews state PROVISIONAL RECEIPT / PENDING SYNC and NOT SERVER-CONFIRMED. These are sales receipts, not tax invoices or ZRA fiscal documents.

Native Share opens the platform share sheet; Export uses system printing/Save as PDF. Web Share/Export downloads a PDF without requiring PDF.js or a network font. Text copy remains available as fallback. Safe filenames contain only the receipt number: `ZedBiz_Receipt_<sanitized-number>.pdf`. Historical export is not gated by subscription write access.

The Web service worker caches public application assets only, never API responses. Serve Web over HTTPS (localhost works for development), with correct `.wasm` MIME type. COOP/COEP headers improve Drift support; use a persistent browser profile. Wait for initial online asset/cache preparation before relying on offline restart. Bump the shell cache version when shipping changed assets.

The custom `web/flutter_bootstrap.js` starts Flutter without registering Flutter's generated service worker. This leaves `offline_shell.js` as the single service worker for the application scope. Installed-Chrome checks verify process restart, SQLite queue persistence and offline application rendering with and without COOP/COEP headers. See [the implementation report](milestone-8-report.md) for commands and evidence.

## Dependencies and sources

Direct additions: drift 2.34.4, drift_flutter 0.3.1, crypto 3.0.7, connectivity_plus 7.3.1, pdf 3.13.0, printing 5.15.0. Compatible transitive dependencies are locked in `pubspec.lock`. No new backend runtime dependency.

Implementation references: [Drift setup](https://drift.simonbinder.eu/setup/), [Drift Web and persistence limitations](https://drift.simonbinder.eu/platforms/web/), [printing](https://pub.dev/packages/printing), [pdf](https://pub.dev/packages/pdf). Web assets come from the matching [Drift 2.34.4 release](https://github.com/simolus3/drift/releases/tag/drift-2.34.4); font licensing is bundled alongside the font.

Milestone 9 and all excluded financial/administrative offline workflows remain out of scope.
