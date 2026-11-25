-- StoreFlow Business Document Center upgrade
-- Existing organization_id schema is retained as the canonical multi-tenant model.
-- Compatibility views expose store_id aliases without duplicating tenant data.

alter table public.organization_business_settings
  add column if not exists branch_code text not null default '00000',
  add column if not exists branch_name text not null default 'สำนักงานใหญ่',
  add column if not exists signature_path text,
  add column if not exists stamp_path text,
  add column if not exists promptpay_id text,
  add column if not exists bank_name text,
  add column if not exists bank_account_name text,
  add column if not exists bank_account_number text,
  add column if not exists default_tax_mode text not null default 'exclude'
    check (default_tax_mode in ('exclude','include','non_vat'));

alter table public.business_documents
  add column if not exists tax_mode text not null default 'exclude'
    check (tax_mode in ('exclude','include','non_vat')),
  add column if not exists copy_type text not null default 'original'
    check (copy_type in ('original','copy')),
  add column if not exists withholding_condition text,
  add column if not exists payment_terms_days integer,
  add column if not exists valid_until date,
  add column if not exists transport_reference text,
  add column if not exists stock_posted_at timestamptz;

alter table public.business_documents drop constraint if exists business_documents_document_type_check;
alter table public.business_documents add constraint business_documents_document_type_check check (
 document_type = any(array[
 'quotation','invoice','receipt','tax_invoice','abbreviated_tax_invoice','credit_note','debit_note',
 'purchase_order','purchase_requisition','billing_note','goods_receipt','delivery_note','sales_return',
 'purchase_return','stock_transfer','stock_count','receipt_voucher','deposit_receipt','payment_voucher',
 'petty_cash_voucher','expense_certificate','payroll_slip','withholding_certificate'
 ]::text[])
);

create table if not exists public.business_document_attachments(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 document_id uuid not null references public.business_documents(id) on delete cascade,
 storage_path text not null,
 file_name text not null,
 mime_type text,
 file_size bigint check(file_size is null or file_size>=0),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organization_id,storage_path)
);
create index if not exists business_document_attachments_doc_idx
 on public.business_document_attachments(organization_id,document_id,created_at desc);
alter table public.business_document_attachments enable row level security;
drop policy if exists business_document_attachments_member_select on public.business_document_attachments;
create policy business_document_attachments_member_select on public.business_document_attachments
 for select to authenticated using(private.is_org_member(organization_id));
drop policy if exists business_document_attachments_member_insert on public.business_document_attachments;
create policy business_document_attachments_member_insert on public.business_document_attachments
 for insert to authenticated with check(
  private.is_org_member(organization_id)
  and private.has_module_access(organization_id,'documents','create')
  and exists(select 1 from public.business_documents d where d.id=document_id and d.organization_id=business_document_attachments.organization_id)
 );
drop policy if exists business_document_attachments_member_delete on public.business_document_attachments;
create policy business_document_attachments_member_delete on public.business_document_attachments
 for delete to authenticated using(private.is_org_member(organization_id) and private.has_module_access(organization_id,'documents','delete'));
