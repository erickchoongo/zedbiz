# API

The HTTP API is rooted at `/api/v1`. JSON is the default representation. Protected endpoints require `Authorization: Bearer <access-token>`.

## Health

### `GET /api/v1/health`

Process liveness check. It does not touch the database.

```json
{"status": "ok"}
```

### `GET /api/v1/health/ready`

Dependency readiness check. It executes a lightweight PostgreSQL query. It returns `200` with `{"status":"ok"}` when reachable, or `503` with a generic error when unavailable. The response deliberately omits connection details.

Interactive OpenAPI documentation is available at `/docs` outside production. Production disables it by default.

## Authentication

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/auth/register` | Register a user and issue an access/refresh pair |
| `POST` | `/api/v1/auth/login` | Authenticate a normalized email and password |
| `POST` | `/api/v1/auth/refresh` | Validate and rotate a refresh session |
| `POST` | `/api/v1/auth/logout` | Revoke the presented refresh session |
| `GET` | `/api/v1/auth/me` | Return the authenticated safe user profile |

Registration accepts `full_name`, `email`, and `password`. Privileged/admin and business-role fields are forbidden. Login failures use a generic message. Responses never contain password hashes or refresh-session hashes.

Access and refresh JWTs contain `sub`, `type`, `iat`, and `exp`; refresh JWTs also contain `jti`. Token types cannot be substituted. Every protected request reloads the active user from the database. Refresh additionally validates the hashed token against an unexpired, unrevoked server-side session and active user.

## Businesses

| Method | Path | Authorization |
|---|---|---|
| `POST` | `/api/v1/businesses` | Authenticated user; creator becomes OWNER |
| `GET` | `/api/v1/businesses` | Active memberships only |
| `GET` | `/api/v1/businesses/{business_id}` | Active membership in that business |
| `PATCH` | `/api/v1/businesses/{business_id}` | Active OWNER; setup allowed before first activation, but EXPIRED/CANCELLED subscriptions are read-only |

Cross-tenant and inactive-membership reads return `404`; known memberships with insufficient roles receive `403` for OWNER-only operations. Business creation does not accept an owner ID, role, currency, or timezone from the client.

**Security invariant: A user must never gain access to another business's data solely by obtaining or guessing its UUID.**

## Customer commercial status

| Method | Path | Authorization |
|---|---|---|
| `GET` | `/api/v1/businesses/{business_id}/commercial-status` | Active member of the requested business |

The response contains safe plan/state/date/write-access information. OWNER receives onboarding fee/payment state and plan price. Non-owner roles receive reduced commercial detail. Internal onboarding notes and other businesses are never returned. Monetary values are JSON strings such as `"79.00"`.

## Platform administration

Every `/api/v1/admin` route requires an active authenticated user whose database record has `is_platform_admin=true`. Business ownership is not sufficient.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/admin/businesses` | Paginated business/commercial list with search and status filters |
| `GET` | `/api/v1/admin/businesses/{business_id}/commercial` | Onboarding, subscription, and payment history detail |
| `PATCH` | `/api/v1/admin/businesses/{business_id}/onboarding` | Validate and record onboarding payment/state changes |
| `POST` | `/api/v1/admin/businesses/{business_id}/subscription/activate` | Atomically activate Founder and record its external payment |
| `POST` | `/api/v1/admin/businesses/{business_id}/subscription/renew` | Atomically extend the period and record its external payment |

Activation requires completed onboarding, an active seeded Founder plan, payment method, and unique external reference. Complimentary access is not silently supported. Invalid state transitions return `409`; malformed requests return `422`; duplicate payment references return `409`; non-admin access returns `403`.

Effective state is ACTIVE before `current_period_end`, GRACE_PERIOD from the exact period-end boundary through the inclusive grace boundary, and EXPIRED after grace. CANCELLED takes precedence when cancellation data exists. Early renewal begins at the existing paid-through boundary; expired renewal begins at the payment timestamp.

ZedBiz records externally completed payments during V1. ZedBiz does not hold customer funds or collect mobile-money PINs.
# Products and inventory (Milestone 4)

