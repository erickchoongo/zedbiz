# ZedBiz Architecture

ZedBiz is a mobile-first system with a Flutter Android client, a versioned FastAPI HTTP API, and PostgreSQL as the system of record. Flutter Web remains enabled for a future internal administration interface.

## Repository boundaries

- `mobile/` contains application bootstrap, shared configuration/network foundations, and feature-oriented UI code. New modules such as auth, dashboard, products, sales, expenses, customers, debts, subscriptions, and admin should be introduced under `lib/features/` only when implemented.
- `backend/app/api/` owns HTTP routing and transport concerns.
- `backend/app/core/` owns validated configuration, logging, and cross-cutting runtime setup.
- `backend/app/db/` owns SQLAlchemy engine, sessions, and declarative metadata.
- `models/`, `schemas/`, `repositories/`, and `services/` are domain boundaries. They must gain code only alongside real use cases, rather than placeholder abstractions.
- `backend/migrations/` is the only production schema evolution mechanism.

## Runtime and client flow

The client resolves its API origin from `--dart-define=API_BASE_URL=...`. It restores tokens through a storage abstraction, loads `/auth/me`, and then loads the user's active businesses. The navigation model is `User -> Business List -> Selected Business -> Business Context`. Zero-business users are directed to creation, one business may be selected automatically, and users with multiple businesses choose explicitly.

The authenticated API client attaches the access token and makes at most one refresh attempt after a 401. Refresh failure clears local authentication state. Authentication and token logic does not live in widgets. The health endpoints remain available for deployment liveness and readiness checks.

Mobile tokens use platform secure storage through `flutter_secure_storage`. The Web implementation is supported for development, but browser storage cannot provide the same device-backed guarantees as Android Keystore; production Web requires HTTPS and a separate threat-model review.

## Authentication and sessions

Passwords are hashed with Argon2 through `pwdlib`; raw passwords are never persisted. Short-lived HS256 access JWTs carry only subject, type, issued-at, and expiration. Refresh JWTs add a random session identifier. The database stores a SHA-256 hash of the complete refresh token, never the raw token.

Each refresh rotates the session: the old row is revoked, a replacement session is created, and the old row records its replacement in one transaction. Logout revokes the presented session. A future password-change workflow can revoke all active refresh sessions for the user.

## Multi-tenancy and financial integrity

Business-owned records must include and enforce a tenant/business scope in application queries and database constraints. Users and businesses are related only through `BusinessMembership`, allowing many-to-many membership. Reusable route dependencies load the authenticated user, active business, active membership, and required role from PostgreSQL. A business UUID in a URL or token is never treated as authorization.

**Security invariant: A user must never gain access to another business's data solely by obtaining or guessing its UUID.**

Business creation and its initial OWNER membership use one service-owned transaction. Repository methods never commit, allowing multi-step use cases to remain atomic. Refresh rotation follows the same service-owned transaction strategy.

Financial transactions should be immutable in normal operation. Corrections should use auditable reversals or compensating entries instead of destructive deletion. Offline synchronization design must preserve tenant isolation, idempotency, conflict handling, and an audit trail.

## Products and inventory

`Product.stock_quantity` is the current projection and `InventoryMovement` is the append-only stock ledger. Every mutation locks the product row on PostgreSQL, validates that stock cannot become negative, updates the projection, and inserts exactly one movement in one transaction. A business-scoped `client_operation_id` makes retries safe; reuse for a different product or payload returns conflict. Opening stock creates a movement only when positive. Services have inventory tracking disabled and always hold zero stock and threshold. Tracking mode is intentionally immutable after creation so history cannot be invalidated.

Money is `NUMERIC(12,2)` and quantity is `NUMERIC(18,3)` end to end. Flutter sends decimal strings and performs no binary floating-point arithmetic. Product lookups include business scope; cross-tenant identifiers resolve as not found. OWNER and MANAGER mutate, CASHIER reads, and the commercial write guard permits ACTIVE/GRACE_PERIOD only. Deactivation preserves products and movement history.

OWNER, MANAGER, and CASHIER are persisted roles. Milestone 2 exposes OWNER creation only; role-management UI and APIs are deferred. Business deletion is not supported. Future deactivation must preserve audit and referential integrity.

