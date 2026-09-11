# ZedBiz

ZedBiz is a mobile-first business management platform for Zambian SMEs. Milestones 1–8 provide the Flutter Android/Web client, secure identity and tenancy, commercial onboarding/subscriptions, products and inventory, atomic sales/receipts, customers, customer credit, repayment tracking, immutable expenses, dashboards, business reports, offline paid-sale/expense synchronization, and device-generated receipt PDFs.

## Repository

```text
mobile/                 Flutter application
backend/app/            FastAPI application and infrastructure
backend/migrations/     Alembic migration history
backend/tests/          Backend tests
docs/                   Architecture, database, API, and product notes
docker-compose.yml      Local PostgreSQL and API services
```

## Prerequisites

- Flutter stable with Android SDK/tooling (and Chrome for Web)
- Python 3.12 and [uv](https://docs.astral.sh/uv/)
- Docker Desktop with Docker Compose
- Git and PowerShell 7 or Windows PowerShell

## Environment setup

From the repository root:

```powershell
Copy-Item .env.example .env
```

Replace every `replace-...` value in `.env`. Generate a local JWT secret, for example:

```powershell
$bytes = New-Object byte[] 48
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$rng.Dispose()
[Convert]::ToBase64String($bytes)
```

Ensure `DATABASE_URL` uses the same database, username, and password as the three `POSTGRES_*` values. `.env` is ignored by Git.

## Start services

Start PostgreSQL only:

```powershell
docker compose up -d db
docker compose ps
```

Install the backend and apply migrations:

```powershell
Set-Location backend
uv sync --frozen
uv run alembic upgrade head
```

Start FastAPI locally:

```powershell
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Alternatively, start PostgreSQL and the containerized API from the repository root:

```powershell
docker compose up -d db
docker compose run --rm api alembic upgrade head
docker compose up --build
```

## Run Flutter

The Android emulator default is `http://10.0.2.2:8000`, while Web defaults to `http://localhost:8000`.

```powershell
Set-Location mobile
flutter pub get
flutter run
```

For a physical device, replace the address with the development machine's LAN IP and ensure firewall/network access is intentionally allowed:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
```

For Web:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Production builds must pass an HTTPS API URL.

The app flow is splash/session restoration, login or registration, business selection, then Home, Sales, Products, and More. Customers and Customer Credit are available from More. ACTIVE/GRACE businesses can record sales, customer credit, and repayments; OWNER/MANAGER can void unpaid credit sales while CASHIER cannot void sales. Expired/cancelled businesses retain historical sale, receipt, customer, debt, repayment, and reminder access. Android tokens are stored through platform secure storage rather than SharedPreferences.

Sales are composed locally as a cart and submitted once as an atomic transaction. The server supplies prices, costs, totals, receipt numbers, and stock results. ZedBiz records the payment method used for a sale but does not process or hold the customer's payment funds.

## Milestone 6 customer credit

Customers use a non-destructive active/inactive lifecycle. Zambia national phone numbers such as `0971234567`, `260971234567`, and `+260971234567` normalize to E.164 (`+260971234567`); explicit valid international `+`/`00` numbers are preserved, and ambiguous input is rejected rather than guessed. Email is optional and normalized to lowercase.

Selecting **Customer Credit** during a sale requires an active customer and creates the immutable sale, stock movements, and linked debt in one transaction. Optional due dates are Zambia-local calendar dates; an unpaid balance is overdue only when its due date is earlier than today's `Africa/Lusaka` date. Manual non-sale debts are not supported.

Customer debt balances are never updated directly by clients. Balances change only through validated sale and repayment workflows. Repayments are exact, partial or full, idempotent, append-only financial events during normal operation and are never destructively deleted. Overpayments are rejected. An unpaid credit sale can be voided with its debt and stock restoration atomically; a credit sale with any repayment cannot use the simple V1 void flow and requires a future refund/credit-note design.

ZedBiz generates reminder text but does not automatically send WhatsApp messages in V1. The Flutter client lets the user copy/share the neutral, customer-safe text; no WhatsApp credentials or automatic delivery are involved.

## Tests and checks

```powershell
Set-Location backend
uv run pytest

Set-Location ..\mobile
flutter analyze
flutter test
```

## Restricted or unreliable networks

Both dependency lockfiles are committed. Keep them unchanged and use frozen resolution for reproducible installs:

```powershell
Set-Location backend
uv sync --frozen
```

If `uv` reports `UnknownIssuer` on a Windows-managed or corporate network, use the Windows certificate store:

```powershell
uv --system-certs sync --frozen
```

When the required artifacts are already cached, installs can run without network access:

```powershell
uv sync --frozen --offline
Set-Location ..\mobile
flutter pub get --offline
```

Docker still needs the PostgreSQL, Python, and uv images to have been pulled at least once. Do not disable TLS verification to work around certificate errors.

## Development URLs

- API: `http://localhost:8000`
- Liveness: `http://localhost:8000/api/v1/health`
- Readiness: `http://localhost:8000/api/v1/health/ready`
- OpenAPI UI (non-production): `http://localhost:8000/docs`
- PostgreSQL: `localhost:5432` (loopback only)

## Milestone 2 API

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/me`
- `POST /api/v1/businesses`
- `GET /api/v1/businesses`
- `GET /api/v1/businesses/{business_id}`
- `PATCH /api/v1/businesses/{business_id}`

Registration cannot assign platform-admin state or business roles. Business creation atomically makes the authenticated user OWNER. Protected business routes always verify the active database membership; knowing a UUID is never authorization.

## Security notes

Never commit `.env`, credentials, tokens, database dumps, or production URLs containing credentials. Passwords use Argon2 and raw refresh tokens are never stored server-side. Access tokens are short-lived; refresh tokens rotate and are revocable. Production startup rejects weak/placeholder JWT secrets, missing trusted CORS origins, wildcard CORS, and local/default database settings. Rotate secrets per environment. Compose binds development ports to loopback; review ingress, TLS termination, CORS, database networking, secret storage, logging, backups, and container image scanning before deployment. Local Android HTTP is enabled only in debug builds; use HTTPS in production.

Milestone 2 does not claim distributed brute-force protection. Add shared ingress/application rate limiting and authentication monitoring before public production launch.

**Security invariant: A user must never gain access to another business's data solely by obtaining or guessing its UUID.**

## Milestone 3 commercial foundation

Milestone 3 adds the database-configured `FOUNDER` plan at ZMW 79.00 per calendar month, a centrally defined ZMW 200.00 onboarding fee, manual external-payment records, seven-day subscription grace, read-only enforcement, append-only audit events, and a protected Flutter Web admin workspace. ZedBiz records externally completed payments during V1. ZedBiz does not hold customer funds or collect mobile-money PINs.

New businesses atomically receive an OWNER membership and an unpaid/not-started onboarding record. Platform administrators confirm or waive onboarding, complete setup, activate Founder access with a payment reference, and record renewals. Early renewal extends the existing paid-through boundary; expired renewal starts at the external payment timestamp. Monthly periods use calendar arithmetic rather than 30-day approximations.

Commercial endpoints:

- `GET /api/v1/businesses/{business_id}/commercial-status`
- `GET /api/v1/admin/businesses`
- `GET /api/v1/admin/businesses/{business_id}/commercial`
- `PATCH /api/v1/admin/businesses/{business_id}/onboarding`
- `POST /api/v1/admin/businesses/{business_id}/subscription/activate`
- `POST /api/v1/admin/businesses/{business_id}/subscription/renew`

From `backend/`, seed the Founder plan idempotently and promote an existing registered user with server-side confirmation:

```powershell
uv run python -m app.cli seed-founder-plan
uv run python -m app.cli promote-admin --email operator@example.com
```

Use `--yes` only in a controlled non-interactive deployment. There is no public admin-creation endpoint and no default admin password.

Money is `Decimal`/PostgreSQL `NUMERIC(12,2)` in the backend, serialized as two-decimal strings, and parsed into integer minor units in Flutter. Customer-facing Zambia dates are rendered in UTC+02:00 (`Africa/Lusaka`). Payment destination details are not embedded in source code.

## Milestone 7 expenses, dashboard, and reports

ACTIVE and GRACE_PERIOD businesses can record expenses. OWNER and MANAGER can see all expense records and void an incorrect entry with a reason; CASHIER can record an expense without private notes and can view only expenses they recorded. No expense update/delete route exists. EXPIRED and CANCELLED businesses retain read-only expense, dashboard, and report access.

The Home screen provides Today, Week, and Month dashboard views. The report hub provides sales, expense, performance, customer-credit, and inventory views. OWNER and MANAGER receive profit, expense, debt, and After Expenses figures. CASHIER receives operational sales count/value, inventory warnings, and recent sales without profitability, expense totals, debt totals, or recent expenses.

Debt repayments are not additional sales revenue. Revenue is recognized from the originating completed sale.

Voided sales and voided expenses do not contribute to active dashboard and report totals.

'After Expenses' is calculated as recorded gross profit minus recorded non-voided expenses. It is a simplified management metric and is not a formal accounting net-profit statement.

`STOCK_PURCHASE` is only an expense category in this milestone. Recording it does not change inventory; stock received must be entered separately through the existing inventory workflow.


## Milestone 8

Milestone 8 adds persistent Drift/SQLite caching, durable paid-sale/expense capture, foreground sync with explicit conflict review, and local receipt PDF sharing/export. PostgreSQL remains authoritative. See [offline synchronization](docs/offline-sync.md) for the scope, policies and verification commands. Customer Credit, repayments, stock administration and voids remain online-only.

See the [Milestone 8 report](docs/milestone-8-report.md) for the change inventory, executed checks, platform limitations and exact local PowerShell commands.

## Milestone 9

Milestone 9 adds controlled-pilot deployment and security hardening, PostgreSQL backup/restore procedures, production configuration checks, and offline/concurrency stress verification. See the [Milestone 9 report](docs/milestone-9-report.md) for results and remaining deployment requirements. Start with the [deployment guide](docs/deployment.md), [disaster recovery guide](docs/disaster-recovery.md), [operations runbook](docs/operations-runbook.md) and [pilot checklist](docs/pilot-checklist.md). No Milestone 10 features are included.

## Pilot Milestone 1

Pilot preparation adds release diagnostics under More, daily backup/monitoring tooling and a one-business rehearsal. See the [Pilot 1 execution guide](docs/pilot-1-operations.md), [issue register](docs/pilot-issues.md) and [Pilot 1 report](docs/pilot-milestone-1-report.md). Public deployment and physical Android acceptance require the operator's hosting, signing and device inputs; local rehearsal results do not establish those outcomes.
