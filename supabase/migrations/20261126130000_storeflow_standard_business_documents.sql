-- Standard unlocks ordinary business documents. Full tax invoice and 50-bis stay Premium-only.
do $$
declare v_def text;
begin
  select pg_get_functiondef('private.has_module_access(uuid,text,text)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    'if v_plan<>''expired'' and p_module in (''documents'',''tax_documents'',''business_documents'') and v_plan not in (''premium'',''lifetime'') then return false; end if;',
    'if v_plan<>''expired'' and p_module=''documents'' and v_plan not in (''standard'',''premium'',''lifetime'') then return false; end if;'||E'\n  '||
    'if v_plan<>''expired'' and p_module in (''tax_documents'',''business_documents'') and v_plan not in (''premium'',''lifetime'') then return false; end if;');
  execute v_def;

  select pg_get_functiondef('public.create_storeflow_business_document(uuid,text,text,text,text,date,date,jsonb,numeric,numeric,text,jsonb)'::regprocedure) into v_def;
  if position('tax_documents' in v_def)=0 then
    v_def:=replace(v_def,
      'if not private.has_module_access(p_organization_id,''documents'',''create'') then raise exception using errcode=''42501'',message=''ไม่มีสิทธิ์สร้างเอกสาร''; end if;',
      'if not private.has_module_access(p_organization_id,''documents'',''create'') then raise exception using errcode=''42501'',message=''ไม่มีสิทธิ์สร้างเอกสาร''; end if;'||E'\n  '||
      'if p_document_type in (''tax_invoice'',''withholding_certificate'') and not private.storeflow_has_feature(p_organization_id,''tax_documents'') then raise exception using errcode=''42501'',message=''ใบกำกับภาษีเต็มรูปและ 50 ทวิ ต้องใช้แพ็กเกจ Premium''; end if;');
    execute v_def;
  end if;
end $$;

create or replace function private.storeflow_guard_tax_document_type()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if new.document_type in ('tax_invoice','withholding_certificate')
    and not private.storeflow_has_feature(new.organization_id,'tax_documents') then
   raise exception 'FEATURE_LOCKED: Full tax invoice and withholding certificate require Premium'
     using errcode='P0001';
 end if;
 return new;
end; $$;
revoke all on function private.storeflow_guard_tax_document_type() from public,anon,authenticated;
drop trigger if exists trg_storeflow_guard_tax_document_type on public.business_documents;
create trigger trg_storeflow_guard_tax_document_type
before insert or update of organization_id,document_type on public.business_documents
for each row execute function private.storeflow_guard_tax_document_type();

update public.subscription_plans
set features=features || jsonb_build_object('documents',true,'business_documents',true)
where id='standard';
update public.subscription_plans
set features=features || jsonb_build_object('documents',true,'business_documents',true,'tax_documents',true)
where id in ('premium','lifetime');