## Brute-force protection

No distributed login rate limiter is claimed in Milestone 2. A process-local limiter would be inconsistent across workers and restarts. Production hardening must add rate limiting at the trusted ingress or a shared store, plus monitoring and alerting, before public launch.

## Commercial architecture

`SubscriptionPlan` is configuration data; `Subscription` is one continuing business relationship, and `SubscriptionPayment` is an immutable record of an external payment that extends that relationship. `OnboardingRecord` remains separate because onboarding is a one-time service, not recurring revenue. `AuditLog` captures financially significant administrator actions without secrets or payment credentials.

The canonical subscription evaluator derives ACTIVE, GRACE_PERIOD, EXPIRED, or CANCELLED from UTC boundaries on every relevant request, so correctness does not depend on a midnight background task. Stored status is synchronized opportunistically. `require_business_write_access` combines existing membership isolation with effective commercial state. Read access is retained after expiry; business data is never deleted for non-payment.

The existing core business-profile update remains available before first activation because it is part of onboarding setup. Once a subscription exists, that route permits ACTIVE/GRACE_PERIOD and blocks EXPIRED/CANCELLED. Future operational mutations use the stricter guard and require ACTIVE or GRACE_PERIOD.

The customer client loads commercial status after business selection. OWNER sees onboarding and plan amounts, MANAGER receives operational state without payment detail, and CASHIER receives only the minimum read-only signal where relevant. The internal Flutter Web admin view is reachable only when `/auth/me` identifies an authenticated platform administrator, while every admin API independently enforces the same server-side privilege.

Business creation, subscription activation/payment, renewal/payment, and multi-record onboarding updates use service-owned transactions. Normal application code exposes no audit-log update/delete route.

## Commercial security boundary

Business OWNER and ZedBiz platform administrator are independent privilege systems. Membership roles never grant `/admin` access. Public registration cannot assign either privilege. The first administrator is promoted from an existing user through the server CLI and the promotion is logged and audited.

ZedBiz records externally completed payments during V1. ZedBiz does not hold customer funds or collect mobile-money PINs.

## Time and money

Timestamps are stored in UTC. Zambia-facing presentation uses `Africa/Lusaka`. Monetary values use fixed-precision decimal types in Dart/Python logic and PostgreSQL `NUMERIC`, never binary floating point.

## Sales transaction boundary

The Flutter client holds an unpersisted cart and a stable operation UUID. `POST /sales` is the transaction boundary: membership/commercial checks occur first, duplicate products are aggregated, product rows are locked in UUID order, stock and activity are validated, current product values are snapshotted, line values and totals are calculated, the business receipt counter is locked, and the sale, items, stock projections, and `SALE` movements commit together. A failure rolls back the whole transaction.

Sale numbering uses a per-business `SaleCounter` row locked with `FOR UPDATE`, producing `ZB-YYYYMMDD-NNNNNN`. It never uses row counts and Flutter cannot choose a number. PostgreSQL row locks serialize competing sales for the same stock and deterministic product ordering reduces deadlock risk.

Completed sales are never destructively deleted. Corrections use audited void/reversal behavior. OWNER/MANAGER voiding locks the sale and affected product rows, appends `SALE_VOID` movements, restores stock, records actor/reason/time, and keeps the original sale and `SALE` movements. CASHIER can record and read sales but cannot void or receive cost/margin fields.

Historical sale values use immutable price and cost snapshots and must not be recalculated from current product data. Customer receipts are derived from those snapshots and intentionally omit costs and profit. A permanent receipt table is unnecessary because the source transaction is immutable.

## Customers and customer credit

`Customer` is tenant-owned contact data with an active/inactive lifecycle. The write boundary normalizes confidently identifiable Zambia numbers to E.164, preserves explicit valid international numbers, lowercases optional email, and rejects ambiguous phone input. Customer list balances are produced with grouped debt aggregates rather than per-customer queries. CASHIER may search and create customers for counter work but cannot edit/deactivate them or write/read internal notes; OWNER and MANAGER have operational customer administration.

