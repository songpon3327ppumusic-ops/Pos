-- Allow Basic stores to edit unrelated payment settings after plan downgrade.
-- Enforce the QR entitlement only when QR-related columns are changed.
create or replace function private.storeflow_guard_merchant_qr()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_qr_changed boolean;
begin
 if tg_op='INSERT' then
   v_qr_changed:=true;
 else
   v_qr_changed :=
     row(new.promptpay_enabled,new.bank_transfer_enabled,new.qr_image_path,new.custom_qr_url)
     is distinct from
     row(old.promptpay_enabled,old.bank_transfer_enabled,old.qr_image_path,old.custom_qr_url);
 end if;
 if v_qr_changed and (
   coalesce(new.promptpay_enabled,false)
   or coalesce(new.bank_transfer_enabled,false)
   or nullif(new.qr_image_path,'') is not null
   or nullif(new.custom_qr_url,'') is not null
 ) and not private.storeflow_has_feature(new.organization_id,'store_payment_qr') then
   raise exception 'FEATURE_LOCKED: Store payment QR requires Standard or higher'
     using errcode='P0001';
 end if;
 return new;
end; $$;
revoke all on function private.storeflow_guard_merchant_qr() from public,anon,authenticated;