# StoreFlow Security Audit Report
**Audit date:** 2026-11-25  
**Repository:** songpon3327ppumusic-ops/Pos (main)  
**Supabase project:** StoreFlow / `tjunaxajcxwxirneopar`  
**Region:** ap-southeast-1  
**Database:** PostgreSQL 17.12  
**Application:** Next.js static export on GitHub Pages + Supabase Data API / Storage / Edge Functions

## 1. Executive summary

A configuration and code security review found several material weaknesses. The highest-risk finding was that `anon` and `authenticated` had table-level `TRUNCATE`, `REFERENCES`, and `TRIGGER` privileges across many public tables. PostgreSQL RLS does not protect `TRUNCATE`; this could have enabled destructive operations outside row-level policies.

The current grants were revoked and verified. Additional hardening was applied to payment-file access, privileged RPC authorization, Stripe Checkout concurrency and webhook replay handling, Edge Function membership checks, and GitHub Actions deployment permissions.

**This is not a certification or a full penetration test.** It is a point-in-time review of the connected GitHub repository, live Supabase database metadata, security advisors, SQL function definitions, Storage policies, and deployed Edge Function source. No destructive exploit tests were run against production data.

## 2. Findings and remediation

### F-01 — Excessive table privileges bypassing RLS
**Severity: Critical — Remediated**

**Evidence**
- `anon` and `authenticated` had `TRUNCATE`, `REFERENCES`, and `TRIGGER` grants on many public tables.
- Examples included `sales`, `customers`, `products`, `employees`, `organization_members`, `payroll_items`, `business_documents`, `audit_logs`, `organization_hardware_settings`, and document tables.
- `anon` also had broad direct grants on several settings and document tables.

**Impact**
- `TRUNCATE` is not filtered by RLS and can remove rows across tenants.
- Table-level `REFERENCES` and `TRIGGER` are unnecessary for normal browser clients and enlarge the attack surface.

**Fix applied**
- Revoked all direct table privileges from `anon` in the public schema.
- Restored only `SELECT` on `public.subscription_plans`, which is intentionally public.
- Revoked `TRUNCATE`, `REFERENCES`, `TRIGGER`, and unnecessary PostgreSQL 17 `MAINTAIN` privileges from `PUBLIC`, `anon`, and `authenticated` on all existing public tables.
- Revoked anonymous sequence access.
- Added default-privilege revocations for objects created by role `postgres`.

**Verification**
- Zero remaining `TRUNCATE`, `REFERENCES`, `TRIGGER`, or `MAINTAIN` grants for `anon` / `authenticated` in public.
- `anon` has only `SELECT` on `subscription_plans`.
- No public security-definer function is executable by `anon`.

### F-02 — Payment slips were readable/uploadable by every active store member
**Severity: High — Remediated**

**Evidence**
- The former Storage read policy allowed any active member of a store to read all objects in `store-payment-assets`, including customer transfer slips.
- The former slip-upload policy allowed any active member to upload a file against any sale ID in the same organization.

**Impact**
- Employees without cashier or finance duties could access sensitive customer payment evidence or upload misleading proof files.

**Fix applied**
- Split QR and slip read policies.
- QR files are readable by active owner/admin/manager/cashier roles.
- Slips are readable by active owner/admin/manager/cashier/accountant roles.
- Slip uploads are restricted to active owner/admin/manager/cashier roles and must reference a sale in the same organization.
- QR uploads/deletes remain owner-only.
- Payment bucket remains private with a 5 MB image limit and PNG/JPEG/WEBP MIME allowlist.

### F-03 — Privileged RPCs did not consistently enforce module permissions
**Severity: High — Remediated for four sensitive RPCs**

**Evidence**
- The checkout, payment-confirmation, customer-credit-settlement, and stock-adjustment functions checked membership and role, but did not also enforce the store's module permission matrix.

**Fix applied**
- `create_pos_sale_with_payment` now requires `orders:create`.
- `confirm_pos_payment` now requires `orders:create` (cashiers are intentionally permitted to complete a POS transaction).
- `record_customer_credit_payment` now requires `orders:create`.
- `adjust_stock` now requires `inventory:update`.

