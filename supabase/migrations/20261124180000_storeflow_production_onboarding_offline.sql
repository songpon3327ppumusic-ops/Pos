-- StoreFlow production onboarding, trial, role guards, idempotent POS sync, and Realtime
begin;

alter table public.organizations
  add column if not exists invite_code text,
  add column if not exists plan_type text not null default 'subscription'
    check (plan_type in ('subscription','lifetime'));

create unique index if not exists organizations_invite_code_uidx
  on public.organizations (upper(invite_code)) where invite_code is not null;

alter table public.organization_members
  add column if not exists membership_status text not null default 'active'
    check (membership_status in ('pending','active','rejected','suspended'));

update public.organization_members
set membership_status = case when is_active then 'active' else 'pending' end
where membership_status is distinct from case when is_active then 'active' else 'pending' end;

create index if not exists organization_members_pending_idx
  on public.organization_members (organization_id, membership_status, created_at desc);

-- Trial metadata already exists in the subscription schema; make the trial policy explicit.
alter table public.organization_subscriptions
  add column if not exists trial_started_at timestamptz,
  add column if not exists plan_type text not null default 'subscription'
    check (plan_type in ('subscription','lifetime'));

update public.organization_subscriptions
set trial_started_at = coalesce(trial_started_at, created_at),
    trial_ends_at = coalesce(trial_ends_at, created_at + interval '7 days')
where status in ('free','trialing') and trial_ends_at is null;

-- Product catalogue / pricing. Stripe price IDs must be configured before accepting live payment.
insert into public.subscription_plans
(id,name,description,monthly_price_thb,yearly_price_thb,limits,features,sort_order,is_active)
values
('lifetime','Lifetime','ซื้อขาด จ่ายครั้งเดียว ใช้งานได้ตลอดชีพ พร้อมอัปเดตฟีเจอร์ฟรี',2590,2590,
 '{"employees":-1,"products":-1,"branches":-1,"storage_mb":51200}'::jsonb,
 '{"pos":true,"inventory":true,"customers":true,"reports_basic":true,"payroll":true,"advanced_reports":true,"priority_support":false,"lifetime_updates":true,"promo_price_thb":2590,"regular_price_thb":3990,"saving_thb":1400}'::jsonb,
 5,true)
on conflict (id) do update set
 name=excluded.name,description=excluded.description,
 monthly_price_thb=2590,yearly_price_thb=2590,
 limits=excluded.limits,features=excluded.features,is_active=true,sort_order=5,updated_at=now();

-- A private lookup avoids exposing invite codes to non-owners.
create or replace function private.is_org_owner(p_org uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id=p_org and m.user_id=(select auth.uid())
      and m.is_active and m.membership_status='active' and m.role='owner'
  );
$$;
revoke all on function private.is_org_owner(uuid) from public, anon;
grant execute on function private.is_org_owner(uuid) to authenticated;

-- Signup metadata is used only by this trusted Auth trigger; it is never used as an RLS claim.
create or replace function private.handle_storeflow_signup()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'onboarding_role','owner');
  v_store_name text := nullif(trim(new.raw_user_meta_data->>'store_name'),'');
  v_invite text := upper(regexp_replace(coalesce(new.raw_user_meta_data->>'invite_code',''), '\s','','g'));
  v_org uuid;
  v_template uuid;
  v_slug text;
  v_invite_code text;
