-- Source-controlled companion for StoreFlow production SQL changes.
-- Shift write access remains tenant-bound and limited to owner/admin/HR.
drop policy if exists shifts_owner_hr_insert on public.shifts;
create policy shifts_owner_hr_insert on public.shifts for insert to authenticated with check (
 exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr'))
 and exists(select 1 from public.employees e where e.id=shifts.employee_id and e.organization_id=shifts.organization_id and e.is_active=true)
);
drop policy if exists shifts_owner_hr_update on public.shifts;
create policy shifts_owner_hr_update on public.shifts for update to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')))
with check(exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')) and exists(select 1 from public.employees e where e.id=shifts.employee_id and e.organization_id=shifts.organization_id and e.is_active=true));
create index if not exists shifts_org_employee_date_idx on public.shifts(organization_id,employee_id,shift_date);
-- Extend document type support and create documents atomically with line items.
alter table public.business_documents drop constraint if exists business_documents_document_type_check;
alter table public.business_documents add constraint business_documents_document_type_check check(document_type in ('quotation','invoice','receipt','tax_invoice','abbreviated_tax_invoice','credit_note','debit_note','purchase_order','goods_receipt','delivery_note','sales_return','purchase_return','stock_transfer','stock_count','receipt_voucher','payment_voucher','petty_cash_voucher','payroll_slip','withholding_certificate'));
create or replace function public.create_storeflow_business_document(
 p_organization_id uuid,p_document_type text,p_party_name text,p_party_tax_id text default null,
 p_party_address text default null,p_issue_date date default current_date,p_due_date date default null,
 p_items jsonb default '[]'::jsonb,p_discount numeric default 0,p_tax_rate numeric default 0,
 p_notes text default null,p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=(select auth.uid());v_no text;v_doc uuid:=gen_random_uuid();v_subtotal numeric(14,2);v_tax numeric(14,2);v_total numeric(14,2);v_item jsonb;v_line numeric(14,2);v_pos integer:=0;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 if not private.is_org_member(p_organization_id) then raise exception using errcode='42501',message='ไม่พบสมาชิกในร้านนี้';end if;
 if not private.has_module_access(p_organization_id,'documents','create') then raise exception using errcode='42501',message='ไม่มีสิทธิ์สร้างเอกสาร';end if;
 if not private.has_active_store_license(p_organization_id) then raise exception using errcode='42501',message='แพ็กเกจหมดอายุ กรุณาต่ออายุ';end if;
 if p_document_type not in ('quotation','invoice','receipt','tax_invoice','abbreviated_tax_invoice','credit_note','delivery_note','goods_receipt','receipt_voucher','payment_voucher','withholding_certificate') then raise exception using errcode='22023',message='ประเภทเอกสารไม่รองรับ';end if;
 if coalesce(trim(p_party_name),'')='' then raise exception using errcode='22023',message='กรุณาระบุชื่อผู้ซื้อ/คู่ค้า';end if;
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception using errcode='22023',message='รูปแบบรายการสินค้าไม่ถูกต้อง';end if;
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 and p_document_type not in ('receipt_voucher','payment_voucher','withholding_certificate') then raise exception using errcode='22023',message='กรุณาเพิ่มรายการอย่างน้อย 1 รายการ';end if;
 if coalesce(p_discount,0)<0 or coalesce(p_tax_rate,0)<0 or coalesce(p_tax_rate,0)>100 then raise exception using errcode='22023',message='ส่วนลดหรืออัตราภาษีไม่ถูกต้อง';end if;
 select coalesce(sum(round((x->>'quantity')::numeric*(x->>'unit_price')::numeric,2)-coalesce((x->>'discount')::numeric,0)),0) into v_subtotal from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x;
 if v_subtotal<0 or p_discount>v_subtotal then raise exception using errcode='22023',message='ยอดส่วนลดเกินยอดรายการ';end if;
 v_subtotal:=round(v_subtotal,2);v_tax:=round((v_subtotal-coalesce(p_discount,0))*coalesce(p_tax_rate,0)/100,2);v_total:=v_subtotal-coalesce(p_discount,0)+v_tax;
 if p_document_type='withholding_certificate' then
  if coalesce(p_metadata->>'income_type','')='' or coalesce((p_metadata->>'withholding_tax')::numeric,0)<0 then raise exception using errcode='22023',message='กรุณาระบุประเภทเงินได้และภาษีหัก ณ ที่จ่าย';end if;
  v_tax:=coalesce((p_metadata->>'withholding_tax')::numeric,0);v_total:=v_subtotal;
 end if;
 v_no:=public.next_business_document_number(p_organization_id,p_document_type,null);
 insert into public.business_documents(id,organization_id,document_type,document_no,status,issue_date,due_date,party_name,party_tax_id,party_address,subtotal,discount,tax_rate,tax_amount,total,notes,metadata,created_by)
 values(v_doc,p_organization_id,p_document_type,v_no,'issued',coalesce(p_issue_date,current_date),p_due_date,trim(p_party_name),nullif(trim(p_party_tax_id),''),nullif(trim(p_party_address),''),v_subtotal,coalesce(p_discount,0),case when p_document_type='withholding_certificate' then 0 else coalesce(p_tax_rate,0) end,v_tax,v_total,p_notes,coalesce(p_metadata,'{}'::jsonb),v_user);
 for v_item in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_pos:=v_pos+1;
  if coalesce((v_item->>'quantity')::numeric,0)<=0 or coalesce((v_item->>'unit_price')::numeric,0)<0 then raise exception using errcode='22023',message='จำนวนหรือราคาต่อหน่วยไม่ถูกต้อง';end if;
  v_line:=round((v_item->>'quantity')::numeric*(v_item->>'unit_price')::numeric-coalesce((v_item->>'discount')::numeric,0),2);
  if v_line<0 then raise exception using errcode='22023',message='ส่วนลดรายการเกินมูลค่า';end if;
  insert into public.business_document_items(organization_id,document_id,description,quantity,unit,unit_price,discount,tax_rate,line_total,sort_order)
  values(p_organization_id,v_doc,coalesce(nullif(trim(v_item->>'description'),''),'รายการ'),(v_item->>'quantity')::numeric,coalesce(nullif(v_item->>'unit',''),'รายการ'),(v_item->>'unit_price')::numeric,coalesce((v_item->>'discount')::numeric,0),coalesce(p_tax_rate,0),v_line,v_pos);
 end loop;
 return v_doc;
end;$$;
revoke all on function public.create_storeflow_business_document(uuid,text,text,text,text,date,date,jsonb,numeric,numeric,text,jsonb) from public,anon;
grant execute on function public.create_storeflow_business_document(uuid,text,text,text,text,date,date,jsonb,numeric,numeric,text,jsonb) to authenticated;