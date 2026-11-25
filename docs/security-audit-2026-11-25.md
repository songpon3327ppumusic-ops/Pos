# StoreFlow Security Audit — 25 November 2026

## Scope and method
Reviewed the Android application source and manifest, Next.js static app, GitHub Actions workflows, Supabase public/private tables, RLS policies, SECURITY DEFINER RPCs, Storage buckets and policies, and all deployed StoreFlow Edge Functions. This is a configuration/source review plus targeted SQL smoke checks; it is not a third-party penetration test or a live multi-device test.

## Summary
- Public database tables: **36/36 have RLS enabled**.
- Tenant guard policies: **23/23 are RESTRICTIVE**.
- Store-license policies: **60/60 are RESTRICTIVE**; no permissive license-only policy remains.
- Public SECURITY DEFINER RPCs: **0 executable by anon**; all reviewed public SECURITY DEFINER functions have a pinned search_path.
- Storage buckets: **5/5 private**.
- Next.js build and `npm audit --audit-level=high`: **passed** on the audited branch.
- Android debug APK: latest build after permission hardening was still running at report preparation; an earlier build on the same branch passed. Signed Release AAB was not run.

## Findings fixed

### Critical — RLS permissive-policy composition could bypass tenant/license guards
PostgreSQL combines permissive policies with OR. License-only write policies could therefore weaken the intended tenant and module guards. Converted the license checks to restrictive policies that require both active organization membership and an active store license. Verified 60 restrictive license policies and zero permissive license policies.

### High — direct checkout RPC could bypass payment-method controls
The lower-level `checkout_sale_idempotent` RPC was callable by authenticated clients, allowing callers to bypass the payment-method checks in `create_pos_sale_with_payment`. Revoked execute for public/anon/authenticated. The intended entry point remains callable by authenticated users and validates the user's role, module permission, and enabled payment method. Confirmed the lower-level RPC is no longer executable by authenticated users.

### High — backup import could contain cross-organization foreign keys
Owner-only JSON restore previously trusted foreign-key IDs inside the uploaded JSON. Added same-organization foreign-key validation, active-membership validation for auth-user references, an 8 MB payload limit, a 20,000-row per-table limit, and merge-only/no-overwrite behavior. Smoke-tested the empty backup path and a malformed sale-item reference; invalid references were rejected before insertion.

### High — account deletion could remove a co-owned store
The prior cleanup selected every store where the deleting user was an owner, including stores with another active owner. Reworked deletion so co-owned stores are retained; stores with other active members but no other owner require ownership transfer; only sole-owner stores with no other active members are deleted. The Edge Function removes storage objects only for store IDs actually deleted.

### Medium — Storage write permissions were broader than necessary
Restricted general store asset upload/update/delete to active owner/admin/manager accounts. Restricted POS slip upload and the slip-attachment RPC to owner/admin/manager/cashier roles and to pending payment sales.

### Medium — invitation code lifetime and suspended-member reactivation
Moved invite codes to 128-bit random values, added a 30-day expiry, and stopped the invite join RPC from automatically reactivating inactive/rejected/suspended memberships. Confirmed the generated invite code length is 32 hex characters.

### Medium — unnecessary Android permissions and local-secret ignore rules
Removed unused CAMERA and Bluetooth permissions/features from AndroidManifest, explicitly enabled Supabase OAuth PKCE for Android deep links, and added a root .gitignore for local environment files, signing keys, build output and local tooling files while retaining .env.example.

### Medium — oversized or mislabeled image/backup uploads
Capped JSON import reads at 8 MB in Android, validated QR image signatures and dimensions before upload, and restricted accepted image types to JPG/PNG/WebP.

## Remaining risks / release blockers

1. **Supabase Leaked Password Protection is disabled.** The Supabase Auth security advisor still reports this warning. Enable it in Supabase Dashboard → Authentication → Settings / Password Security before production. This setting was not exposed by the connected database tools, so it was not changed here.
2. **22 authenticated SECURITY DEFINER RPCs remain flagged by the Supabase linter.** None are executable by anon, and all public SECURITY DEFINER functions have a pinned search_path. They are used for privileged business operations and must retain strict in-function user, membership, role, license, and module checks. Keep this set under review whenever RPCs are changed.
3. **JSON backups are plaintext.** They can contain customer, employee, payroll and bank-account data. The app now warns users to protect the file, but client-side password encryption has not yet been implemented.
4. **Google OAuth / Android deep-link verification still needs production validation.** The app now explicitly uses PKCE with the custom `storeflow://auth` scheme. Confirm Supabase Google provider credentials and allowed redirect URLs, then test callback handling with a second app/device. Verified HTTPS App Links are preferable where a domain can host `assetlinks.json`.
5. **Privacy policy requires real controller/developer identity and contact details** before Play Store submission. The current policy explicitly flags this requirement; do not publish with placeholder contact information.
6. **Release signing and Play Store readiness are unverified.** A signed AAB, keystore backup, Play App Signing, Data Safety form, target API review and Play policy review remain.
7. **Payment-provider production validation remains.** Stripe webhook signature verification and payment-state checks are present in the deployed function, but test/live secrets, Connect webhook setup, real THB test transactions, refund/chargeback handling and settlement reconciliation need an end-to-end test.
8. **No independent two-tenant penetration test or physical-device QA was performed.** Test two separate accounts across two stores for read/write isolation, staff permissions, backup/restore, attendance, offline sync, QR slips and account deletion before production.

## Performance notes
The Supabase performance advisor's 11 unindexed foreign-key findings were addressed with indexes. The remaining unused-index notices are informational and should be evaluated only after real workload telemetry; do not remove them solely because the project is new.

## Changed source
- `supabase/migrations/202611250001_storeflow_security_audit_hardening.sql`
- `supabase/migrations/202611250002_storeflow_storage_role_hardening.sql`
- `supabase/migrations/202611250003_storeflow_invite_security.sql`
- `supabase/functions/storeflow-delete-account/index.ts` (private object cleanup paginates through large folders)
- Android manifest, repository, settings/backup UI
- Root `.gitignore`, Dependabot and CI workflow

## Release decision
**Not yet production/Play Store ready.** The critical database authorization paths have been hardened and the web CI security audit passed, but leaked-password protection, release signing, provider configuration, privacy contact details and real-device / multi-tenant end-to-end tests remain.