Other reviewed security-definer RPCs were checked for their own authorization model, including owner approval, employee-account linking, payroll, document creation, goods receipt, invite-code access, employee self-service payslips, and shift attendance.

### F-04 — Duplicate or stale Stripe Checkout sessions could cause double charges
**Severity: High — Remediated in application logic**

**Evidence**
- The former POS Edge Function created a new Stripe Checkout Session for every retry.
- The webhook updated a sale based on sale ID and status, without verifying that the event belonged to the currently active Checkout Session.

**Impact**
- Multiple valid Checkout Sessions could exist for one sale. A stale session could be paid after a newer session had been created, creating a risk of a second customer charge that the POS would not reconcile correctly.

**Fix applied**
- Added `stripe_checkout_session_id`, `payment_attempt`, and `payment_attempt_started_at` to `sales`.
- Added `claim_storeflow_pos_stripe_checkout`, a service-role-only RPC that atomically claims a payment attempt, verifies active store membership and Stripe readiness, and prevents concurrent claims.
- Stripe Checkout now reuses an existing open session, rejects completed sessions pending webhook confirmation, and uses a per-attempt Stripe idempotency key.
- Webhook processing now checks that the event's Checkout Session ID matches the sale's current session ID.
- Stale/expired events cannot mark a newer attempt failed or paid.
- Webhook signature verification, timestamp tolerance, and test/live-mode checks remain enabled.

### F-05 — Billing Edge Functions did not check membership status consistently
**Severity: Medium — Remediated**

- `storeflow-create-checkout` and `storeflow-billing-portal` previously checked `is_active` and role but did not require `membership_status='active'`.
- Both functions now require an active membership status as well as an allowed owner/admin role.

### F-06 — Payment and credit data visibility was broader than necessary
**Severity: Medium — Remediated**

- `store_payment_settings` reads are now limited to active owner/admin/manager/cashier/accountant roles.
- `customer_credit_ledger` reads now require the relevant customer-read or orders-read module permission.

### F-07 — GitHub Actions permissions and dependency installation
**Severity: Medium — Hardened; lockfile still outstanding**

**Fix applied**
- Deployment permissions are scoped by job.
- Checkout no longer persists the repository token in Git configuration.
- GitHub Actions versions were updated.
- Node.js 24 is used.
- npm install lifecycle scripts are disabled with `--ignore-scripts`.
- The build runs `npm audit --audit-level=high`.
- Direct npm dependencies are pinned to exact versions.
- Dependabot weekly update checks were added for npm and GitHub Actions.

**Outstanding**
- The repository does not currently contain `package-lock.json`. Transitive dependency versions are therefore not reproducibly locked. A lockfile must be generated and committed in a network-enabled build environment, then the workflow should move to `npm ci`.

## 3. Controls verified

| Control | Result |
|---|---|
| RLS on all inspected public/private tables | Pass — no tables without RLS |
| Anonymous public-table grants | Pass — subscription plan read only |
| Dangerous table privileges | Pass — no TRUNCATE / REFERENCES / TRIGGER / MAINTAIN remain for anon/authenticated |
| Anonymous SECURITY DEFINER execution | Pass — none found |
| Public views | Pass — all inspected views use `security_invoker=true` |
| Payment Storage bucket | Pass — private |
| Store payment settings writes | Pass — owner-only insert/update/delete |
| Payment asset tenant paths | Pass — organization UUID path and role checks |
| Stripe claim RPC | Pass — service_role only |
| Sensitive RPC module checks | Pass — four updated functions verified |
| Edge Functions | Pass — all six deployed functions report ACTIVE |
| Edge Function JWT | Pass — all require JWT except the Stripe webhook, which verifies Stripe signatures itself |
| Supabase health advisor | Pass — no health lints returned |
| Dangerous HTML execution sinks in inspected POS component | Pass — no `dangerouslySetInnerHTML`, `innerHTML`, `eval`, or `new Function` found |

