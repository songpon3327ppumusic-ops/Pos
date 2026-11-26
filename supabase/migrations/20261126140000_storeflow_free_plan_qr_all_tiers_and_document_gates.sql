begin;

alter table public.organization_subscriptions
  drop constraint if exists organization_subscriptions_plan_tier_check;
alter table public.organization_subscriptions
  add constraint organization_subscriptions_plan_tier_check
  check (plan_tier = any (array['free','basic','standard','premium','lifetime']::text[]));

insert into public.subscription_plans
  (id,name,description,monthly_price_thb,yearly_price_thb,limits,features,is_active,sort_order)
values
  ('free','Free','เริ่มต้นใช้งานฟรีตลอดชีพ',0,0,
   '{"employees":0,"products":20,"branches":1,"storage_mb":100}'::jsonb,
   '{"pos":true,"inventory":true,"reports_basic":true,"staff":false,"shifts":false,"attendance":false,"store_payment_qr":true,"payroll":false,"tax_documents":false,"barcode_scanner":true,"receipt_printer":false,"documents_receipt":true}'::jsonb,
   true,0)
on conflict (id) do update set
  name=excluded.name, description=excluded.description,
  monthly_price_thb=0, yearly_price_thb=0,
  limits=excluded.limits, features=excluded.features,
  is_active=true, sort_order=0, updated_at=now();

update public.subscription_plans
set features = coalesce(features,'{}'::jsonb) ||
    '{"store_payment_qr":true,"barcode_scanner":true}'::jsonb,
    updated_at=now()
where id in ('basic','standard','premium','lifetime');

update public.subscription_plans
set monthly_price_thb=2590, yearly_price_thb=2590,
    description='ซื้อขาดครั้งเดียว ฿2,590 (ราคาปกติ ฿3,990) • ปลดล็อกทุกฟีเจอร์ตลอดชีพ',
    limits='{"employees":-1,"products":-1,"branches":-1,"storage_mb":-1}'::jsonb,
    features=coalesce(features,'{}'::jsonb) ||
      '{"store_payment_qr":true,"barcode_scanner":true,"payroll":true,"tax_documents":true,"withholding_documents":true,"advanced_documents":true}'::jsonb,
    is_active=true, sort_order=4, updated_at=now()
where id='lifetime';

create or replace function private.has_active_store_license(p_org uuid)
returns boolean
language sql stable security definer
set search_path=''
as $function$
  select exists (
    select 1 from public.organization_subscriptions s
    where s.organization_id=p_org and (
      (s.status='free' and s.plan_tier='free')
      or (s.plan_type='lifetime' and s.status='active')
      or (s.status='active' and (s.current_period_end is null or s.current_period_end>now()))
      or (s.status in ('trial','trialing') and s.trial_ends_at>now())
    )
  );
$function$;

create or replace function private.storeflow_effective_plan(p_organization_id uuid)
returns text
language plpgsql stable security definer
set search_path=''
as $function$
declare v_tier text; v_status text; v_plan_type text; v_trial_end timestamptz; v_period_end timestamptz;
begin
  if auth.uid() is not null and exists (
    select 1 from public.platform_admins a where a.user_id=(select auth.uid())
  ) then return 'lifetime'; end if;
  select lower(coalesce(s.plan_tier,s.plan_id,'basic')),
         lower(coalesce(s.status,'expired')),
         lower(coalesce(s.plan_type,'subscription')),
         s.trial_ends_at,s.current_period_end
    into v_tier,v_status,v_plan_type,v_trial_end,v_period_end
  from public.organization_subscriptions s
  where s.organization_id=p_organization_id;
  if not found then return 'expired'; end if;
  if v_plan_type='lifetime' or v_tier='lifetime' then
    return case when v_status='active' then 'lifetime' else 'expired' end;
  end if;
  if v_status='free' and v_tier='free' then return 'free'; end if;
  if v_status in ('trial','trialing') then
    return case when v_trial_end is not null and v_trial_end>now() then 'standard' else 'expired' end;
  end if;
  if v_status<>'active' then return 'expired'; end if;
  if v_period_end is not null and v_period_end<=now() then return 'expired'; end if;
  return case
    when v_tier in ('premium','business') then 'premium'
    when v_tier in ('standard','pro') then 'standard'
    when v_tier='free' then 'free'
    else 'basic'
  end;
end;
$function$;

