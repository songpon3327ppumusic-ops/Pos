# StoreFlow Security Audit — 25 November 2026

## Executive summary

This is a source/configuration/database security review of the StoreFlow repository and linked Supabase project. It is not a third-party penetration test and does not certify that every possible vulnerability is absent.

### Verified database and storage posture

- Public schema: 36/36 tables have Row Level Security (RLS) enabled; 0 tables without RLS.
- Private schema: 4/4 tables have RLS enabled.
- Storage: \`business-documents\`, \`store-assets\`, and \`store-payment-assets\` are all private buckets.
- Anonymous database grants were revoked except read access to the public subscription-plan catalogue.
- Tenant guard policies on organization-owned tables are RESTRICTIVE, so they are combined with role/module policies rather than being bypassed by permissive-policy OR behavior.
- A simulated authenticated user from one store could not read a separate test organization.
- The public browser key in \`.env.example\` is a Supabase publishable key. No service-role, Stripe secret, or webhook secret was found in the selected configuration and Edge Function source files inspected; this is not a repository-wide secret-scanning certification.

## Changes applied during this audit

### 1. Database authorization and payment integrity

- Revoked authenticated/anonymous execution of the internal owner slip-review implementation. The public RPC is now a narrow SECURITY DEFINER wrapper that requires an authenticated identity and delegates to the private implementation, which checks active owner membership and the target sale's organization.
- Kept payment evidence and verification fields protected from direct client updates.
- Retained a deferred database constraint trigger that rejects a bank-transfer/PromptPay sale reaching \`paid\` unless it has a slip path, a transaction reference, and \`verified\` or \`manual_verified\` status. The deferred trigger permits a trusted transaction to write the evidence and paid state atomically.
- Added an atomic service-role-only rate-limit table and RPC for sensitive Edge Function actions: slip verification 5/10 min, provider-key changes 3/10 min, SaaS Checkout 5/10 min, Billing Portal 10/10 min, Stripe Connect onboarding 3/10 min, and POS Stripe Checkout 5/10 min per store/user/sale scope.
- Kept private operational tables without client policies and without authenticated/anonymous grants.

### 2. Slip-verification Edge Function

- Added a 16 KiB request-body limit and JSON-shape validation.
- Added per-store/per-user limits: 5 slip-verification attempts per 10 minutes and 3 provider-key configuration attempts per 10 minutes.
- Validates actual JPEG, PNG, and WebP file signatures in addition to MIME type and the 4 MiB storage limit.
- Requires the provider response to state THB explicitly; a missing currency is no longer silently treated as THB.
- Keeps API credentials encrypted in the database and only decrypts them inside the Edge Function.
- Continues to fail closed: provider unavailability or insufficient recipient data results in Pending Review, not automatic payment confirmation.

### 3. Stripe billing webhook

- Continues to verify the Stripe signature against the raw body, enforce the timestamp tolerance, and reject test/live mode mismatches.
- Lifetime Checkout now checks THB currency, non-zero discounted total, configured Stripe Price ID, quantity, subtotal against the actual Stripe Price object, and that the Stripe customer matches the store's saved billing customer before granting lifetime entitlement.
- Subscription events now check the configured plan, billing interval, Price ID, THB currency, unit amount, recurring interval, quantity, and saved store billing-customer binding before updating the store subscription. Existing subscriptions can still process cancellation/payment-status events if a plan is later deactivated.
- Entitlements continue to be granted only from signed webhook events, not from the browser return URL.

### 4. GitHub Actions and dependency hygiene

- Pinned the GitHub Actions used by CI and Pages deployment to immutable commit SHAs.
- Added \`npm audit --audit-level=high\` to CI.
- Disabled npm lifecycle scripts during CI dependency installation.
- Pinned the jsQR dependency to an exact version.

## Security tests performed

| Test | Result |
|---|---|
| Count public tables with RLS | PASS — 36/36 |
| Count private tables with RLS | PASS — 4/4 |
| Private Storage bucket configuration | PASS — all 3 buckets private |
| Cross-store organization read simulation | PASS — other store not visible |
| Authenticated direct edit of payment verification fields | PASS — rejected with 42501 |
| Trusted service-role attempt to mark a transfer paid without slip/reference/verification | PASS — rejected by deferred constraint with 23514 |
| Owner manual-review RPC with active owner identity | PASS — sale moved to manual_verified/paid in a rolled-back test transaction |
| Slip-verification rate-limit logic | PASS — requests 1–3 allowed, request 4 denied in a rolled-back test transaction |
| Stripe live webhook end-to-end event | NOT RUN — requires a controlled Stripe test event and configured webhook secrets |
| Real EasySlip transaction verification | NOT RUN — requires a store-owned EasySlip API key and a real test slip |
| External penetration test / automated DAST | NOT RUN |

All database test transactions were rolled back; no test sale or test organization was retained.

## Runtime log review (last 24 hours at audit time)

- Auth audit logs showed 7 login events, token refresh/revoke events, and no recorded failed-login action in the sampled 24-hour window. This is not proof that credential attacks never occurred; it only describes the retained log window.
- Six POST requests to `storeflow-pos-connect` returned HTTP 500 under the same authenticated owner account. The store's `stripe_connect_account_id` remains empty and Stripe flags remain disabled. These requests do not by themselves indicate intrusion; they indicate an unresolved Stripe Connect onboarding/API error. The underlying Stripe error is not recoverable from the retained edge access logs. The handler was updated to log sanitized Stripe error codes/statuses and return upstream failures as HTTP 502 for future diagnosis. Verify the platform's Stripe account country, Connect availability, requested capabilities, and secret mode before enabling Connect payments.

## Historical payment records requiring owner reconciliation

Four existing sales were found with `payment_status = paid` and bank-transfer/PromptPay methods but no stored slip or transaction reference. They were marked `legacy_unverified` rather than silently treated as verified or automatically reversed. The owner must reconcile these four receipts against the actual bank statement before relying on the historical paid status.

## Remaining risks and owner actions

### High priority

1. **Leaked-password protection is disabled in Supabase Auth.** The Supabase Security Advisor reports this as a warning. Enable it in Authentication → Settings → Password Security if supported by the project's plan. Set a server-side minimum password length of at least 12 characters and enable the strongest available character requirements. Client-side \`minLength\` alone is not an enforcement boundary.
2. **MFA is not enforced by the current login flow.** Enable and require MFA for owner/admin accounts before treating the control plane as strongly protected. AAL2 enforcement needs a deliberate enrollment and recovery flow to avoid locking out existing owners.

### Medium priority

3. **No committed \`package-lock.json\` was found.** Direct dependency and GitHub Action pinning was improved, but transitive npm dependencies are not yet reproducibly locked. Generate and commit a reviewed lockfile, then switch CI to \`npm ci\`.
4. **GitHub branch protection could not be inspected by the connected GitHub integration (HTTP 403).** The repository owner should require pull requests, require successful CI checks, block force pushes/deletions, and restrict who can push to \`main\`.
5. **GitHub secret-scanning alert status could not be read by the connected integration.** Enable secret scanning and push protection where available, and review existing alerts in repository Settings → Security.
6. **The repository is public.** The Supabase publishable key is designed to be public; all service-role, Stripe, webhook, encryption, and provider secrets must remain only in Supabase Function Secrets. Rotate any secret that has ever been committed or pasted into a public issue/log.

### Low / operational

7. Security Advisor reports callable SECURITY DEFINER functions. These are intentional RPCs in this application and their definitions were reviewed for authentication, tenant membership, role, and module checks. The warning is not itself proof of exploitation, but every new SECURITY DEFINER function must receive the same review.
8. Security Advisor reports private tables with RLS enabled and no policies. These are intentional server-only tables with no client grants; do not add permissive policies just to silence the informational warning.
9. Run a controlled Stripe test-mode checkout and webhook replay test, EasySlip test transactions, and an external penetration test before production launch.

## Important interpretation

A successful CI build, RLS coverage, or a green Security Advisor does not prove the application is invulnerable. The remaining owner actions above are part of the security baseline, not optional cosmetic warnings.
