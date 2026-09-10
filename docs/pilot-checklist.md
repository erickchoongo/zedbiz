# Pilot acceptance checklist

Use this for each actual deployment; do not treat automated local results as operator sign-off. See `milestone-9-report.md` for executed evidence and outstanding items.

## Infrastructure

- [ ] Real API/Web domains point to the selected host; HTTPS certificates and HTTP redirect verified.
- [ ] PostgreSQL is private, volume persistence confirmed, app role is not administrative.
- [ ] Exact migration head and API liveness/readiness verified.
- [ ] Off-host protected backup destination configured; restore drill passed.
- [ ] Disk alerts, backup-age alerts and API/readiness probes assigned to an operator.
- [ ] Log rotation and image rollback versions recorded.

## Security

- [ ] Independently generated secrets stored outside Git; no default passwords.
- [ ] Explicit CORS and trusted hosts tested from the actual Web domain.
- [ ] Forwarding trust limited to the deployed proxy; one process/replica for local limits.
- [ ] Login/account/general rate limits active; errors expose request IDs without secrets.
- [ ] Platform administrator promoted deliberately; normal OWNER cannot call admin APIs.
- [ ] Dependency findings reviewed and any release blockers resolved.

## Application

- [ ] Normal login, business creation and Founder onboarding/subscription completed.
- [ ] Products, opening stock, cash/mobile-money sale and receipt verified.
- [ ] Online credit sale, partial repayment and debt balance verified.
- [ ] Expense, dashboard and reports agree with supervised transactions.
- [ ] Offline sale/expense survive restart; repeated sync does not duplicate records.
- [ ] Price/stock/role/subscription conflicts remain reviewable.
- [ ] Account/business switching and logout protect cached records.
- [ ] PDF and text receipts exclude costs, margins, internal notes and credentials.

## Mobile

- [ ] Operator-controlled release signing configured and certificate recorded.
- [ ] APK installed on the intended phone/API level; launch/login/business selection verified.
- [ ] Offline restart and reconnect/sync verified on that phone.
- [ ] Credit/repayment online, expense, dashboard and logout/re-login verified.
- [ ] Receipt PDF and native share/export tested on the target device.

## Recovery

- [ ] Timestamped backup/hash captured and counts verified after disposable restore.
- [ ] Migration failure and application rollback procedures rehearsed/reviewed.
- [ ] Post-backup financial reconciliation procedure understood before a restore cutover.
- [ ] Pending offline clients will not be wiped during an outage.

## Explain pilot limitations to staff

ZedBiz is not formal double-entry accounting or a tax-filing package. There is no ZRA Smart Invoice, automatic mobile-money collection, refunds/credit notes, suppliers/procurement, payroll, lending, marketplace, AI or multi-branch functionality. Customer Credit, repayments, stock administration and voids require internet. Offline paid transactions remain provisional until the server accepts them. The 24-hour offline authorization window, browser/device storage limitations and price/stock conflicts must be understood. Pilot distribution must not precede the outstanding HTTPS and device/signing acceptance checks.
