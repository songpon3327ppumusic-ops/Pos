# StoreFlow — All-in-One Store Management System

Next.js 14 App Router · React · TypeScript · Tailwind · Supabase Auth / Postgres · Recharts.

## Supabase project
- Project: StoreFlow
- Region: Southeast Asia (Singapore)
- Project ref: `tjunaxajcxwxirneopar`
- Database migration `storeflow_core` has been applied.
- Tenant organization `StoreFlow` has been created (slug: `storeflow`).

## Local setup
1. Copy `.env.example` to `.env.local` (the file contains the public project URL and publishable key).
2. Create the first Auth user in Supabase Authentication, or sign up through the app once deployed.
3. Add the first owner membership using the Auth user's UUID:

```sql
insert into public.organization_members (organization_id, user_id, role)
values ('68365882-e031-4e6a-8200-065967d3101d', 'YOUR_AUTH_USER_UUID', 'owner')
on conflict (organization_id, user_id) do update set role = 'owner', is_active = true;
```

4. Install and run:
```bash
npm install
npm run dev
```

## Supabase security
- SSR cookie-based auth via `@supabase/ssr`; unauthenticated routes are redirected to `/login`.
- RLS enabled for every table in the public schema created by the migration.
- Tenant row isolation by active organization membership.
- Role-limited database writes: owner/admin/manager may insert/update; owner/admin may delete.
- The `role_permissions` matrix is currently schema-only; fine-grained module permissions and approval rules still need server/API enforcement.
- Never expose a service-role key in browser code or `NEXT_PUBLIC_*` variables.

## Included demo screens
Dashboard, POS cart and checkout (mock), order history, inventory, employees and leave requests, payroll overview, CRM/loyalty, expenses, reports/CSV, role permission matrix and audit log.

## Important implementation boundary
Login/session protection is wired to Supabase once environment variables are configured. The existing operational screens still use in-memory Mock Data; they are not yet reading/writing the Postgres tables. Payroll calculations, payment processing, stock deduction transactions, permission-aware API enforcement, production audit triggers, and end-to-end tests need further implementation.
