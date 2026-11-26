-- Protect full tax invoice and 50-bis rows from direct API updates on Standard.
create or replace function private.storeflow_guard_tax_document_type()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if (
   new.document_type in ('tax_invoice','withholding_certificate')
   or (tg_op='UPDATE' and old.document_type in ('tax_invoice','withholding_certificate'))
 ) and not private.storeflow_has_feature(new.organization_id,'tax_documents') then
   raise exception 'FEATURE_LOCKED: Full tax invoice and withholding certificate require Premium'
     using errcode='P0001';
 end if;
 return new;
end; $$;
drop trigger if exists trg_storeflow_guard_tax_document_type on public.business_documents;
create trigger trg_storeflow_guard_tax_document_type
before insert or update on public.business_documents
for each row execute function private.storeflow_guard_tax_document_type();