The intentional public access to active subscription plans is limited to read-only. The `pos_payment_events` table has RLS enabled and no client policy/grant; this is intentional because it is a webhook idempotency ledger accessed by the service role only.

## 4. Remaining warnings / actions required

### R-01 — Leaked Password Protection is disabled
**Severity: Medium — Not changed by this audit**

Supabase Security Advisor still reports leaked-password protection disabled. The available connected Supabase actions do not expose the Auth password-security setting, so it was not changed through this audit.

**Required manual action**
1. Open Supabase Dashboard → Authentication → Settings / Security and Protection (wording may vary).
2. Enable leaked-password protection.
3. Set a strong minimum password length and enable MFA for owner/admin accounts where available.
4. Save and verify the Auth Security Advisor warning clears.

### R-02 — Default grants owned by `supabase_admin`
**Severity: Medium — Existing objects secured; future default ACL requires project-admin action**

The database reports a default ACL for role `supabase_admin` that includes anonymous table grants in the public schema. An attempt to alter that role's default privileges through the connected SQL role was rejected with `permission denied to change default privileges`.

All current public tables were secured and verified. The default ACL for objects created by `postgres` was hardened. The project owner/DB administrator should remove anonymous default table grants from `supabase_admin` (and review default privileges for exposed schemas) so future objects cannot inherit them.

### R-03 — SECURITY DEFINER advisor warnings remain
**Severity: Review / intentional RPC surface**

Supabase still reports 18 authenticated-callable SECURITY DEFINER functions. These are intended application RPCs. They use an empty search path and were reviewed for their authorization checks; anonymous execution was not found. Do not blindly revoke them because the application calls these RPCs. Continue reviewing any new security-definer function before granting authenticated execution.

### R-04 — Dependency lockfile and CI result
**Severity: Medium — Outstanding**

A `package-lock.json` was not present in the repository and could not be generated in this environment because npm registry access was unavailable. A completed GitHub Actions build/audit result was not available during this review. Do not treat the static code review as proof that the latest deployment passed.

### R-05 — Runtime secrets and live payment validation
**Severity: Operational verification**

The source code uses server-side `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and `SUPABASE_SERVICE_ROLE_KEY` as Edge Function secrets. Their actual configured values, age, and rotation status cannot be read from the connected tools. Confirm they exist only as Supabase Edge Function secrets and rotate any value that was ever committed to GitHub or shared publicly.

A real Stripe test-mode payment, connected-account webhook delivery, refund, and bank-credit reconciliation still need to be exercised with a store owner account. EDC approval codes remain manual references from the physical terminal and are not verified by the POS.

## 5. Verification details

Post-remediation SQL checks returned:
- `rls_off = []`
- `dangerous_grants = []`
- `anon_grants = [{ public.subscription_plans, SELECT }]`
- `anon_definer = []`
- Stripe claim RPC: authenticated=false, anon=false, service_role=true
- Module permission checks: checkout=true, confirm=true, credit=true, stock=true

All six deployed Edge Functions reported ACTIVE. The three Stripe POS / Connect / webhook functions and the two billing functions were re-fetched after deployment to confirm the hardened code was live.

## 6. Recommended next steps before public launch

1. Enable leaked-password protection and MFA for privileged accounts.
2. Have the project database administrator harden `supabase_admin` default privileges.
3. Generate and commit `package-lock.json`; change CI to `npm ci`.
4. Confirm the latest GitHub Actions run passed both npm audit and Next.js build.
5. Perform a two-store authorization test with separate owner/cashier accounts (read, write, Storage, RPC, and cross-store IDOR cases).
6. Complete Stripe test-mode checkout, duplicate-click, stale-webhook, expired-session, and refund tests.
7. Rotate any historical secrets that may have been exposed before this audit.

**Overall conclusion:** The highest-risk current table-grant issue and the identified payment authorization / session replay weaknesses have been remediated and verified at the database/function level. StoreFlow should not yet be labelled fully production-secure until the outstanding Auth settings, `supabase_admin` default ACL, lockfile/CI verification, and live payment tests are completed.
