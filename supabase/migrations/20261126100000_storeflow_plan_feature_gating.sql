-- StoreFlow plan feature gating + quotas
-- Existing schema verified on project tjunaxajcxwxirneopar:
-- organizations, organization_subscriptions, platform_admins, products, employees,
-- store_payment_settings, private.has_module_access, private.has_active_store_license.
begin;

-- Super Admin role is server-owned app_metadata, not user_metadata.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('role', 'platform_admin')
where lower(email) = lower('songponsonma.3340@gmail.com');

insert into public.platform_admins(user_id)
select id from auth.users where lower(email)=lower('songponsonma.3340@gmail.com')
on conflict (user_id) do nothing;

-- This account's existing StoreFlow organization receives the requested lifetime license.
update public.organization_subscriptions s
set plan_id='lifetime',
    plan_tier='lifetime',
    plan_type='lifetime',
    billing_interval='lifetime',
    status='active',
    current_period_start=coalesce(current_period_start, now()),
    current_period_end=null,
    trial_started_at=null,
    trial_ends_at=null,
    updated_at=now(),
    metadata=coalesce(metadata,'{}'::jsonb) ||
        jsonb_build_object('granted_by','storeflow_super_admin','grant_reason','owner lifetime entitlement','price_thb',2590)
from public.organization_members m
join auth.users u on u.id=m.user_id
where s.organization_id=m.organization_id
  and m.is_active=true
  and m.membership_status='active'
  and lower(u.email)=lower('songponsonma.3340@gmail.com');

update public.organizations o
set plan_type='lifetime'
where exists (
  select 1 from public.organization_members m
  join auth.users u on u.id=m.user_id
  where m.organization_id=o.id and m.is_active=true
    and m.membership_status='active'
    and lower(u.email)=lower('songponsonma.3340@gmail.com')
);

