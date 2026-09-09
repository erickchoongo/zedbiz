# ZedBiz Product Requirements

ZedBiz is a mobile-first small-business management platform initially for SMEs in Zambia. Milestone 2 implements identity, authentication, business creation/selection, roles, and multi-tenant isolation. It does not implement operational or financial modules.

## Implemented foundation

- email/password registration and login;
- secure mobile token persistence;
- rotating, revocable refresh sessions;
- current-user session restoration and logout;
- business creation with automatic OWNER membership;
- active-membership business listing and selection;
- OWNER-only business updates;
- server-side cross-tenant authorization.

## V1 direction

ZedBiz V1 will eventually provide:

- business onboarding;
- paid subscriptions;
- products;
- inventory;
- sales;
- expenses;
- customers;
- customer debt;
- debt repayments;
- dashboards;
- reports;
- receipts;
- offline-first synchronization.

These capabilities are roadmap scope, not implemented by this milestone.

Subscriptions, onboarding payments, products, inventory, sales, expenses, customers, debts, reports, receipts, offline synchronization, AI, marketplace, Smart Invoice, mobile-money APIs, lending, payroll, and procurement remain outside Milestone 2.

## Out of scope for V1

- marketplace;
- lending;
- payroll;
- AI assistant;
- delivery;
- ZRA Smart Invoice integration;
- direct mobile-money wallet/payment processing;
- advanced procurement.

## Milestone 3 delivered scope

The revenue foundation introduces the Founder plan at ZMW 79.00 per calendar month, a distinct ZMW 200.00 onboarding service, manual external-payment confirmation by platform administrators, seven-day grace, and historical/read-only availability after expiry. Prices are database/configuration values rather than duplicated route or widget literals.

The customer journey now distinguishes unpaid onboarding, setup in progress, pending subscription, active Founder access, grace, and expired read-only access. OWNER receives commercial management visibility; MANAGER and CASHIER visibility is deliberately reduced. A minimal protected Flutter Web interface supports admin business search, onboarding confirmation/waiver/progress/completion, Founder activation, renewal, and payment-history review with confirmation prompts.

ZedBiz records externally completed payments during V1. ZedBiz does not hold customer funds or collect mobile-money PINs. Direct payment-provider APIs, wallets, PIN collection, products, inventory, sales, expenses, customers, debts, receipts, reports, offline sync, AI, Smart Invoice, lending, payroll, procurement, and multi-branch management remain out of scope.
# Milestone 4 — Products and inventory

Delivered scope includes products and services, exact pricing, fractional stock, opening stock, add/adjust/damaged/lost operations, low-stock alerts, history, search, pagination, tenant/role/commercial enforcement, and inactive-product preservation. Zero threshold means a tracked product is low only when stock reaches zero. Inactive products are excluded from alerts. Sales, purchases, suppliers, valuation, barcode scanning, bulk import, and offline queuing are explicitly deferred.

## Milestone 5 — Sales and receipts

Delivered scope includes local cart composition, product/service search, fractional quantities, exact previews, one payment method, fixed discount, atomic completion, immutable item snapshots, stock deduction, paginated history, role-sensitive detail, customer-safe receipts, shareable receipt text, and audited OWNER/MANAGER voids with stock restoration.

Completed sales are never destructively deleted. Corrections use audited void/reversal behavior. Historical sale values use immutable price and cost snapshots and must not be recalculated from current product data.

Customer accounts, debt/credit sales, split payments, returns/exchanges, direct payment APIs, ZRA Smart Invoice, expenses, suppliers, procurement, formal accounting reports, offline synchronization, and analytics are outside Milestone 5.

## Milestone 6 — Customers and customer credit

Delivered scope includes tenant-scoped customer records, Zambia-aware phone normalization, active/inactive lifecycle management, aggregated customer balances, credit-sale creation, linked immutable sale/debt history, optional local due dates, overdue calculation, exact partial/full repayments, repayment history, debt summaries, conservative credit-sale void handling, and neutral WhatsApp-ready reminder text.

Customer debt balances are never updated directly by clients. Balances change only through validated sale and repayment workflows. Repayments are append-only financial events during normal operation and are never destructively deleted. Settled and voided debts remain visible historically.

OWNER and MANAGER administer customer lifecycle and may perform normal credit operations. CASHIER may find/create customers, record customer-credit sales, and receive repayments as counter operations, but cannot manage lifecycle/internal notes, see sale margin, or perform administrative debt reversals. ACTIVE and GRACE_PERIOD permit these writes; lapsed businesses retain read-only financial history.

ZedBiz generates reminder text but does not automatically send WhatsApp messages in V1. Messages contain no internal notes, costs, margins, threats, late fees, or credentials.

Manual non-sale debt, overpayment/customer wallets, interest, late fees, repayment correction/reversal, returns, exchanges, split payments, automatic WhatsApp/SMS delivery, direct payment-provider APIs, expenses, suppliers, purchases, procurement, formal accounting reports, offline synchronization, analytics, Smart Invoice, lending, payroll, delivery, marketplace, AI, and multi-branch management remain outside Milestone 6.

## Milestone 7 — Expenses, dashboard, and business reports

Delivered scope includes an immutable expense ledger, supported cost categories and non-credit payment methods, search/filter/pagination, business-scoped idempotent creation, audited voiding, Zambia-local expense dates, Today/Yesterday/Week/Month/custom report periods, dashboard metrics, sales and expense breakdowns, top products, performance reporting, and Flutter dashboard/expense/report flows.

OWNER and MANAGER can read the full expense ledger and profitability reports and may void expenses. CASHIER can record ordinary expenses without internal notes and can read only their own expense entries; the CASHIER dashboard/report shape omits gross profit, expense totals, After Expenses, debt totals, and recent expenses. ACTIVE/GRACE_PERIOD permits authorized expense writes. Lapsed subscriptions preserve historical expense and report reads.

Debt repayments are not additional sales revenue. Revenue is recognized from the originating completed sale.

Voided sales and voided expenses do not contribute to active dashboard and report totals.

'After Expenses' is calculated as recorded gross profit minus recorded non-voided expenses. It is a simplified management metric and is not a formal accounting net-profit statement.

`STOCK_PURCHASE` is a spending classification only. Recording one does not receive inventory automatically; the existing stock-add workflow remains a separate explicit action.

Milestone 7 does not add double-entry accounting, tax filing, cash/bank reconciliation, budgets, recurring expenses, attachment storage, suppliers, purchase orders, payroll, refunds/credit notes, multi-branch consolidation, offline synchronization, or charting/BI infrastructure.


## Milestone 8

Delivered Milestone 8 scope is persistent cached business reads, queued ordinary paid sales and expenses, safe retries, explicit pending/conflict review, account/business isolation, and local PDF receipts with sharing/export. Offline capture uses a configurable 24-hour verified membership/commercial window. No credit, repayment, void, stock administration, generic conflict merging or Milestone 9 feature is added. See [offline-sync.md](offline-sync.md) for the full operation matrix and limitations.
