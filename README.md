# StoreFlow — All-in-One Store Management System

Next.js 14 App Router · React · TypeScript · Tailwind · Supabase Auth / Postgres.

## Backend
- Supabase project: StoreFlow
- Project ref: `tjunaxajcxwxirneopar`
- Region: Southeast Asia (Singapore)
- Existing multi-tenant schema: organizations, memberships, products, sales, stock, customers, employees, expenses, payroll and audit logs.
- Browser uses only the Supabase publishable key. Never expose a secret/service-role key in frontend code.

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Install dependencies: `npm install`.
3. Run: `npm run dev`.
4. Open `/Pos/login/`, create the first owner account, and verify the email if Supabase email confirmation is enabled.

The first authenticated account is assigned the owner role for the existing `storeflow` organization through the guarded `bootstrap_store_owner` database function. Once the organization has an owner, later signups cannot claim ownership.

## Live modules in this implementation
- Supabase Auth sign-up and sign-in.
- Organization membership and role-based navigation.
- Products: create, update, list and search.
- Stock adjustment with stock movement and audit records.
- POS: server-side price lookup, stock validation, atomic sale + sale item writes, stock deduction, receipt number and audit record.
- Sales history and CSV export.
- Customers, employees and expenses: create and list.
- Dashboard and sales summaries derived from database rows only.
- Empty states are shown when no real data exists; no demo rows or fabricated KPI values are loaded.

## Not yet implemented
- Payment gateway collection / PromptPay verification (the POS currently records the selected payment method only).
- Employee invitations and multi-user onboarding after the first owner.
- Payroll processing, detailed permissions matrix, leave/attendance workflows, supplier purchasing and advanced reporting.
- End-to-end browser tests and production launch review.

## Database functions
Migration `202611240002_live_operations.sql` adds:
- `bootstrap_store_owner`: guarded first-owner setup.
- `checkout_sale`: atomic POS checkout and stock deduction, restricted to authenticated store members with sales permissions.
- `adjust_stock`: role-checked stock adjustments with movement and audit records.
- Migration `202611240003_fix_organization_read_policy.sql`: restricts organization records to active members using the correct organization ID.

All three functions validate the authenticated user and explicitly revoke execution from public/anonymous roles. Keep all service-role/secret keys server-side.