begin
  if v_role not in ('owner','cashier') then
    raise exception 'Invalid onboarding role';
  end if;

  insert into public.profiles(id,display_name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''), split_part(new.email,'@',1)))
  on conflict (id) do nothing;

  if v_role='owner' then
    if v_store_name is null or length(v_store_name)<2 or length(v_store_name)>120 then
      raise exception 'Store name must be between 2 and 120 characters';
    end if;
    v_slug := 'store-' || substr(replace(gen_random_uuid()::text,'-',''),1,12);
    v_invite_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    insert into public.organizations(name,slug,invite_code,plan_type)
    values(v_store_name,v_slug,v_invite_code,'subscription') returning id into v_org;

    insert into public.organization_members(organization_id,user_id,role,is_active,membership_status)
    values(v_org,new.id,'owner',true,'active')
    on conflict (organization_id,user_id) do update
      set role='owner',is_active=true,membership_status='active';

    insert into public.organization_subscriptions
      (organization_id,plan_id,billing_interval,status,trial_started_at,trial_ends_at,plan_type)
    values(v_org,'free','month','trialing',now(),now()+interval '7 days','subscription')
    on conflict (organization_id) do update set
      status='trialing',trial_started_at=now(),trial_ends_at=now()+interval '7 days',
      plan_id='free',plan_type='subscription',updated_at=now();

    select id into v_template from public.organizations where slug='storeflow' limit 1;
    if v_template is not null then
      insert into public.role_permissions(organization_id,role,module,action,allowed)
      select v_org,role,module,action,allowed from public.role_permissions
      where organization_id=v_template on conflict do nothing;
    end if;
  else
    if v_invite='' then raise exception 'Invite code is required for staff signup'; end if;
    select id into v_org from public.organizations
      where upper(invite_code)=v_invite limit 1;
    if v_org is null then raise exception 'Invite code is invalid'; end if;
    insert into public.organization_members(organization_id,user_id,role,is_active,membership_status)
    values(v_org,new.id,'cashier',false,'pending')
    on conflict (organization_id,user_id) do update
      set role='cashier',is_active=false,membership_status='pending';
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_storeflow on auth.users;
create trigger on_auth_user_created_storeflow
after insert on auth.users
for each row execute function private.handle_storeflow_signup();

-- Existing bootstrap function must not silently turn a staff signup into a new Owner account.
create or replace function public.bootstrap_store_owner(p_org_slug text default 'storeflow')
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare v_user uuid := auth.uid(); v_org uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select organization_id into v_org from public.organization_members
  where user_id=v_user and is_active and membership_status='active'
  order by created_at limit 1;
  if v_org is not null then return v_org; end if;
  raise exception 'No active store membership. Owner onboarding is completed during signup; staff must wait for approval.';
end;
$$;
revoke all on function public.bootstrap_store_owner(text) from public, anon;
grant execute on function public.bootstrap_store_owner(text) to authenticated;

create or replace function public.get_my_store_membership_state()
returns table(organization_id uuid, membership_status text, role text, organization_name text)
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select m.organization_id,m.membership_status,m.role,o.name
  from public.organization_members m
  join public.organizations o on o.id=m.organization_id
  where m.user_id=(select auth.uid())
  order by m.created_at desc limit 1;
$$;
revoke all on function public.get_my_store_membership_state() from public, anon;
grant execute on function public.get_my_store_membership_state() to authenticated;

create or replace function public.approve_store_member(p_member_id uuid, p_approve boolean default true)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.organization_members where id=p_member_id;
  if v_org is null or not private.is_org_owner(v_org) then
    raise exception 'Only the store owner can approve staff';
  end if;
  update public.organization_members
  set is_active=p_approve,
      membership_status=case when p_approve then 'active' else 'rejected' end
  where id=p_member_id and membership_status='pending';
  if not found then raise exception 'Pending membership not found'; end if;
end;
$$;
revoke all on function public.approve_store_member(uuid,boolean) from public, anon;
grant execute on function public.approve_store_member(uuid,boolean) to authenticated;

-- Staff may see only same-store products, and only today's sales for their own cashier account.
drop policy if exists sales_cashier_today_guard on public.sales;
create policy sales_cashier_today_guard on public.sales
as restrictive for select to authenticated
using (
  not exists (
    select 1 from public.organization_members m
    where m.organization_id=sales.organization_id and m.user_id=(select auth.uid())
      and m.role='cashier' and m.is_active and m.membership_status='active'
  )
  or (
    cashier_id=(select auth.uid())
    and created_at >= (date_trunc('day', now() at time zone 'Asia/Bangkok') at time zone 'Asia/Bangkok')
    and created_at < ((date_trunc('day', now() at time zone 'Asia/Bangkok') + interval '1 day') at time zone 'Asia/Bangkok')
  )
);

