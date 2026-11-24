# StoreFlow — All-in-One Store Management System

Next.js 14 App Router · React · TypeScript · Tailwind · Supabase Auth / Postgres · Recharts.

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
3. Apply `supabase/migrations/202611240001_storeflow_core.sql` in the Supabase SQL Editor.
4. Create the first Auth user in Supabase Authentication.
5. Bootstrap the first tenant and owner membership in the SQL Editor (replace the values with your own):

```sql
insert into public.organizations (name, slug)
values ('My Store', 'my-store')
returning id;

-- Use the returned organization UUID and the Auth user UUID:
insert into public.organization_members (organization_id, user_id, role)
values ('YOUR_ORGANIZATION_UUID', 'YOUR_AUTH_USER_UUID', 'owner');
```

6. Install and run:
```bash
npm install
npm run dev
``

## Supabase security
- SSR cookie-based auth via `@supabase/ssr`; unauthenticated routes are redirected to `/login`.
- RLS enabled for every table in the public schema created by the migration.
- Tenant row isolation by active organization membership.
- Role-limited database writes: owner/admin/manager may insert/update; owner/admin may delete.
- Never expose a service-role key in browser code or `NEXT_PUBLIC_*` variables.

## Included demo screens
Dashboard, POS cart and checkout (mock), order history, inventory, employees and leave requests, payroll overview, CRM/loyalty, expenses, reports/CSV, role permission matrix and audit log.

## Important implementation boundary
Login/session protection is wired to Supabase once environment variables are configured. The existing operational screens still use in-memory Mock Data; they are not yet reading/writing the Postgres tables. The database migration is committed but has not been applied to a live project. Payroll calculations, payment processing, stock deduction transactions, permission-aware API enforcement, and production audit triggers need further implementation and tests.