- `POST/GET /api/v1/businesses/{business_id}/products`
- `GET/PATCH /api/v1/businesses/{business_id}/products/{product_id}`
- `POST .../{product_id}/deactivate|reactivate`
- `POST .../{product_id}/stock/add|adjust|damaged|lost`
- `GET .../{product_id}/inventory-movements`
- `GET /api/v1/businesses/{business_id}/inventory/low-stock|summary`

Lists support `page`, `page_size`, `search`, lifecycle, tracking, and low-stock filters. Money and quantity values are JSON strings. Stock writes require a UUID `client_operation_id`; retry the same payload with the same ID, but generate a new ID for a new user intent. Reductions and adjustments require a reason. Expected access failures are 402 (commercial state), 403 (role), 404 (tenant-safe absence), and 409 (domain/idempotency conflict).

## Sales and receipts (Milestone 5)

- `POST /api/v1/businesses/{business_id}/sales` completes one atomic sale.
- `GET /api/v1/businesses/{business_id}/sales` provides paginated search, payment/status/date/seller filters.
- `GET /api/v1/businesses/{business_id}/sales/{sale_id}` returns role-shaped detail.
- `GET /api/v1/businesses/{business_id}/sales/{sale_id}/receipt` returns customer-safe receipt data.
- `POST /api/v1/businesses/{business_id}/sales/{sale_id}/void` performs an OWNER/MANAGER reversal.

Sale creation accepts only product IDs, exact quantities, a fixed discount, payment method/reference, notes, and a required operation UUID. Unit prices, costs, totals, profit, sale number, and stock values are server-derived. Duplicate product lines are aggregated. Repeating an identical operation returns the existing sale; materially different reuse returns `409`.

Supported payment methods are CASH, MTN_MONEY, AIRTEL_MONEY, ZAMTEL_MONEY, BANK_TRANSFER, and OTHER. There is one payment method per sale. ZedBiz records the payment method used for a sale but does not process or hold the customer's payment funds. PINs, OTPs, passwords, card numbers, and provider secrets are never accepted.

CASHIER detail responses set cost and profit fields to null. Receipt responses never expose them. ACTIVE/GRACE may mutate; expired/cancelled businesses can still list sales, read detail, and obtain receipts.

## Customers and customer credit (Milestone 6)

Customer endpoints:

- `POST /api/v1/businesses/{business_id}/customers`
- `GET /api/v1/businesses/{business_id}/customers`
- `GET /api/v1/businesses/{business_id}/customers/{customer_id}`
- `PATCH /api/v1/businesses/{business_id}/customers/{customer_id}`
- `POST /api/v1/businesses/{business_id}/customers/{customer_id}/deactivate`
- `POST /api/v1/businesses/{business_id}/customers/{customer_id}/reactivate`

Lists accept `page`, `page_size`, `search`, `is_active`, and `outstanding_only`; each row contains grouped outstanding/overdue/open-debt totals. Customer detail embeds only a small recent-debt sample, with full history available through the paginated debt endpoint. OWNER/MANAGER create, edit and change lifecycle state. CASHIER may list/view and create a basic customer during a sale, but cannot set/read internal notes or edit/deactivate/reactivate.

Debt endpoints:

- `GET /api/v1/businesses/{business_id}/debts`
- `GET /api/v1/businesses/{business_id}/debts/summary`
- `GET /api/v1/businesses/{business_id}/debts/{debt_id}`
- `GET /api/v1/businesses/{business_id}/debts/{debt_id}/payments`
- `POST /api/v1/businesses/{business_id}/debts/{debt_id}/payments`
- `GET /api/v1/businesses/{business_id}/debts/{debt_id}/reminder`

Debt lists accept status, overdue-only, customer, due-date range, customer-name/phone search, and database pagination. The debt summary is limited to total outstanding, total overdue, customers owing, and open-debt count. Default ordering places overdue debt first, then other open debt, paid debt, and voided debt, with due/creation dates providing stable ordering.

`POST /sales` additionally accepts `CUSTOMER_DEBT`, `customer_id`, and optional `due_date`. Customer fields are rejected for non-credit payment methods; credit requires an active same-business customer and a positive final total. The server creates the sale and linked OPEN debt atomically. The receipt identifies Customer Credit and may include customer/due-date data, but never internal debt notes, cost, or margin.

