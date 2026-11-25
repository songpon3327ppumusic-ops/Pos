create or replace function public.convert_storeflow_quotation(
  p_organization_id uuid,
  p_source_document_id uuid,
  p_target_type text default 'invoice'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_source public.business_documents%rowtype;
  v_new_id uuid := gen_random_uuid();
  v_no text;
begin
  if v_user is null then raise exception using errcode='28000', message='Authentication required'; end if;
  if not private.is_org_member(p_organization_id) then raise exception using errcode='42501', message='ไม่พบสมาชิกในร้านนี้'; end if;
  if not private.has_module_access(p_organization_id,'documents','create') then raise exception using errcode='42501', message='ไม่มีสิทธิ์สร้างเอกสาร'; end if;
  if not private.has_active_store_license(p_organization_id) then raise exception using errcode='42501', message='แพ็กเกจหมดอายุ'; end if;
  if p_target_type not in ('invoice','billing_note','receipt','tax_invoice') then
    raise exception using errcode='22023', message='ประเภทเอกสารปลายทางไม่รองรับ';
  end if;
  select * into v_source from public.business_documents
   where id=p_source_document_id and organization_id=p_organization_id
   for update;
  if not found or v_source.document_type <> 'quotation' then
    raise exception using errcode='22023', message='ไม่พบใบเสนอราคาที่สามารถแปลงได้';
  end if;
  if v_source.status not in ('issued','approved') then
    raise exception using errcode='22023', message='สถานะใบเสนอราคาไม่สามารถแปลงได้';
  end if;
  v_no := public.next_business_document_number(p_organization_id,p_target_type,null);
  insert into public.business_documents(
    id,organization_id,document_type,document_no,status,related_document_id,customer_id,
    issue_date,due_date,party_name,party_tax_id,party_branch_code,party_address,
    subtotal,discount,tax_rate,tax_amount,total,notes,metadata,created_by,tax_mode,
    withholding_condition,payment_terms_days,valid_until
  ) values (
    v_new_id,p_organization_id,p_target_type,v_no,'issued',v_source.id,v_source.customer_id,
    current_date,v_source.due_date,v_source.party_name,v_source.party_tax_id,
    v_source.party_branch_code,v_source.party_address,v_source.subtotal,v_source.discount,
    v_source.tax_rate,v_source.tax_amount,v_source.total,v_source.notes,v_source.metadata,
    v_user,v_source.tax_mode,v_source.withholding_condition,v_source.payment_terms_days,v_source.valid_until
  );
  insert into public.business_document_items(
    organization_id,document_id,product_id,description,quantity,unit,unit_price,discount,tax_rate,line_total,sort_order
  )
  select organization_id,v_new_id,product_id,description,quantity,unit,unit_price,discount,tax_rate,line_total,sort_order
  from public.business_document_items
  where organization_id=p_organization_id and document_id=v_source.id
  order by sort_order;
  return v_new_id;
end;
$$;
revoke all on function public.convert_storeflow_quotation(uuid,uuid,text) from public;
grant execute on function public.convert_storeflow_quotation(uuid,uuid,text) to authenticated;