begin;

create or replace function private.storeflow_document_allowed(p_organization_id uuid,p_document_type text)
returns boolean language plpgsql stable security definer set search_path=''
as $function$
declare v_plan text:=private.storeflow_effective_plan(p_organization_id);
begin
  if v_plan in ('premium','lifetime') then return true; end if;
  if v_plan='expired' then return false; end if;
  if v_plan='free' then return p_document_type='receipt'; end if;
  if v_plan='basic' then return p_document_type in ('receipt','quotation','delivery_note'); end if;
  if v_plan='standard' then return p_document_type in (
    'receipt','quotation','delivery_note','abbreviated_tax_invoice','tax_invoice','invoice','billing_note'
  ); end if;
  return false;
end;
$function$;
revoke all on function private.storeflow_document_allowed(uuid,text) from public,anon,authenticated;
grant execute on function private.storeflow_document_allowed(uuid,text) to authenticated;

update public.subscription_plans
set limits = case id
  when 'free' then '{"employees":0,"products":20,"branches":1,"storage_mb":100}'::jsonb
  when 'basic' then '{"employees":1,"products":50,"branches":1,"storage_mb":250}'::jsonb
  when 'standard' then '{"employees":5,"products":-1,"branches":1,"storage_mb":2048}'::jsonb
  else '{"employees":-1,"products":-1,"branches":-1,"storage_mb":-1}'::jsonb
end,
features = coalesce(features,'{}'::jsonb) || jsonb_build_object(
  'pos',true,'inventory',true,'reports_basic',true,'store_payment_qr',true,'barcode_scanner',true,
  'staff',id in ('basic','standard','premium','lifetime'),
  'shifts',id in ('standard','premium','lifetime'),
  'attendance',id in ('standard','premium','lifetime'),
  'tax_documents',id in ('standard','premium','lifetime'),
  'payroll',id in ('premium','lifetime'),
  'withholding_documents',id in ('premium','lifetime'),
  'advanced_documents',id in ('premium','lifetime'),
  'receipt_printer',id in ('premium','lifetime')
),updated_at=now()
where id in ('free','basic','standard','premium','lifetime');

do $$
declare v_def text; v_old text;
begin
  select pg_get_functiondef('public.get_store_invite_code()'::regprocedure) into v_def;
  v_old := 'if v_org is null then raise exception using errcode=''42501'',message=''Only active store owners can view invite code''; end if;';
  if position(v_old in v_def)>0 then
    v_def:=replace(v_def,v_old,v_old||E'\n  if not private.storeflow_has_feature(v_org,''staff'') then raise exception using errcode=''42501'',message=''แพ็กเกจ Free ไม่สามารถเพิ่มพนักงานหรือสร้างรหัสเชิญได้''; end if;');
    execute v_def;
  elsif position('storeflow_has_feature(v_org' in v_def)=0 then
    raise exception 'Could not locate get_store_invite_code owner guard';
  end if;

  select pg_get_functiondef('public.storeflow_join_by_invite(text)'::regprocedure) into v_def;
  v_old := 'if v_org is null then' || E'\n    raise exception using errcode=''P0002'',message=''รหัสเชิญไม่ถูกต้องหรือหมดอายุ'';' || E'\n  end if;';
  if position(v_old in v_def)>0 then
    v_def:=replace(v_def,v_old,v_old||E'\n  if not private.storeflow_has_feature(v_org,''staff'') then raise exception using errcode=''42501'',message=''ร้านค้าแพ็กเกจ Free ไม่สามารถรับสมาชิกเพิ่มได้''; end if;');
    execute v_def;
  elsif position('storeflow_has_feature(v_org' in v_def)=0 then
    raise exception 'Could not locate storeflow_join_by_invite invite validation';
  end if;
end $$;

commit;