Repayment creation accepts a required operation UUID, positive exact amount, CASH/MTN_MONEY/AIRTEL_MONEY/ZAMTEL_MONEY/BANK_TRANSFER/OTHER, optional reference, and optional management note. `CUSTOMER_DEBT`, overpayment, and payment against PAID/VOIDED debt are rejected. An identical retry returns the existing event and current debt; materially different operation reuse returns `409`. Responses contain the appended payment plus the server-updated debt.

ACTIVE/GRACE_PERIOD allows role-authorized customer, credit-sale, and repayment writes. PENDING/EXPIRED/CANCELLED denies writes with `402`, while customer/debt/payment/reminder and linked-sale history remains readable. Every lookup includes business scope and foreign identifiers use safe `404` behavior.

Reminder output contains a neutral message using business/customer name, current outstanding balance, and optional due date. ZedBiz generates reminder text but does not automatically send WhatsApp messages in V1. It accepts no WhatsApp credentials and performs no automatic message delivery.

## Expenses, dashboard, and reports (Milestone 7)

Expense endpoints:

- `POST /api/v1/businesses/{business_id}/expenses`
- `GET /api/v1/businesses/{business_id}/expenses`
- `GET /api/v1/businesses/{business_id}/expenses/{expense_id}`
- `POST /api/v1/businesses/{business_id}/expenses/{expense_id}/void`

Creation accepts a required operation UUID, category, nonblank description, positive two-decimal amount string, payment method/reference, local expense date, and optional notes. `CUSTOMER_DEBT`, floats, client-supplied status, and unknown fields are rejected. Identical create/void retries are idempotent; materially different operation reuse returns `409`. Lists support database pagination plus search, category, payment method, status, local date range, and recorder filters. CASHIER lists/details are restricted to self-recorded expenses.

Dashboard and report endpoints:

- `GET /api/v1/businesses/{business_id}/dashboard`
- `GET /api/v1/businesses/{business_id}/reports/sales`
- `GET /api/v1/businesses/{business_id}/reports/expenses`
- `GET /api/v1/businesses/{business_id}/reports/performance`

Each accepts `range=today|yesterday|week|month`, defaulting to today, or a complete inclusive `date_from`/`date_to` custom range. Local day boundaries use `Africa/Lusaka` and sales timestamps are compared as an inclusive UTC start/exclusive UTC end. Expense dates use the inclusive local date range. The sales report includes totals, average, payment breakdown, daily totals, and top products. The expense report includes totals and category/payment/day breakdowns plus largest expenses. Performance includes gross sales, snapshot gross profit, non-voided recorded expenses, After Expenses, and gross margin.

The dashboard names the simple result `net_operating_result` and the point-in-time receivable fields `outstanding_customer_debt` and `overdue_customer_debt`. The sales report uses `average_sale_value`; the performance report uses `expenses`, `net_operating_result`, and `gross_margin_percentage`. All money and percentage values are serialized as exact two-decimal strings.

CASHIER can read the operational dashboard and sales report, but profit and owner-only fields are null. Expense and performance reports require OWNER/MANAGER. Dashboard/report reads remain available after subscription expiry; expense writes require ACTIVE/GRACE_PERIOD.

Debt repayments are not additional sales revenue. Revenue is recognized from the originating completed sale.

Voided sales and voided expenses do not contribute to active dashboard and report totals.

'After Expenses' is calculated as recorded gross profit minus recorded non-voided expenses. It is a simplified management metric and is not a formal accounting net-profit statement.

`STOCK_PURCHASE` classifies spending only; it never mutates product stock. Top-product revenue sums immutable sale-item line subtotals and therefore does not allocate sale-level discounts. Products aggregate by `product_id`, display the current same-business name when available, and retain the sale-item snapshot as a safe fallback.


## Milestone 8

Product responses now include sale_version. Sale items may include this optional token; stale price/activity/tracking state returns 409 under existing row locks. Missing tokens retain legacy online fingerprint behavior. Sale/expense responses and sale history expose client_operation_id for reconciliation. POST /api/v1/businesses/{business_id}/sales/reconcile and /expenses/reconcile are read-only recovery endpoints: submit the original create payload; identical accepted operations return 200, absent operations 404, differing fingerprints 409. Membership and expense read restrictions apply; current subscription write access is not required. Canonical creation endpoints and server timestamps are unchanged. See [offline-sync.md](offline-sync.md).
