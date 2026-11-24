-- StoreFlow multi-tenant schema. Apply in Supabase SQL editor or migration workflow.
create extension if not exists pgcrypto;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','manager','cashier','hr','accountant','employee')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);
create index if not exists organization_members_user_idx on public.organization_members(user_id, organization_id);

create table if not exists public.role_permissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  role text not null,
  module text not null,
  action text not null check (action in ('read','create','update','delete','approve')),
  allowed boolean not null default false,
  unique (organization_id, role, module, action)
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sku text not null,
  name text not null,
  category text,
  cost numeric(12,2) not null default 0 check(cost >= 0),
  price numeric(12,2) not null default 0 check(price >= 0),
  stock numeric(12,3) not null default 0,
  min_stock numeric(12,3) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id, sku)
);

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_code text not null,
  user_id uuid references auth.users(id) on delete set null,
  full_name text not null,
  position text,
  department text,
  employment_type text check(employment_type in ('permanent','part_time','contract','temporary')),
  start_date date,
  phone text,
  emergency_contact jsonb not null default '{}'::jsonb,
  payment_channel jsonb not null default '{}'::jsonb,
  base_salary numeric(12,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(organization_id, employee_code)
);

create table if not exists public.shifts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  shift_date date not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  check(ends_at > starts_at)
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date date not null,
  clock_in timestamptz,
  clock_out timestamptz,
  overtime_minutes integer not null default 0 check(overtime_minutes >= 0),
  late_minutes integer not null default 0 check(late_minutes >= 0),
  status text not null default 'present' check(status in ('present','late','absent','leave')),
  created_at timestamptz not null default now(),
  unique(employee_id, work_date)
);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  leave_type text not null,
  starts_on date not null,
  ends_on date not null,
  reason text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  check(ends_on >= starts_on)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  tier text not null default 'bronze' check(tier in ('bronze','silver','gold','platinum')),
  points integer not null default 0 check(points >= 0),
  credit_limit numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  receipt_no text not null,
  customer_id uuid references public.customers(id) on delete set null,
  cashier_id uuid references auth.users(id),
  subtotal numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  payment_method text not null,
  status text not null default 'completed' check(status in ('pending','completed','refunded','cancelled')),
  created_at timestamptz not null default now(),
  unique(organization_id, receipt_no)
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity numeric(12,3) not null check(quantity > 0),
  unit_price numeric(12,2) not null check(unit_price >= 0),
  unit_cost numeric(12,2) not null default 0,
  line_total numeric(12,2) not null
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  movement_type text not null check(movement_type in ('purchase','sale','return','adjustment','transfer')),
  quantity_delta numeric(12,3) not null,
  reference text,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null,
  category text not null,
  amount numeric(12,2) not null check(amount >= 0),
  expense_date date not null default current_date,
  payment_status text not null default 'pending' check(payment_status in ('pending','paid','void')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.payroll_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  pay_date date,
  status text not null default 'draft' check(status in ('draft','approved','paid')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  check(period_end >= period_start)
);

create table if not exists public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  payroll_period_id uuid not null references public.payroll_periods(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  base_pay numeric(12,2) not null default 0,
  allowances numeric(12,2) not null default 0,
  overtime_pay numeric(12,2) not null default 0,
  commission numeric(12,2) not null default 0,
  bonus numeric(12,2) not null default 0,
  deductions numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0,
  social_security numeric(12,2) not null default 0,
  net_pay numeric(12,2) generated always as (base_pay + allowances + overtime_pay + commission + bonus - deductions - tax - social_security) stored,
  unique(payroll_period_id, employee_id)
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_logs_org_created_idx on public.audit_logs(organization_id, created_at desc);

-- Tenant isolation: all organization-owned rows are visible only to active members.
alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_members enable row level security;
alter table public.role_permissions enable row level security;
alter table public.products enable row level security;
alter table public.employees enable row level security;
alter table public.shifts enable row level security;
alter table public.attendance enable row level security;
alter table public.leave_requests enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.expenses enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_items enable row level security;
alter table public.audit_logs enable row level security;

create policy "profile self read" on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "profile self insert" on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy "profile self update" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "members read own memberships" on public.organization_members for select to authenticated using (user_id = (select auth.uid()));
create policy "organization members read org" on public.organizations for select to authenticated using (
  exists(select 1 from public.organization_members m where m.organization_id = id and m.user_id = (select auth.uid()) and m.is_active)
);

-- Organization-scoped tables. Policies intentionally grant authenticated members basic access;
-- fine-grained role_permissions enforcement must also be performed by trusted server/API actions.
do $$
declare t text;
begin
  foreach t in array array['role_permissions','products','employees','shifts','attendance','leave_requests','customers','sales','sale_items','stock_movements','expenses','payroll_periods','payroll_items','audit_logs']
  loop
    execute format('create policy %I on public.%I for select to authenticated using (exists(select 1 from public.organization_members m where m.organization_id = organization_id and m.user_id = (select auth.uid()) and m.is_active))', t || '_member_select', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (exists(select 1 from public.organization_members m where m.organization_id = organization_id and m.user_id = (select auth.uid()) and m.is_active))', t || '_member_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (exists(select 1 from public.organization_members m where m.organization_id = organization_id and m.user_id = (select auth.uid()) and m.is_active)) with check (exists(select 1 from public.organization_members m where m.organization_id = organization_id and m.user_id = (select auth.uid()) and m.is_active))', t || '_member_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (exists(select 1 from public.organization_members m where m.organization_id = organization_id and m.user_id = (select auth.uid()) and m.is_active))', t || '_member_delete', t);
  end loop;
end $$;

-- No anonymous table access. Authenticated grants are subject to RLS.
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
