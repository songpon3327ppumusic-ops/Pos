create or replace function public.next_business_document_number(p_organization_id uuid,p_document_type text,p_prefix text default null)
returns text language plpgsql security definer set search_path='' as $$
declare v_user uuid:=(select auth.uid());v_month text:=to_char(now() at time zone 'Asia/Bangkok','YYYYMM');v_prefix text;v_seq bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 if not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active' and m.role in ('owner','admin','accountant','hr','manager')) then raise exception using errcode='42501',message='ไม่มีสิทธิ์ออกเอกสาร';end if;
 if p_document_type not in ('invoice','receipt','quotation','delivery','goods_receipt','withholding','payment_voucher','cash_voucher','credit_note','tax_invoice','abbreviated_tax_invoice','delivery_note','receipt_voucher','withholding_certificate') then raise exception using errcode='22023',message='ประเภทเอกสารไม่ถูกต้อง';end if;
 select coalesce(p_prefix,document_prefixes->>p_document_type,case p_document_type when 'tax_invoice' then 'TAX' when 'abbreviated_tax_invoice' then 'TAXS' when 'delivery_note' then 'DN' when 'receipt_voucher' then 'CV' when 'withholding_certificate' then 'WHT' else upper(left(p_document_type,3)) end)
 into v_prefix from public.organization_business_settings where organization_id=p_organization_id;
 v_prefix:=coalesce(v_prefix,case p_document_type when 'tax_invoice' then 'TAX' when 'abbreviated_tax_invoice' then 'TAXS' when 'delivery_note' then 'DN' when 'receipt_voucher' then 'CV' when 'withholding_certificate' then 'WHT' else upper(left(p_document_type,3)) end);
 insert into public.business_document_sequences(organization_id,document_month,document_type,last_number) values(p_organization_id,v_month,p_document_type,1)
 on conflict(organization_id,document_month,document_type) do update set last_number=public.business_document_sequences.last_number+1 returning last_number into v_seq;
 return v_prefix||'-'||v_month||'-'||lpad(v_seq::text,4,'0');
end;$$;
revoke all on function public.next_business_document_number(uuid,text,text) from public,anon;
grant execute on function public.next_business_document_number(uuid,text,text) to authenticated;