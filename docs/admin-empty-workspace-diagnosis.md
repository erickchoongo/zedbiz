# Empty platform-admin workspace diagnosis

## Evidence and limits

The reported live screen contains only two filters. That does not match this checkout: the previous source already had an overview and four navigation destinations, regardless of business count. The exact live cause is NOT established without the deployed frontend bundle and an authenticated API response. Do not report zero businesses or successful authenticated parsing without that evidence.

Public probes from this workstation: backend /api/v1/health and /api/v1/health/ready returned 200; unauthenticated /api/v1/admin/businesses?page=1&page_size=100 returned 401. Cloudflare frontend, main.dart.js and bootstrap requests returned 403. A later OpenAPI request timed out. No database connection, personal-data query or promotion was performed. Hosted counts and the current account's platform-admin flag remain unverified.

The private operator helper is C:\Users\Administrator\AppData\Local\ZedBiz-Local\diagnose-admin-live.py. It prompts privately, uses the APP session-pooler account with verify-full and read-only protection, reads only six requested table counts, and uses GET requests with the existing admin session. Safe output is admin-live-diagnostic.json in the same directory. No credentials are written to that result. Never paste the token/password into chat.

## Confirmed source issues corrected

- Fixed-height search/filter controls outside the list could consume the available viewport. Overview, navigation, filters, status and results now share one CustomScrollView; there is no nested list/Expanded height allocation.
- Errors had only raw text and a toolbar refresh, with an empty-list message potentially shown concurrently. API or parsing failure now produces Unable to load admin data plus Retry, and suppresses misleading zero totals/empty results.
- Pagination accepted wrong page metadata, repeated records and changing totals. It now requires one-based page numbers, page_size=100, a stable nonnegative integer total, no duplicate IDs/oversized pages, and progress until the exact total. Invalid pagination surfaces a visible failure.
- Missing onboarding_payment_status previously defaulted to UNPAID. It is now required when parsing the backend response, so malformed data cannot look like a legitimate unpaid business.

## State behavior

Before filters: title, explicit loading/error state or overview cards, section navigation and search. After filters: payment/subscription explanation, explicit empty/no-match state or business cards. Successful zero records show zero metrics and No businesses registered yet. While loading, a progress indicator and Loading admin data appear; no false zero totals. Failure always offers Retry. Filters and records scroll together at narrow, mobile and desktop sizes.

No backend/schema/commercial-rule changes in this follow-up. CORS, trusted hosts, database URL, roles and grants remain unchanged. Offline shell is network-first, with cached fallback only on failed fetch; a cache-only root cause is not proven.

## Existing API contract

GET /api/v1/admin/businesses: page (1-based), page_size (1..100), optional search/onboarding_status/subscription_status. Response: items/page/page_size/total. Each row contains id/name/nullable owner_name/owner_email, onboarding_status, onboarding_payment_status, subscription_status and nullable paid_through.

GET /api/v1/admin/businesses/{id}/commercial: business identity, onboarding (including nullable payment method/reference/dates), nullable subscription, payments and optional additive audit_history. Existing methods remain PATCH onboarding and POST subscription/activate or subscription/renew. Server-side PlatformAdmin checks current database user on every request; ordinary membership roles never confer this access. No duplicate APIs were added.

## Changed files in this follow-up

- mobile/lib/features/admin/presentation/admin_business_list_screen.dart
- mobile/lib/features/admin/data/admin_repository.dart
- mobile/lib/features/admin/domain/admin_business.dart
- mobile/test/admin_workspace_test.dart
- mobile/test/admin_repository_test.dart
- mobile/test/commercial_flow_test.dart
- docs/admin-empty-workspace-diagnosis.md

Existing staged changes from the preceding task were preserved; this follow-up does not stage, commit, push or deploy. A fresh Cloudflare upload will be required. No new Render deployment is needed for this frontend-only follow-up if the previous admin API version is already deployed.

## Validation

Completed local validation:

- Backend full suite: 111 passed.
- Flutter full suite: 89 passed; 3 existing external integration tests skipped.
- Flutter analyze: no issues.
- Release Web build: succeeded, build/web generated in 239.8 seconds. Used the requested API_BASE_URL, APP_ENV=production and API_REQUEST_TIMEOUT_SECONDS=90, with --no-pub and --no-wasm-dry-run. The optional WebAssembly compatibility check was skipped; this is a JavaScript release artifact. A Cupertino font warning remains; Material icons were generated.
- Final artifact inspection confirms the intended hosted API URL, overview labels, visible error and explicit zero-state text are present in main.dart.js.
- git diff --check passed. Existing index contents were preserved; no staging, commit, push, hosting changes or database mutations.

The corrected local workspace and release artifact are ready for manual frontend deployment, but the exact live root cause is still unconfirmed. No private admin-live-diagnostic.json has been supplied. Hosted table counts, the specific account's current admin flag and authenticated API/Flutter parsing success must not be claimed. Run the prepared private helper locally and review its safe result to complete that portion of the diagnosis. Do not clear browser business storage to troubleshoot a stale frontend; it may contain unsynced operations.
