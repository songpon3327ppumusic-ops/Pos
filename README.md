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

## Business Document Center
- Multi-tenant business document center built on the existing `business_documents` and `business_document_items` tables, with `document_settings`, `documents`, and `document_items` security-invoker compatibility views exposing `store_id`.
- Monthly per-store/per-type document numbering; tax modes (VAT excluded, VAT included, non-VAT); Thai baht text; original/copy A4 print and 58/80mm receipt print.
- Document types: full/abbreviated tax invoices, 50 Tawi withholding certificate, credit/debit notes, delivery note, goods receipt, PO/PR, quotation, billing note, receipt/deposit vouchers, payment/petty-cash vouchers, and expense certificate.
- POS sales history includes a direct "ออกเอกสาร" action; the selected sale's line items and customer are imported and the source sale is linked to the new document.
- Goods receipt confirmation posts stock movements and increments the linked products once, guarded by a transaction and duplicate-post protection.
- Private `business-documents` Storage bucket stores logos, signatures, stamps, and document attachments under the organization UUID path. Storage writes are restricted by tenant membership and document/settings permissions.
- Employee invite code generation is owner-only; `get_store_invite_code()` now creates a code when the organization does not yet have one.

### Migration and statutory-document notes
Apply the migration files under `supabase/migrations` in version order. The document compatibility views are aliases over the existing organization-scoped tables; they intentionally avoid duplicating records. The 50 Tawi layout is a print template, not a certified Revenue Department e-filing form; confirm statutory wording, rates, and required fields with the Revenue Department/accountant before issuing official certificates.

## Store payment and POS checkout
- Per-store `store_payment_settings` keyed by `organization_id` (the current StoreFlow store/tenant key), with owner-only write RLS and member read access.
- Dynamic EMVCo PromptPay QR payload with the invoice amount, or private uploaded bank QR image; bank transfer account display and slip upload in the private `store-payment-assets` bucket.
- Cash checkout with tendered amount and change, EDC approval code / last four digits, and customer credit ledger with partial settlement.
- QR / bank transfer sales remain `pending` until a cashier explicitly verifies the actual bank credit and confirms payment. A QR image or uploaded slip alone is never treated as bank confirmation.
- Stripe Connect onboarding and direct-charge Checkout use server-side Edge Functions; the existing signed Stripe webhook updates POS sales to paid. The Stripe option stays hidden until the connected account can accept charges and a Connect webhook endpoint is detected.
- The existing subscription Stripe webhook now also handles connected-account POS Checkout events. Configure the same endpoint to listen to connected-account events: `https://tjunaxajcxwxirneopar.supabase.co/functions/v1/storeflow-stripe-webhook`.
- Daily reports separate paid cash, PromptPay, bank transfer, EDC and unpaid customer-credit totals.
- Omise/Opn remains disabled until a secure merchant-key onboarding and webhook integration is configured; no secret API keys are stored in browser-readable settings.

### Payment setup notes
1. Owner opens **ตั้งค่า → ช่องทางรับชำระเงิน**, enables the desired channels, and saves.
2. For dynamic PromptPay, enter a 10-digit mobile PromptPay ID or 13-digit national/tax ID. For static QR, upload the bank QR image.
3. For Stripe, complete Connect onboarding, configure the webhook endpoint for connected-account events, then use **ตรวจสอบสถานะ**. Enable Stripe checkout only after charges and webhook verification are both true.
4. EDC approval codes are cashier-entered references from the physical terminal; they are not automatically verified by the POS.
