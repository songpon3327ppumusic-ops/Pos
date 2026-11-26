update public.subscription_plans
set monthly_price_thb = case id
      when 'free' then 0 when 'basic' then 149 when 'standard' then 299
      when 'premium' then 599 when 'lifetime' then 2590 else monthly_price_thb end,
    yearly_price_thb = case id
      when 'free' then 0 when 'basic' then 1490 when 'standard' then 2990
      when 'premium' then 5990 when 'lifetime' then 2590 else yearly_price_thb end,
    limits = coalesce(limits,'{}'::jsonb) || case id
      when 'free' then '{"products":30,"employees":0}'::jsonb
      when 'basic' then '{"products":150,"employees":2}'::jsonb
      when 'standard' then '{"products":-1,"employees":6}'::jsonb
      when 'premium' then '{"products":-1,"employees":-1}'::jsonb
      when 'lifetime' then '{"products":-1,"employees":-1}'::jsonb
      else '{}'::jsonb end,
    features = coalesce(features,'{}'::jsonb) || case id
      when 'free' then '{"pos":true,"store_payment_qr":true,"barcode_scanner":true,"reports_basic":true,"documents_receipt":true,"staff":false,"shifts":false,"attendance":false,"tax_documents":false,"payroll":false,"withholding_documents":false,"advanced_documents":false}'::jsonb
      when 'basic' then '{"pos":true,"store_payment_qr":true,"barcode_scanner":true,"reports_basic":true,"advanced_reports":true,"staff":true,"quotes":true,"delivery":true,"shifts":false,"attendance":false,"tax_documents":false,"payroll":false,"withholding_documents":false,"advanced_documents":false}'::jsonb
      when 'standard' then '{"pos":true,"store_payment_qr":true,"barcode_scanner":true,"reports_basic":true,"advanced_reports":true,"staff":true,"quotes":true,"delivery":true,"shifts":true,"attendance":true,"tax_documents":true,"full_tax_invoice":true,"payroll":false,"withholding_documents":false,"advanced_documents":false}'::jsonb
      when 'premium' then '{"pos":true,"store_payment_qr":true,"barcode_scanner":true,"reports_basic":true,"advanced_reports":true,"staff":true,"quotes":true,"delivery":true,"shifts":true,"attendance":true,"tax_documents":true,"full_tax_invoice":true,"payroll":true,"payroll_per_employee":true,"withholding_documents":true,"advanced_documents":true,"all_documents":true}'::jsonb
      when 'lifetime' then '{"pos":true,"store_payment_qr":true,"barcode_scanner":true,"reports_basic":true,"advanced_reports":true,"staff":true,"quotes":true,"delivery":true,"shifts":true,"attendance":true,"tax_documents":true,"full_tax_invoice":true,"payroll":true,"payroll_per_employee":true,"withholding_documents":true,"advanced_documents":true,"all_documents":true,"lifetime_updates":true}'::jsonb
      else '{}'::jsonb end,
    updated_at = now()
where id in ('free','basic','standard','premium','lifetime');

create or replace function private.storeflow_enforce_plan_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_plan text;
  v_count bigint;
  v_limit integer;
  v_org uuid;
  v_id uuid;
begin
  v_org := new.organization_id;
  v_id := new.id;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text, 0));
  v_plan := private.storeflow_effective_plan(v_org);

  if v_plan = 'expired' then
    raise exception 'PLAN_EXPIRED: renew your StoreFlow plan before adding records'
      using errcode = 'P0001';
  end if;
  if v_plan in ('premium','lifetime') then return new; end if;

  if tg_table_name = 'products' then
    v_limit := case
      when v_plan = 'free' then 30
      when v_plan = 'basic' then 150
      when v_plan = 'standard' then null
      else 0 end;
    if v_limit is null then return new; end if;
    if tg_op = 'UPDATE' then
      select count(*) into v_count from public.products
      where organization_id = v_org and is_active = true and id <> v_id;
    else
      select count(*) into v_count from public.products
      where organization_id = v_org and is_active = true;
    end if;
  elsif tg_table_name = 'employees' then
    v_limit := case
      when v_plan = 'free' then 0
      when v_plan = 'basic' then 2
      when v_plan = 'standard' then 6
      else 0 end;
    if tg_op = 'UPDATE' then
      select count(*) into v_count from public.employees
      where organization_id = v_org and is_active = true and id <> v_id;
    else
      select count(*) into v_count from public.employees
      where organization_id = v_org and is_active = true;
    end if;
  else
    raise exception 'Unsupported quota table';
  end if;

  if coalesce(new.is_active, true) and v_count >= v_limit then
    raise exception 'PLAN_QUOTA_EXCEEDED: % limit is % for plan %',
      tg_table_name, v_limit, v_plan using errcode = 'P0001';
  end if;
  return new;
end;
$function$;

revoke all on function private.storeflow_enforce_plan_quota() from public, anon, authenticated;