drop policy if exists sale_items_cashier_today_guard on public.sale_items;
create policy sale_items_cashier_today_guard on public.sale_items
as restrictive for select to authenticated
using (
  not exists (
    select 1 from public.organization_members m
    where m.organization_id=sale_items.organization_id and m.user_id=(select auth.uid())
      and m.role='cashier' and m.is_active and m.membership_status='active'
  )
  or exists (
    select 1 from public.sales s
    where s.id=sale_items.sale_id and s.organization_id=sale_items.organization_id
      and s.cashier_id=(select auth.uid())
      and s.created_at >= (date_trunc('day', now() at time zone 'Asia/Bangkok') at time zone 'Asia/Bangkok')
      and s.created_at < ((date_trunc('day', now() at time zone 'Asia/Bangkok') + interval '1 day') at time zone 'Asia/Bangkok')
  )
);

-- Role permission rows: cashiers can read stock and create POS orders, not inventory mutations or financial modules.
insert into public.role_permissions(organization_id,role,module,action,allowed)
select o.id,'cashier',v.module,v.action,v.allowed
from public.organizations o
cross join (values
 ('dashboard','read',true),('pos','read',true),('pos','create',true),
 ('inventory','read',true),('orders','read',true),('orders','create',true),
 ('inventory','create',false),('inventory','update',false),('inventory','delete',false),
 ('reports','read',false),('expenses','read',false),('payroll','read',false),
 ('permissions','read',false),('permissions','update',false),('billing','read',false)
) as v(module,action,allowed)
on conflict (organization_id,role,module,action) do update set allowed=excluded.allowed;

-- A durable idempotency ledger makes retries safe when a client loses the network after checkout committed.
create table if not exists private.pos_order_idempotency (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  idempotency_key uuid not null,
  sale_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key)
);
alter table private.pos_order_idempotency enable row level security;
revoke all on private.pos_order_idempotency from public, anon, authenticated;

create or replace function public.checkout_sale_idempotent(
  p_organization_id uuid,
  p_items jsonb,
  p_payment_method text,
  p_discount numeric default 0,
  p_tax numeric default 0,
  p_customer_id uuid default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare v_user uuid := auth.uid(); v_sale uuid; v_existing uuid; v_key uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null then raise exception 'Idempotency key is required'; end if;
  if not private.is_org_member(p_organization_id) then raise exception 'Not an active store member'; end if;
  v_key:=p_idempotency_key;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || v_key::text,0));
  select sale_id into v_existing from private.pos_order_idempotency
    where organization_id=p_organization_id and idempotency_key=v_key;
  if v_existing is not null then return v_existing; end if;
  insert into private.pos_order_idempotency(organization_id,idempotency_key,created_by)
  values(p_organization_id,v_key,v_user)
  on conflict do nothing;
  v_sale:=public.checkout_sale(p_organization_id,p_items,p_payment_method,p_discount,p_tax,p_customer_id);
  update private.pos_order_idempotency set sale_id=v_sale
  where organization_id=p_organization_id and idempotency_key=v_key;
  return v_sale;
end;
$$;
revoke all on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid) from public, anon;
grant execute on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid) to authenticated;

-- Realtime publication is opt-in per table; avoid duplicate publication errors.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='products') then
      alter publication supabase_realtime add table public.products;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='sales') then
      alter publication supabase_realtime add table public.sales;
    end if;
  end if;
end $$;

create index if not exists sales_org_created_idx on public.sales(organization_id,created_at desc);
create index if not exists sales_org_cashier_created_idx on public.sales(organization_id,cashier_id,created_at desc);

commit;
