# Free pilot deployment acceptance

All boxes start unchecked. Repository preparation does not establish remote deployment success. Follow [the setup guide](free-pilot-deployment.md), record dates/commit/evidence privately, and check each item only after testing the actual provider deployment.

- [ ] GitHub repository created with intended visibility/access.
- [ ] Reviewed code pushed; deployed branch and commit recorded.
- [ ] Supabase Free dedicated project created.
- [ ] Supabase Data API disabled; ZedBiz tables not exposed through Realtime.
- [ ] Certificate downloaded; session pooler 5432 or reachable direct connection selected.
- [ ] Separate migrator and restricted runtime roles created with private strong passwords.
- [ ] DATABASE_URL configured with verified TLS and appropriate role.
- [ ] Alembic current/heads/upgrade head complete; revisions match.
- [ ] Founder Plan seeded idempotently; K79/month and K200 onboarding preserved.
- [ ] Render Free backend deployed from the reviewed commit.
- [ ] PORT-based startup, one worker, production validation and verified database SSL confirmed.
- [ ] Liveness health passes.
- [ ] Database readiness passes with restricted runtime role.
- [ ] Flutter built with the real HTTPS backend URL, 90-second request timeout and no secrets.
- [ ] Cloudflare Pages Web deployed with index/assets at upload root.
- [ ] Backend URL configured correctly; no localhost/template endpoint in hosted build.
- [ ] Exact Pages CORS origin configured; browser preflight passes.
- [ ] Exact Render trusted hostname configured; no wildcard.
- [ ] Frontend loads and refreshing does not return an avoidable 404.
- [ ] COOP/COEP headers, Web SQLite storage and cached shell work on actual Pages origin.
- [ ] Register/login works, including a cold first request.
- [ ] Existing registered platform admin promoted through audited CLI; ordinary owner stays nonadmin.
- [ ] Business onboarding enforces payment gating.
- [ ] Business activation uses legitimate admin workflow without duplicate business/subscription.
- [ ] Activated OWNER reaches dashboard with Home, Sales, Products and More tabs.
- [ ] Product creation and inventory adjustment work.
- [ ] New sale and sales history work.
- [ ] Customer credit and repayments work online.
- [ ] Expense entry works.
- [ ] Reports reconcile with test transactions.
- [ ] Offline queue, reconnect replay, idempotency and Sync Status work.
- [ ] Receipt PDF opens/downloads.
- [ ] Temporary backend/database unavailability produces recoverable UI state.
- [ ] Manual pg_dump stored privately outside Git; catalogue and checksum verified.
- [ ] Disposable local restore drill completed; revision/counts and financial totals checked.
- [ ] Protected off-laptop backup copy made and location recorded.
- [ ] Free-tier constraints, account recovery and operator responsibilities accepted for this internal pilot.

Dedicated Business Settings, Subscription and account-detail screens were not added by this infrastructure task. Verify only existing destinations and report missing feature work separately; do not interpret this checklist as a new milestone.