Customer credit extends the existing sale transaction rather than creating a parallel sales path. `CUSTOMER_DEBT` requires an active same-business customer. The sale, immutable items, stock projections, `SALE` movements, and one linked `Debt` are flushed and committed by `SalesService` together. A failure at any point rolls back every record. Manual non-sale debt is deliberately excluded.

`Debt.original_amount` is the server-calculated final sale total. `amount_paid` and `outstanding_amount` are server-owned projections backed by append-only `DebtPayment` events. Customer debt balances are never updated directly by clients. Balances change only through validated sale and repayment workflows. A repayment locks the debt row with PostgreSQL `FOR UPDATE`, checks business scope/status/outstanding balance, appends the payment, derives OPEN/PARTIALLY_PAID/PAID state, and commits the event and projection together. Business-scoped operation UUIDs plus canonical SHA-256 fingerprints make network retries idempotent and reject materially different reuse.

Repayments are append-only financial events during normal operation and are never destructively deleted. Overpayment, payment against PAID/VOIDED debt, `CUSTOMER_DEBT` as a repayment method, and client-supplied balances/status are rejected. Repayment corrections and reversals require a future explicit compensating workflow.

Due dates are business-local dates. Overdue state is calculated at request time using today's `Africa/Lusaka` date and applies only to positive OPEN/PARTIALLY_PAID balances. PAID and VOIDED debts remain historical but do not contribute to outstanding or overdue aggregates.

Sale voiding locks the sale and linked debt before inventory restoration. An unpaid linked debt is changed to VOIDED with zero active outstanding balance in the same transaction as the sale void and `SALE_VOID` movements. If any repayment exists, the V1 sale void is rejected; silently erasing or reinterpreting received money would require a refund/credit-note workflow.

Debt/customer/payment/reminder reads always include business scope and remain available after subscription expiry. ACTIVE and GRACE_PERIOD permit authorized mutations; PENDING, EXPIRED, and CANCELLED are read-only. Reminder responses contain only business/customer name, current outstanding amount, optional due date, and neutral wording. ZedBiz generates reminder text but does not automatically send WhatsApp messages in V1.

## Expenses and reporting

`Expense` is an immutable tenant-owned financial event. Creation uses an exact decimal string and a business-scoped operation UUID with a canonical request fingerprint. Corrections are audited void transitions with a separate idempotent operation UUID; there is no update or delete path. OWNER/MANAGER see the business ledger and may void, while CASHIER may create without internal notes and read only their own entries.

Dashboard and report queries always begin with an explicit `business_id` predicate. Sales use immutable `Sale.total_amount` and `Sale.gross_profit` snapshots and include only COMPLETED rows whose UTC timestamp falls inside boundaries derived from `Africa/Lusaka`. Expense totals use RECORDED rows and local `expense_date`. Current outstanding and overdue debt are point-in-time metrics and are not constrained by a selected sales/expense period.

CASHIER response shaping is enforced by the API: dashboard profitability, expenses, debt, and recent-expense fields are null; sales-report gross profit is null; expense and performance reports return `403`. OWNER/MANAGER receive the complete management view. Historical reads remain available for lapsed subscriptions, while expense creation and voiding share the ACTIVE/GRACE write guard.

Debt repayments are not additional sales revenue. Revenue is recognized from the originating completed sale.

Voided sales and voided expenses do not contribute to active dashboard and report totals.

'After Expenses' is calculated as recorded gross profit minus recorded non-voided expenses. It is a simplified management metric and is not a formal accounting net-profit statement.

Top products aggregate immutable `SaleItem.quantity` and `line_subtotal` by `product_id`. The current same-business product name is displayed when available, with the stored sale-item name retained as the query fallback. Sale-level discounts are not allocated back across item lines, so top-product revenue is explicitly line-subtotal revenue before a sale-level discount.


## Milestone 8

The Flutter composition root now supplies OfflineClient to the existing repositories. Drift handles persistent cached read models, durable domain intents, and synchronization leases; PostgreSQL retains transaction authority. Optional sale-critical tokens guard stale offline prices. See [offline-sync.md](offline-sync.md) for the state machine, authentication, account/business isolation, restart recovery and platform constraints.
