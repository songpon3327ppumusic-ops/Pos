-- StoreFlow SaaS subscriptions, plan catalogue, and platform billing events
create table if not exists public.subscription_plans (
 id text primary key,
 name text not null,
 description text not null default '',
 monthly_price_thb integer not null default 0 check (monthly_price_thb >= 0),
 yearly_price_thb integer not null default 0 check (yearly_price_thb >= 0),
 stripe_product_id text,
 stripe_monthly_price_id text,
 stripe_yearly_price_id text,
 limits jsonb not null default '{}'::jsonb,
 features jsonb not null default '{}'::jsonb,
 is_active boolean not null default true,
 sort_order integer not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
insert into public.subscription_plans
(id,name,description,monthly_price_thb,yearly_price_thb,limits,features,sort_order)
values
('free','Free','เริ่มต้นใช้งาน StoreFlow',0,0,'{"employees":2,"products":100,"branches":1,"storage_mb":250}'::jsonb,'{"pos":true,"inventory":true,"customers":true,"reports_basic":true,"payroll":false,"advanced_reports":false,"priority_support":false}'::jsonb,1),
('starter','Starter','สำหรับร้านค้าขนาดเล็ก',199,1990,'{"employees":5,"products":1000,"branches":1,"storage_mb":2048}'::jsonb,'{"pos":true,"inventory":true,"customers":true,"reports_basic":true,"payroll":true,"advanced_reports":false,"priority_support":false}'::jsonb,2),
('pro','Pro','สำหรับร้านค้าที่กำลังเติบโต',399,3990,'{"employees":20,"products":10000,"branches":3,"storage_mb":10240}'::jsonb,'{"pos":true,"inventory":true,"customers":true,"reports_basic":true,"payroll":true,"advanced_reports":true,"priority_support":true}'::jsonb,3),
('business','Business','สำหรับธุรกิจหลายสาขา',799,7990,'{"employees":100,"products":50000,"branches":10,"storage_mb":51200}'::jsonb,'{"pos":true,"inventory":true,"customers":true,"reports_basic":true,"payroll":true,"advanced_reports":true,"priority_support":true,"api_access":true}'::jsonb,4)
on conflict (id) do update set name=excluded.name,description=excluded.description,monthly_price_thb=excluded.monthly_price_thb,yearly_price_thb=excluded.yearly_price_thb,limits=excluded.limits,features=excluded.features,sort_order=excluded.sort_order,updated_at=now();
create table if not exists public.organization_subscriptions (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null unique references public.organizations(id) on delete cascade,
 plan_id text not null references public.subscription_plans(id),
 billing_interval text not null default 'month' check (billing_interval in ('month','year','lifetime')),
 status text not null default 'free' check (status in ('free','trialing','active','past_due','canceled','incomplete','unpaid','paused','expired')),
 stripe_customer_id text unique,
 stripe_subscription_id text unique,
 stripe_price_id text,
 current_period_start timestamptz,
 current_period_end timestamptz,
 trial_ends_at timestamptz,
 cancel_at_period_end boolean not null default false,
 canceled_at timestamptz,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.subscription_billing_events (
 id uuid primary key default gen_random_uuid(),
 stripe_event_id text not null unique,
 event_type text not null,
 organization_id uuid references public.organizations(id) on delete set null,
 processed_at timestamptz not null default now(),
 payload jsonb not null default '{}'::jsonb
);
create table if not exists public.platform_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
insert into public.platform_admins(user_id) values ('1621cbbb-9bd8-4151-8236-ba8013944469') on conflict (user_id) do nothing;
alter table public.subscription_plans enable row level security;
alter table public.organization_subscriptions enable row level security;
alter table public.subscription_billing_events enable row level security;
alter table public.platform_admins enable row level security;
drop policy if exists subscription_plans_public_read on public.subscription_plans;
create policy subscription_plans_public_read on public.subscription_plans for select to anon,authenticated using (is_active=true);
drop policy if exists org_subscriptions_member_read on public.organization_subscriptions;
create policy org_subscriptions_member_read on public.organization_subscriptions for select to authenticated using (exists(select 1 from public.organization_members m where m.organization_id=organization_subscriptions.organization_id and m.user_id=(select auth.uid()) and m.is_active=true));
drop policy if exists platform_admins_self_read on public.platform_admins;
create policy platform_admins_self_read on public.platform_admins for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists billing_events_admin_read on public.subscription_billing_events;
create policy billing_events_admin_read on public.subscription_billing_events for select to authenticated using (exists(select 1 from public.platform_admins a where a.user_id=(select auth.uid())));
insert into public.organization_subscriptions(organization_id,plan_id,billing_interval,status) values ('68365882-e031-4e6a-8200-065967d3101d','free','month','free') on conflict (organization_id) do nothing;
create index if not exists org_subscriptions_status_idx on public.organization_subscriptions(status,current_period_end);
create index if not exists subscription_events_org_idx on public.subscription_billing_events(organization_id,processed_at desc);