create or replace function private.storeflow_has_feature(p_organization_id uuid,p_feature text)
returns boolean
language plpgsql stable security definer
set search_path=''
as $function$
declare v_plan text:=private.storeflow_effective_plan(p_organization_id);
begin
  if v_plan in ('premium','lifetime') then return true; end if;
  if v_plan='expired' then return false; end if;
  case p_feature
    when 'overview','pos','products','basic_sales_reports' then return true;
    when 'staff' then return v_plan in ('basic','standard');
    when 'store_payment_qr','barcode_scanner','business_documents' then return true;
    when 'shifts','attendance','tax_documents' then return v_plan in ('standard','premium','lifetime');
    when 'withholding_documents','advanced_documents','payroll_auto','receipt_printer' then return false;
    else return false;
  end case;
end;
$function$;

create or replace function private.storeflow_document_allowed(p_organization_id uuid,p_document_type text)
returns boolean
language plpgsql stable security definer
set search_path=''
as $function$
declare v_plan text:=private.storeflow_effective_plan(p_organization_id);
begin
  if v_plan in ('premium','lifetime') then return true; end if;
  if v_plan='expired' then return false; end if;
  if v_plan='free' then return p_document_type='receipt'; end if;
  if v_plan='basic' then return p_document_type in ('receipt','quotation','delivery_note'); end if;
  if v_plan='standard' then return p_document_type in (
    'receipt','quotation','delivery_note','abbreviated_tax_invoice',
    'tax_invoice','invoice','billing_note','goods_receipt'
  ); end if;
  return false;
end;
$function$;
revoke all on function private.storeflow_document_allowed(uuid,text) from public,anon,authenticated;
grant execute on function private.storeflow_document_allowed(uuid,text) to authenticated;

create or replace function private.has_module_access(p_organization_id uuid,p_module text,p_action text)
returns boolean
language plpgsql stable security definer
set search_path=''
as $function$
declare v_role text; v_allowed boolean; v_plan text;
begin
  if auth.uid() is null then return false; end if;
  select m.role into v_role from public.organization_members m
  where m.organization_id=p_organization_id and m.user_id=(select auth.uid())
    and m.is_active=true and m.membership_status='active' limit 1;
  if v_role is null then return false; end if;
  v_plan:=private.storeflow_effective_plan(p_organization_id);
  if v_plan='expired' and p_action not in ('read','select') then return false; end if;
  if v_plan<>'expired' and p_module in ('attendance','shifts')
     and v_plan not in ('standard','premium','lifetime') then return false; end if;
  if v_plan<>'expired' and p_module='payroll'
     and v_plan not in ('premium','lifetime') then return false; end if;
  if v_plan='free' and p_module in ('employees','staff','workforce')
     and p_action not in ('read','select') then return false; end if;
  if v_plan<>'expired' and p_module in ('documents','business_documents')
     and not private.storeflow_has_feature(p_organization_id,'business_documents') then return false; end if;
  if v_role in ('owner','admin') then return true; end if;
  if v_role='cashier' then
    return case when p_module='pos' then p_action in ('read','create')
      when p_module='orders' then p_action in ('read','create')
      when p_module='inventory' then p_action='read' else false end;
  end if;
  select rp.allowed into v_allowed from public.role_permissions rp
  where rp.organization_id=p_organization_id and rp.role=v_role
    and rp.module=p_module and rp.action=p_action limit 1;
  if v_allowed is not null then return v_allowed; end if;
  return case
    when v_role='manager' then p_action in ('read','create','update')
      and p_module not in ('payroll','permissions','audit')
    when v_role='hr' then p_module in ('employees','attendance','leave','payroll')
      and p_action in ('read','create','update')
    when v_role='accountant' then p_module in ('reports','expenses','payroll','orders')
      and p_action in ('read','create','update','approve')
    when v_role='employee' then p_module in ('dashboard','attendance','leave')
      and p_action in ('read','create')
    else false
  end;
end;
$function$;

create or replace function private.storeflow_enforce_plan_quota()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_plan text; v_count bigint; v_limit integer; v_org uuid; v_id uuid;
begin
  v_org:=new.organization_id; v_id:=new.id;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text,0));
  v_plan:=private.storeflow_effective_plan(v_org);
  if v_plan='expired' then
    raise exception 'PLAN_EXPIRED: renew your StoreFlow plan before adding records' using errcode='P0001';
  end if;
  if v_plan in ('premium','lifetime') then return new; end if;
  if tg_table_name='products' then
    v_limit:=case when v_plan='free' then 20 when v_plan='basic' then 50 else null end;
    if v_limit is null then return new; end if;
    if tg_op='UPDATE' then
      select count(*) into v_count from public.products where organization_id=v_org and is_active=true and id<>v_id;
    else
      select count(*) into v_count from public.products where organization_id=v_org and is_active=true;
    end if;
  elsif tg_table_name='employees' then
    v_limit:=case when v_plan='free' then 0 when v_plan='basic' then 1 when v_plan='standard' then 5 else null end;
    if v_limit is null then return new; end if;
    if tg_op='UPDATE' then
      select count(*) into v_count from public.employees where organization_id=v_org and is_active=true and id<>v_id;
    else
      select count(*) into v_count from public.employees where organization_id=v_org and is_active=true;
    end if;
  else
    raise exception 'Unsupported quota table';
  end if;
  if coalesce(new.is_active,true) and v_count>=v_limit then
    raise exception 'PLAN_QUOTA_EXCEEDED: % limit is % for plan %',tg_table_name,v_limit,v_plan using errcode='P0001';
  end if;
  return new;