-- Effective plan resolver. All authorization uses the verified auth.uid()/platform_admins row.
create or replace function private.storeflow_effective_plan(p_organization_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tier text;
  v_status text;
  v_plan_type text;
  v_trial_end timestamptz;
  v_period_end timestamptz;
begin
  if auth.uid() is not null and exists (
    select 1 from public.platform_admins a where a.user_id=(select auth.uid())
  ) then
    return 'lifetime';
  end if;

  select lower(coalesce(s.plan_tier,s.plan_id,'basic')),
         lower(coalesce(s.status,'expired')),
         lower(coalesce(s.plan_type,'subscription')),
         s.trial_ends_at, s.current_period_end
    into v_tier,v_status,v_plan_type,v_trial_end,v_period_end
  from public.organization_subscriptions s
  where s.organization_id=p_organization_id;

  if not found then return 'expired'; end if;

  if v_plan_type='lifetime' or v_tier='lifetime' then
    return case when v_status='active' then 'lifetime' else 'expired' end;
  end if;

  if v_status in ('trial','trialing') then
    return case when v_trial_end is not null and v_trial_end>now()
      then 'standard' else 'expired' end;
  end if;

  if v_status='free' then return 'basic'; end if;
  if v_status<>'active' then return 'expired'; end if;
  if v_period_end is not null and v_period_end<=now() then return 'expired'; end if;

  return case
    when v_tier in ('premium','business') then 'premium'
    when v_tier in ('standard','pro') then 'standard'
    else 'basic'
  end;
end;
$$;
revoke all on function private.storeflow_effective_plan(uuid) from public, anon, authenticated;
grant execute on function private.storeflow_effective_plan(uuid) to authenticated;

create or replace function private.storeflow_has_feature(
  p_organization_id uuid,
  p_feature text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_plan text := private.storeflow_effective_plan(p_organization_id);
begin
  if v_plan in ('premium','lifetime') then return true; end if;
  if v_plan='expired' then return false; end if;
  case p_feature
    when 'overview','pos','products','basic_sales_reports','staff' then return true;
    when 'shifts','attendance','store_payment_qr' then return v_plan='standard';
    when 'payroll_auto','tax_documents','barcode_scanner','receipt_printer' then return false;
    else return false;
  end case;
end;
$$;
revoke all on function private.storeflow_has_feature(uuid,text) from public, anon, authenticated;
grant execute on function private.storeflow_has_feature(uuid,text) to authenticated;

-- Enforce the same plan matrix at the existing module-RLS boundary.
create or replace function private.has_module_access(
  p_organization_id uuid, p_module text, p_action text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_role text;
  v_allowed boolean;
  v_plan text;
begin
  if auth.uid() is null then return false; end if;

  select m.role into v_role
  from public.organization_members m
  where m.organization_id=p_organization_id
    and m.user_id=(select auth.uid())
    and m.is_active=true
    and m.membership_status='active'
  limit 1;
  if v_role is null then return false; end if;

  v_plan := private.storeflow_effective_plan(p_organization_id);

  -- Expired stores retain SELECT/history access but cannot perform writes.
  if v_plan='expired' and p_action not in ('read','select') then return false; end if;

  if p_module in ('attendance','shifts') and v_plan not in ('standard','premium','lifetime') then
    return false;
  end if;
  if p_module='payroll' and v_plan not in ('premium','lifetime') then return false; end if;
  if p_module in ('documents','tax_documents','business_documents')
     and v_plan not in ('premium','lifetime') then return false; end if;

  if v_role in ('owner','admin') then return true; end if;
  if v_role='cashier' then
    return case
      when p_module='pos' then p_action in ('read','create')
      when p_module='orders' then p_action in ('read','create')
      when p_module='inventory' then p_action='read'
      else false
    end;
  end if;

  select rp.allowed into v_allowed
  from public.role_permissions rp
  where rp.organization_id=p_organization_id
    and rp.role=v_role and rp.module=p_module and rp.action=p_action
  limit 1;
  if v_allowed is not null then return v_allowed; end if;

  return case v_role
    when 'manager' then p_action in ('read','create','update')
      and p_module not in ('payroll','permissions','audit')
    when 'hr' then p_module in ('employees','attendance','leave','payroll')
      and p_action in ('read','create','update')
    when 'accountant' then p_module in ('reports','expenses','payroll','orders')
      and p_action in ('read','create','update','approve')
    when 'employee' then p_module in ('dashboard','attendance','leave')
      and p_action in ('read','create')
    else false
  end;
end;
$function$;

-- Quotas: Basic 50 active products / 1 active employee; Standard unlimited products / 5 employees.
-- Premium and Lifetime are unlimited. Advisory lock serializes concurrent inserts per store.
create or replace function private.storeflow_enforce_plan_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan text;
  v_count bigint;
  v_limit integer;
  v_org uuid;
  v_id uuid;
begin
  v_org := new.organization_id;
  v_id := new.id;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text,0));

  v_plan := private.storeflow_effective_plan(v_org);
  if v_plan='expired' then
    raise exception 'PLAN_EXPIRED: renew your StoreFlow plan before adding records'
      using errcode='P0001';
  end if;
  if v_plan in ('premium','lifetime') then return new; end if;

  if tg_table_name='products' then
    v_limit := case when v_plan='basic' then 50 else null end;
    if v_limit is null then return new; end if;
    if tg_op='UPDATE' then
      select count(*) into v_count from public.products
      where organization_id=v_org and is_active=true and id<>v_id;
    else
      select count(*) into v_count from public.products
      where organization_id=v_org and is_active=true;
    end if;
  elsif tg_table_name='employees' then
    v_limit := case when v_plan='basic' then 1 when v_plan='standard' then 5 else null end;
    if v_limit is null then return new; end if;
    if tg_op='UPDATE' then
      select count(*) into v_count from public.employees
      where organization_id=v_org and is_active=true and id<>v_id;
    else
      select count(*) into v_count from public.employees
      where organization_id=v_org and is_active=true;
    end if;
  else
    raise exception 'Unsupported quota table';
  end if;

  if coalesce(new.is_active,true) and v_count>=v_limit then
    raise exception 'PLAN_QUOTA_EXCEEDED: % limit is % for plan %',
      tg_table_name,v_limit,v_plan using errcode='P0001';
  end if;
  return new;
end;
$$;
revoke all on function private.storeflow_enforce_plan_quota() from public, anon, authenticated;

drop trigger if exists trg_storeflow_products_plan_quota on public.products;
create trigger trg_storeflow_products_plan_quota
before insert or update of organization_id,is_active on public.products
for each row execute function private.storeflow_enforce_plan_quota();

drop trigger if exists trg_storeflow_employees_plan_quota on public.employees;
create trigger trg_storeflow_employees_plan_quota
before insert or update of organization_id,is_active on public.employees
for each row execute function private.storeflow_enforce_plan_quota();

-- Standard unlocks merchant QR settings; Basic cannot enable or upload QR.
create or replace function private.storeflow_guard_merchant_qr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
    coalesce(new.promptpay_enabled,false)
    or coalesce(new.bank_transfer_enabled,false)
    or nullif(new.qr_image_path,'') is not null
    or nullif(new.custom_qr_url,'') is not null
  ) and not private.storeflow_has_feature(new.organization_id,'store_payment_qr') then
    raise exception 'FEATURE_LOCKED: Store payment QR requires Standard or higher'
      using errcode='P0001';
  end if;
  return new;
end;
$$;
revoke all on function private.storeflow_guard_merchant_qr() from public,anon,authenticated;
drop trigger if exists trg_storeflow_guard_merchant_qr on public.store_payment_settings;
create trigger trg_storeflow_guard_merchant_qr
before insert or update on public.store_payment_settings
for each row execute function private.storeflow_guard_merchant_qr();

commit;
