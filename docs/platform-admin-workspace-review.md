# Pilot platform-admin workspace audit and completion

## Findings

The existing Milestone 3 backend already provided platform-admin business search, commercial detail, onboarding updates, subscription activation and renewal. All routes enforce PlatformAdmin using the current database user; OWNER/MANAGER/CASHIER membership does not confer platform administration. Login and restored sessions fetch /auth/me. Token refresh preserves identity and the server checks the current role, including immediate revocation. A user promoted while already signed in should sign out and sign back in to refresh the UI profile.

The existing Flutter workspace was a business list and commercial detail page, not an overview dashboard. Its repository discarded pagination and displayed only the first 25 records. Its model discarded onboarding_payment_status. The business-selection entry was an icon only; the More entry appeared below the initial viewport. These explain inadequate oversight and poor discoverability in source. The authenticated hosted UI was not inspected; no claim is made that the deployed build matches this checkout. Public web-tool checks were unavailable.

## Changes

- Explicit ZedBiz Admin entry on business selection; existing More entry moved to the top for platform admins only. App routing also checks the admin flag.
- Overview cards for registered businesses, unpaid/paid/waived onboarding, and active/grace/expired subscriptions. Counts use the complete existing paginated list, not one page. They are a refreshed multi-request view, not a transactionally consistent analytics snapshot.
- Businesses, Payments and Subscriptions navigation; business/name/owner/email/ID search and existing onboarding/subscription status filters plus onboarding-payment filters.
- Payments are grouped by business. Select a business to see recorded subscription payments and onboarding payment information. No fabricated global revenue/payment totals or provider payment statuses.
- Details expose owner/contact identity, business ID, onboarding amount/status/method/reference/date, subscription start/period/grace, and payment amounts/methods/references/paid/recorded/covered-period dates.
- Existing protected commercial detail API adds latest 100 commercial audit events, restricted to action, actor ID and timestamp. No arbitrary audit metadata or new API endpoints.
- Existing confirmation, waiver, activation and renewal workflows remain unchanged. No direct Flutter database writes. K200 onboarding, K79 Founder and seven-day grace unchanged.

Payment methods ARE stored: both onboarding_records and subscription_payments have payment_method. Onboarding may have no recorded method; the UI says Not recorded. Subscription payments are recorded receipts; no invented gateway-confirmation status is shown.

## Validation

- Backend full suite: 111 passed using local disposable SQLite test fixtures, never Supabase.
- Flutter full suite: 77 passed, 3 pre-existing external integration tests skipped.
- Flutter analyze: no issues.
- Regression coverage: admin/ordinary navigation, profile state after token refresh, immediate server-side revocation/403, audit response field restrictions, full pagination/payment-state mapping, and existing commercial action paths/payloads.
- Release Web build uses API_BASE_URL=https://zedbiz-free-pilot.onrender.com, APP_ENV=production, API_REQUEST_TIMEOUT_SECONDS=90. PASS: build/web generated successfully. The optional WebAssembly compatibility dry-run was cancelled after prolonged compilation; the successful JavaScript release build used --no-wasm-dry-run with all three requested production defines. Build emitted a missing Cupertino icon-font warning; Material icons were generated successfully. No WebAssembly artifact is claimed.

## Files changed for this task

- backend/app/api/v1/routes/admin.py
- backend/app/schemas/commercial.py
- backend/tests/test_commercial.py
- mobile/lib/app/app.dart
- mobile/lib/features/admin/data/admin_repository.dart
- mobile/lib/features/admin/domain/admin_business.dart
- mobile/lib/features/admin/presentation/admin_business_list_screen.dart
- mobile/lib/features/admin/presentation/admin_commercial_detail_screen.dart
- mobile/lib/features/businesses/presentation/business_list_screen.dart
- mobile/lib/features/businesses/presentation/business_shell.dart
- mobile/test/commercial_flow_test.dart
- mobile/test/admin_repository_test.dart
- docs/platform-admin-workspace-review.md

Existing uncommitted Supabase handoff and free-pilot documentation changes predate this task and were preserved.

## Deployment handoff

A new Render deployment is required for the additive audit-history response. A new Cloudflare Pages upload of mobile/build/web is required for the dashboard/navigation changes. The frontend tolerates an older response without audit_history but will show no audit events until the backend is updated. No migrations, Supabase grants/roles/handoff, automatic deployments, commits or pushes were performed. After manual deployment, log out/in as the promoted admin and check both navigation entries and an existing business; no production commercial action was executed during testing.
