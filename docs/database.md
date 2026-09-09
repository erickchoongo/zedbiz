# Database Conventions

PostgreSQL is ZedBiz's system of record. SQLAlchemy 2.x supplies mappings and sessions; Alembic owns every production schema change. Application startup must never call `Base.metadata.create_all()` as a migration strategy.

## Required conventions

- Public entity identifiers normally use UUIDs. Internal surrogate keys may be considered only with a documented reason.
- Every business-owned row is tenant-scoped. Future migrations should add appropriate foreign keys, composite uniqueness, and indexes containing the tenant identifier.
- Money is represented with explicit-scale PostgreSQL `NUMERIC` columns and decimal application values, never `REAL`, `DOUBLE PRECISION`, Python `float`, or Dart `double`.
- Persist timestamps as timezone-aware UTC values. Convert to `Africa/Lusaka` only at user-facing boundaries.
- Financial records are corrected through audit/reversal entries, not destructive deletion.
- All schema changes are generated, reviewed, and applied through Alembic.

The initial migration remains an empty Milestone 1 baseline. Revision `20260829_0002` introduces the Milestone 2 identity and tenancy schema.

## Identity and tenancy schema

- `users`: normalized unique email, Argon2 password hash, safe profile fields, active/admin flags, and UTC timestamps. A database check enforces lowercase email storage.
- `businesses`: business details, activity flag, and centralized defaults of `ZMW` and `Africa/Lusaka`.
- `business_memberships`: user/business foreign keys, OWNER/MANAGER/CASHIER role, activity flag, tenant lookup indexes, and a unique `(user_id, business_id)` constraint.
- `refresh_sessions`: hashed refresh token, expiry, revocation and use timestamps, plus an optional replacement-session reference for rotation history.

All public IDs are UUIDs. Users do not contain a `business_id`; membership is the explicit many-to-many boundary.

## Transactions

Repositories issue queries and stage changes but never commit. Services own commits and rollbacks. Business plus OWNER membership creation is atomic. Refresh rotation revokes the old session and inserts the replacement atomically.

## Migration workflow

From `backend/`:

```powershell
uv run alembic upgrade head
uv run alembic revision --autogenerate -m "describe the change"
uv run alembic downgrade -1
```

Autogeneration is a starting point, not a substitute for reviewing constraints, indexes, data migrations, downgrade behavior, locks, and tenant safety.

## Milestone 3 commercial tables

- `subscription_plans`: stable unique plan code, name, currency, `NUMERIC(12,2)` price, billing period, grace days, activity, and UTC timestamps.
- `subscriptions`: one row per business, plan foreign key, stored status, start/current period/grace/cancellation timestamps, period-order checks, and status/date indexes.
- `subscription_payments`: immutable external payment records with exact amount/currency, method/reference, paid and covered periods, recording admin, duplicate-reference protection, and business/date index.
- `onboarding_records`: one row per business with exact fee, payment state, onboarding state, optional external reference/assignment/completion, and internal notes.
- `audit_logs`: actor, optional business, action, entity identity, JSONB metadata on PostgreSQL, and timestamp indexes. The SQLAlchemy test variant uses JSON on SQLite.

Revision `20260830_0003` follows `20260829_0002`. It also backfills an unpaid/not-started onboarding record for businesses that predate Milestone 3. The Founder plan is intentionally seeded by an idempotent management command rather than a migration so running migrations does not overwrite intentional production plan changes.

All money uses Python `Decimal` and PostgreSQL `NUMERIC(12,2)`. API money fields are two-decimal strings and Flutter converts them to integer minor units. Monthly billing preserves the calendar day and end-of-month anchors: January 31 advances to February month-end, and a subsequent month-end renewal advances to March month-end.

One transaction owns each of these workflows:

- business + OWNER membership + onboarding record;
- subscription activation + payment + audit event;
- renewal + payment + audit event;
- onboarding state/payment changes + audit events.
# Milestone 4 inventory schema

`products` stores tenant-scoped catalogue data, exact prices, current stock projection, low-stock threshold, tracking and lifecycle flags. SKU and barcode are unique per business when present. `inventory_movements` stores opening, added, manual-adjustment, damaged, and lost movements with before/delta/after quantities, actor, reason, optional unit cost, and a business-scoped operation ID. Database checks enforce nonnegative values and `after = before + delta`; foreign keys and indexes support tenant and chronological access.

Migration `20260830_0004` creates both tables after the commercial foundation. Downgrade removes the ledger before products.