end;
$function$;
revoke all on function private.storeflow_enforce_plan_quota() from public,anon,authenticated;

create or replace function private.storeflow_guard_merchant_qr()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if (
    coalesce(new.promptpay_enabled,false)
    or nullif(new.qr_image_path,'') is not null
    or nullif(new.custom_qr_url,'') is not null
  ) and not private.storeflow_has_feature(new.organization_id,'store_payment_qr') then
    raise exception 'FEATURE_LOCKED: Store payment QR is not available on this plan' using errcode='P0001';
  end if;
  return new;
end;
$function$;
revoke all on function private.storeflow_guard_merchant_qr() from public,anon,authenticated;

do $$
declare v_def text; v_old text;
begin
  select pg_get_functiondef('public.create_storeflow_business_document(uuid,text,text,text,text,date,date,jsonb,numeric,numeric,text,jsonb)'::regprocedure) into v_def;
  v_old := 'if p_document_type in (''tax_invoice'',''withholding_certificate'') and not private.storeflow_has_feature(p_organization_id,''tax_documents'') then raise exception using errcode=''42501'',message=''ใบกำกับภาษีเต็มรูปและ 50 ทวิ ต้องใช้แพ็กเกจ Premium''; end if;';
  if position(v_old in v_def)>0 then
    v_def:=replace(v_def,v_old,
      'if not private.storeflow_document_allowed(p_organization_id,p_document_type) then raise exception using errcode=''42501'',message=''เอกสารประเภทนี้ไม่อยู่ในสิทธิ์แพ็กเกจปัจจุบัน''; end if;');
    execute v_def;
  elsif position('storeflow_document_allowed' in v_def)=0 then
    raise exception 'Could not locate document plan guard in create_storeflow_business_document';
  end if;
end $$;

create or replace function public.storeflow_select_free_plan(p_organization_id uuid)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=(select auth.uid());
begin
  if v_user is null then raise exception using errcode='28000',message='Authentication required'; end if;
  if exists(select 1 from public.platform_admins a where a.user_id=v_user) then
    raise exception using errcode='42501',message='บัญชีผู้ดูแลระบบใช้สิทธิ์ Lifetime ไม่สามารถเปลี่ยนเป็น Free ได้';
  end if;
  if not exists(select 1 from public.organization_members m
    where m.organization_id=p_organization_id and m.user_id=v_user
      and m.role='owner' and m.is_active and m.membership_status='active') then
    raise exception using errcode='42501',message='เฉพาะเจ้าของร้านเท่านั้นที่เปลี่ยนแพ็กเกจได้';
  end if;
  if exists(select 1 from public.organization_subscriptions s
    where s.organization_id=p_organization_id and s.status='active'
      and (s.plan_type='lifetime' or s.plan_tier='lifetime')) then
    raise exception using errcode='42501',message='ร้านนี้ใช้สิทธิ์ซื้อขาด Lifetime อยู่แล้ว';
  end if;
  insert into public.organization_subscriptions(
    organization_id,plan_id,plan_tier,plan_type,billing_interval,status,
    current_period_start,current_period_end,trial_started_at,trial_ends_at,
    cancel_at_period_end,canceled_at,metadata,updated_at
  ) values (
    p_organization_id,'free','free','subscription','month','free',
    now(),null,null,null,false,null,jsonb_build_object('selected_by',v_user,'selected_at',now()),now()
  )
  on conflict(organization_id) do update set
    plan_id='free',plan_tier='free',plan_type='subscription',billing_interval='month',status='free',
    current_period_start=now(),current_period_end=null,trial_started_at=null,trial_ends_at=null,
    cancel_at_period_end=false,canceled_at=null,
    metadata=coalesce(public.organization_subscriptions.metadata,'{}'::jsonb)
      || jsonb_build_object('selected_by',v_user,'selected_at',now()),updated_at=now();
  update public.organizations set plan_type='subscription' where id=p_organization_id;
  return 'free';
end;
$function$;
revoke all on function public.storeflow_select_free_plan(uuid) from public,anon;
grant execute on function public.storeflow_select_free_plan(uuid) to authenticated;

commit;
