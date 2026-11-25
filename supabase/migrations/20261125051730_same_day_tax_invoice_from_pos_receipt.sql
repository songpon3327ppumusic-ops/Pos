-- Enforce same-day POS receipt -> full tax invoice issuance at database level.
create unique index if not exists business_documents_one_tax_invoice_per_sale_idx
on public.business_documents(organization_id,source_sale_id)
where document_type='tax_invoice' and source_sale_id is not null;

create or replace function public.enforce_same_day_tax_invoice_from_pos()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
 v_sale_created_at timestamptz;
 v_sale_org uuid;
 v_sale_date date;
 v_today_bkk date;
begin
 if new.document_type <> 'tax_invoice' or new.source_sale_id is null then
   return new;
 end if;

 select s.created_at,s.organization_id
 into v_sale_created_at,v_sale_org
 from public.sales s
 where s.id=new.source_sale_id;

 if not found or v_sale_org is distinct from new.organization_id then
   raise exception using errcode='23503',message='ไม่พบใบเสร็จ POS ในร้านนี้';
 end if;

 v_sale_date := (v_sale_created_at at time zone 'Asia/Bangkok')::date;
 v_today_bkk := (now() at time zone 'Asia/Bangkok')::date;

 if v_sale_date <> v_today_bkk or new.issue_date <> v_sale_date then
   raise exception using errcode='23514',message='ใบกำกับภาษีจากใบเสร็จ POS ต้องออกภายในวันเดียวกับวันที่ขายเท่านั้น';
 end if;

 return new;
end;
$function$;

drop trigger if exists business_documents_same_day_tax_invoice on public.business_documents;
create trigger business_documents_same_day_tax_invoice
before insert or update of document_type,source_sale_id,issue_date,organization_id
on public.business_documents
for each row
execute function public.enforce_same_day_tax_invoice_from_pos();

comment on function public.enforce_same_day_tax_invoice_from_pos() is
'Enforces same-day issuance and one full tax invoice per POS receipt for StoreFlow.';