## Milestone 5 sales schema

Migration `20260830_0005` adds `sale_counters`, `sales`, and `sale_items`, and extends inventory movements with `SALE` and `SALE_VOID`. `sales` stores exact totals, one recorded payment method, seller, operation fingerprint, lifecycle and void metadata. Business-scoped unique constraints protect receipt numbers, sale operation IDs, and void operation IDs.

`sale_items` stores business and sale context plus immutable name, SKU, inventory-mode, unit selling price, unit cost, quantity, line revenue, line cost, and line profit snapshots. A composite foreign key ensures its business matches its sale. Money is `NUMERIC(12,2)` and quantity is `NUMERIC(18,3)`. Database checks enforce positive quantities, nonnegative financial inputs, discount bounds, total equations, and valid status/payment values.

Lines are rounded to ZMW cents with `ROUND_HALF_UP`; sale totals sum the rounded lines. Sale-level `gross_profit = total_amount - total_cost`, so discounts reduce gross profit without artificial per-line allocation. Services contribute revenue/cost but never create stock movements.

## Milestone 6 customer-credit schema

Migration `20260902_0006` creates `customers`, `debts`, and `debt_payments`, adds nullable `sales.customer_id`, and extends the sale payment constraint with `CUSTOMER_DEBT`. Existing Milestone 5 rows remain unchanged with no customer link.

- `customers` stores tenant-owned normalized contact data, internal notes, and active lifecycle state. A composite unique key on `(id, business_id)` supports tenant-safe child references; indexed business/name, phone, and email fields support listing and search.
- `debts` represents credit-sale-only receivables. Each row has one same-business customer and sale, exact original/paid/outstanding amounts, derived lifecycle state, optional local due date, creator, settlement metadata, and void metadata. `(business_id, sale_id)` is unique.
- `debt_payments` is the append-only repayment ledger. It stores the same-business debt/customer, exact positive amount, external payment method/reference, business-scoped operation UUID and fingerprint, receiver, UTC payment time, and optional internal notes.

Composite foreign keys prevent linking a sale, customer, debt, or repayment across businesses. Debt checks enforce positive original amount, nonnegative balances, paid not exceeding original, and state/balance/timestamp consistency. For non-voided debt, `outstanding = original - paid`; a VOIDED unpaid debt preserves its original amount while active outstanding is zero. Payment checks reject zero/negative amounts and `CUSTOMER_DEBT` as a repayment method.

Customer credit and repayments use `NUMERIC(12,2)`/Python `Decimal`; clients never submit authoritative debt balances or status. Due dates use `DATE` because they are business-calendar commitments, while event timestamps remain timezone-aware UTC.

The downgrade is intentionally data-protective. It succeeds for an empty Milestone 6 schema, but refuses to remove the feature while any customers, credit sales, debts, or repayments exist. This avoids silently deleting or reclassifying financial history merely to restore the Milestone 5 payment constraint.

## Milestone 7 expense ledger and reporting indexes

Migration `20260903_0007` creates `expenses` after `20260902_0006`. Each row stores business scope, category, description, exact `NUMERIC(12,2)` amount, non-credit payment method/reference, local expense date, optional notes, recorder, lifecycle state, creation fingerprint, and optional void actor/reason/time/operation metadata.

Database checks require positive amounts, supported categories and payment methods, a nonblank description, valid RECORDED/VOIDED status, and internally consistent void metadata. Business-scoped unique constraints protect create and void operation UUIDs. Business/date plus status, category, payment, and recorder indexes support bounded ledger/report reads. No stored dashboard summary is introduced; totals are derived from authoritative sales, expenses, debts, and products.

The Milestone 7 downgrade is data-protective: it removes an empty expense table, but refuses to discard any recorded or voided expense history.

Debt repayments are not additional sales revenue. Revenue is recognized from the originating completed sale.

Voided sales and voided expenses do not contribute to active dashboard and report totals.

'After Expenses' is calculated as recorded gross profit minus recorded non-voided expenses. It is a simplified management metric and is not a formal accounting net-profit statement.


## Milestone 8

Local SQLite schema v1 adds cached_reads, sync_operations and sync_leases. All financial operations include immutable account/business scope and stable operation UUIDs. Payload schema v1 retains exact decimal strings. PostgreSQL tables and all seven existing migrations remain unchanged: sale_version is computed from sale-critical product fields. See [offline-sync.md](offline-sync.md) for migration and retention policy.