grant select,insert,delete on public.business_document_attachments to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('business-documents','business-documents',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists business_documents_storage_select on storage.objects;
create policy business_documents_storage_select on storage.objects for select to authenticated using(
 bucket_id='business-documents' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and private.is_org_member(((storage.foldername(name))[1])::uuid));
drop policy if exists business_documents_storage_insert on storage.objects;
create policy business_documents_storage_insert on storage.objects for insert to authenticated with check(
 bucket_id='business-documents' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and private.is_org_member(((storage.foldername(name))[1])::uuid));
drop policy if exists business_documents_storage_delete on storage.objects;
create policy business_documents_storage_delete on storage.objects for delete to authenticated using(
 bucket_id='business-documents' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and private.is_org_member(((storage.foldername(name))[1])::uuid));

create or replace function public.next_business_document_number(p_organization_id uuid,p_document_type text,p_prefix text default null)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=(select auth.uid());v_month text:=to_char(now() at time zone 'Asia/Bangkok','YYYYMM');v_prefix text;v_seq bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 if not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active' and m.role in('owner','admin','accountant','hr','manager')) then raise exception using errcode='42501',message='ไม่มีสิทธิ์ออกเอกสาร';end if;
 if p_document_type not in('invoice','receipt','quotation','delivery','goods_receipt','withholding','payment_voucher','cash_voucher','credit_note','debit_note','tax_invoice','abbreviated_tax_invoice','delivery_note','receipt_voucher','withholding_certificate','purchase_order','purchase_requisition','billing_note','deposit_receipt','petty_cash_voucher','expense_certificate') then raise exception using errcode='22023',message='ประเภทเอกสารไม่ถูกต้อง';end if;
 select coalesce(p_prefix,document_prefixes->>p_document_type,case p_document_type
  when 'tax_invoice' then 'TAX' when 'abbreviated_tax_invoice' then 'TAXS' when 'withholding_certificate' then 'WHT'
  when 'delivery_note' then 'DN' when 'goods_receipt' then 'GRN' when 'purchase_order' then 'PO'
  when 'purchase_requisition' then 'PR' when 'billing_note' then 'BN' when 'receipt_voucher' then 'RV'
  when 'deposit_receipt' then 'DEP' when 'payment_voucher' then 'PV' when 'petty_cash_voucher' then 'PC'
  when 'expense_certificate' then 'EC' when 'credit_note' then 'CN' when 'debit_note' then 'DN'
  else upper(left(p_document_type,3)) end) into v_prefix
 from public.organization_business_settings where organization_id=p_organization_id;
 v_prefix:=coalesce(v_prefix,case p_document_type
  when 'tax_invoice' then 'TAX' when 'abbreviated_tax_invoice' then 'TAXS' when 'withholding_certificate' then 'WHT'
  when 'delivery_note' then 'DN' when 'goods_receipt' then 'GRN' when 'purchase_order' then 'PO'
  when 'purchase_requisition' then 'PR' when 'billing_note' then 'BN' when 'receipt_voucher' then 'RV'
  when 'deposit_receipt' then 'DEP' when 'payment_voucher' then 'PV' when 'petty_cash_voucher' then 'PC'
  when 'expense_certificate' then 'EC' when 'credit_note' then 'CN' when 'debit_note' then 'DN'
  else upper(left(p_document_type,3)) end);
 insert into public.business_document_sequences(organization_id,document_month,document_type,last_number)
 values(p_organization_id,v_month,p_document_type,1)
 on conflict(organization_id,document_month,document_type)
 do update set last_number=public.business_document_sequences.last_number+1 returning last_number into v_seq;
 return v_prefix||'-'||v_month||'-'||lpad(v_seq::text,4,'0');
end;$function$;
revoke all on function public.next_business_document_number(uuid,text,text) from public,anon;
grant execute on function public.next_business_document_number(uuid,text,text) to authenticated;

create or replace function public.create_storeflow_business_document(
 p_organization_id uuid,p_document_type text,p_party_name text,p_party_tax_id text default null,
 p_party_address text default null,p_issue_date date default current_date,p_due_date date default null,
 p_items jsonb default '[]'::jsonb,p_discount numeric default 0,p_tax_rate numeric default 0,
 p_notes text default null,p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path=''
as $function$
declare
 v_user uuid:=(select auth.uid());v_no text;v_doc uuid:=gen_random_uuid();
 v_subtotal numeric(14,2);v_tax numeric(14,2);v_total numeric(14,2);
 v_item jsonb;v_line numeric(14,2);v_pos integer:=0;v_wh jsonb;v_tax_mode text;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 if not private.is_org_member(p_organization_id) then raise exception using errcode='42501',message='ไม่พบสมาชิกในร้านนี้';end if;
 if not private.has_module_access(p_organization_id,'documents','create') then raise exception using errcode='42501',message='ไม่มีสิทธิ์สร้างเอกสาร';end if;
 if not private.has_active_store_license(p_organization_id) then raise exception using errcode='42501',message='แพ็กเกจหมดอายุ กรุณาต่ออายุ';end if;
 if p_document_type not in('quotation','invoice','receipt','tax_invoice','abbreviated_tax_invoice','credit_note','debit_note','purchase_order','purchase_requisition','billing_note','goods_receipt','delivery_note','receipt_voucher','deposit_receipt','payment_voucher','petty_cash_voucher','expense_certificate','withholding_certificate') then raise exception using errcode='22023',message='ประเภทเอกสารไม่รองรับ';end if;
 if coalesce(trim(p_party_name),'')='' then raise exception using errcode='22023',message='กรุณาระบุชื่อผู้ซื้อ/คู่ค้า';end if;
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception using errcode='22023',message='รูปแบบรายการสินค้าไม่ถูกต้อง';end if;
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 and p_document_type not in('receipt_voucher','payment_voucher','petty_cash_voucher','deposit_receipt','expense_certificate','withholding_certificate','purchase_requisition') then raise exception using errcode='22023',message='กรุณาเพิ่มรายการอย่างน้อย 1 รายการ';end if;
 if coalesce(p_discount,0)<0 or coalesce(p_tax_rate,0)<0 or coalesce(p_tax_rate,0)>100 then raise exception using errcode='22023',message='ส่วนลดหรืออัตราภาษีไม่ถูกต้อง';end if;
 select coalesce(sum(round((x->>'quantity')::numeric*(x->>'unit_price')::numeric,2)-coalesce((x->>'discount')::numeric,0)),0) into v_subtotal from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x;
 if v_subtotal<0 or p_discount>v_subtotal then raise exception using errcode='22023',message='ยอดส่วนลดเกินยอดรายการ';end if;
 v_subtotal:=round(v_subtotal,2);v_tax_mode:=coalesce(p_metadata->>'tax_mode','exclude');
 if v_tax_mode not in('exclude','include','non_vat') then raise exception using errcode='22023',message='รูปแบบ VAT ไม่ถูกต้อง';end if;
 if v_tax_mode='include' then v_tax:=round((v_subtotal-coalesce(p_discount,0))*coalesce(p_tax_rate,0)/(100+coalesce(p_tax_rate,0)),2);v_total:=v_subtotal-coalesce(p_discount,0);
 elsif v_tax_mode='non_vat' then v_tax:=0;v_total:=v_subtotal-coalesce(p_discount,0);
 else v_tax:=round((v_subtotal-coalesce(p_discount,0))*coalesce(p_tax_rate,0)/100,2);v_total:=v_subtotal-coalesce(p_discount,0)+v_tax;end if;
 if p_document_type='withholding_certificate' then
  v_wh:=coalesce(p_metadata->'withholding',p_metadata);
  if coalesce(v_wh->>'income_type','')='' or coalesce((v_wh->>'withholding_tax')::numeric,0)<0 then raise exception using errcode='22023',message='กรุณาระบุประเภทเงินได้และภาษีหัก ณ ที่จ่าย';end if;
  v_tax:=coalesce((v_wh->>'withholding_tax')::numeric,0);if v_tax>v_subtotal then raise exception using errcode='22023',message='ภาษีหัก ณ ที่จ่ายเกินยอดเงินได้';end if;v_total:=v_subtotal-v_tax;
 end if;
 v_no:=public.next_business_document_number(p_organization_id,p_document_type,null);
 insert into public.business_documents(id,organization_id,document_type,document_no,status,issue_date,due_date,party_name,party_tax_id,party_address,subtotal,discount,tax_rate,tax_amount,total,notes,metadata,created_by,tax_mode,withholding_condition,payment_terms_days,valid_until,transport_reference)
 values(v_doc,p_organization_id,p_document_type,v_no,'issued',coalesce(p_issue_date,current_date),p_due_date,trim(p_party_name),nullif(trim(p_party_tax_id),''),nullif(trim(p_party_address),''),v_subtotal,coalesce(p_discount,0),case when p_document_type='withholding_certificate' then 0 else coalesce(p_tax_rate,0) end,v_tax,v_total,p_notes,coalesce(p_metadata,'{}'::jsonb),v_user,v_tax_mode,nullif(p_metadata->>'withholding_condition',''),nullif(p_metadata->>'payment_terms_days','')::integer,nullif(p_metadata->>'valid_until','')::date,nullif(p_metadata->>'transport_reference',''));
 for v_item in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_pos:=v_pos+1;
  if coalesce((v_item->>'quantity')::numeric,0)<=0 or coalesce((v_item->>'unit_price')::numeric,0)<0 then raise exception using errcode='22023',message='จำนวนหรือราคาต่อหน่วยไม่ถูกต้อง';end if;
  v_line:=round((v_item->>'quantity')::numeric*(v_item->>'unit_price')::numeric-coalesce((v_item->>'discount')::numeric,0),2);
  if v_line<0 then raise exception using errcode='22023',message='ส่วนลดรายการเกินมูลค่า';end if;
  insert into public.business_document_items(organization_id,document_id,product_id,description,quantity,unit,unit_price,discount,tax_rate,line_total,sort_order)
  values(p_organization_id,v_doc,nullif(v_item->>'product_id','')::uuid,coalesce(nullif(trim(v_item->>'description'),''),'รายการ'),(v_item->>'quantity')::numeric,coalesce(nullif(v_item->>'unit',''),'รายการ'),(v_item->>'unit_price')::numeric,coalesce((v_item->>'discount')::numeric,0),case when v_tax_mode='non_vat' then 0 else coalesce(p_tax_rate,0) end,v_line,v_pos);
 end loop;
 return v_doc;
end;$function$;
revoke all on function public.create_storeflow_business_document(uuid,text,text,text,text,date,date,jsonb,numeric,numeric,text,jsonb) from public,anon;
grant execute on function public.create_storeflow_business_document(uuid,text,text,text,text,date,date,jsonb,numeric,numeric,text,jsonb) to authenticated;

create or replace function public.confirm_storeflow_goods_receipt(p_document_id uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=(select auth.uid());v_doc public.business_documents%rowtype;v_item public.business_document_items%rowtype;v_product public.products%rowtype;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 select * into v_doc from public.business_documents where id=p_document_id for update;
 if not found or not private.is_org_member(v_doc.organization_id) then raise exception using errcode='42501',message='ไม่พบเอกสารในร้านนี้';end if;
 if v_doc.document_type<>'goods_receipt' then raise exception 'เอกสารนี้ไม่ใช่ใบรับสินค้า';end if;
 if v_doc.status not in('issued','partially_paid') then raise exception 'สถานะเอกสารไม่อนุญาตให้รับสินค้า';end if;
 if v_doc.stock_posted_at is not null then raise exception 'เอกสารนี้อัปเดตสต็อกแล้ว';end if;
 if not private.has_module_access(v_doc.organization_id,'documents','update') or not private.has_active_store_license(v_doc.organization_id) then raise exception using errcode='42501',message='ไม่มีสิทธิ์หรือแพ็กเกจหมดอายุ';end if;
 for v_item in select * from public.business_document_items where document_id=p_document_id and organization_id=v_doc.organization_id order by sort_order for update loop
  if v_item.product_id is null then raise exception 'รายการ % ยังไม่ได้เชื่อมกับสินค้าในคลัง',v_item.description;end if;
  select * into v_product from public.products where id=v_item.product_id and organization_id=v_doc.organization_id for update;
  if not found then raise exception 'ไม่พบสินค้า % ในร้านนี้',v_item.description;end if;
  update public.products set stock=stock+v_item.quantity,updated_at=now() where id=v_item.product_id and organization_id=v_doc.organization_id;
  insert into public.stock_movements(organization_id,product_id,movement_type,quantity_delta,note,created_by) values(v_doc.organization_id,v_item.product_id,'adjustment',v_item.quantity,'รับสินค้าเข้าคลังจากเอกสาร '||v_doc.document_no,v_user);
  insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details) values(v_doc.organization_id,v_user,'goods_receipt_stock_posted','business_document',p_document_id::text,jsonb_build_object('document_no',v_doc.document_no,'product_id',v_item.product_id,'quantity',v_item.quantity));
 end loop;
 update public.business_documents set stock_posted_at=now(),metadata=metadata||jsonb_build_object('stock_posted',true),updated_at=now() where id=p_document_id;
end;$function$;
revoke all on function public.confirm_storeflow_goods_receipt(uuid) from public,anon;
grant execute on function public.confirm_storeflow_goods_receipt(uuid) to authenticated;

create or replace function public.get_store_invite_code()
returns text language plpgsql volatile security definer set search_path=''
as $function$
declare v_org uuid;v_code text;
begin
 if (select auth.uid()) is null then raise exception using errcode='28000',message='Authentication required';end if;
 select m.organization_id into v_org from public.organization_members m
 where m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'
 order by m.created_at limit 1;
 if v_org is null then raise exception using errcode='42501',message='Only active store owners can view invite code';end if;
 insert into private.organization_invites(organization_id,invite_code,is_active)
 values(v_org,upper(substr(encode(gen_random_bytes(8),'hex'),1,16)),true)
 on conflict(organization_id) do update set is_active=true returning invite_code into v_code;
 return v_code;
end;$function$;
revoke all on function public.get_store_invite_code() from public,anon;
grant execute on function public.get_store_invite_code() to authenticated;

create or replace view public.document_settings with (security_invoker=true) as
select organization_id as store_id,legal_name,display_name,address,tax_id,phone,email,logo_path,vat_registered,vat_rate,document_prefixes,branch_code,branch_name,signature_path,stamp_path,promptpay_id,bank_name,bank_account_name,bank_account_number,default_tax_mode,created_at,updated_at
from public.organization_business_settings;
create or replace view public.documents with (security_invoker=true) as
select id,organization_id as store_id,document_type,document_no,status,related_document_id,customer_id,supplier_id,source_sale_id,issue_date,due_date,party_name,party_tax_id,party_branch_code,party_address,subtotal,discount,tax_rate,tax_amount,total,notes,metadata,issued_at,created_by,created_at,updated_at,tax_mode,copy_type,withholding_condition,payment_terms_days,valid_until,transport_reference,stock_posted_at
from public.business_documents;
create or replace view public.document_items with (security_invoker=true) as
select id,organization_id as store_id,document_id,product_id,description,quantity,unit,unit_price,discount,tax_rate,line_total,sort_order,created_at
from public.business_document_items;
grant select,insert,update,delete on public.document_settings,public.documents,public.document_items to authenticated;
