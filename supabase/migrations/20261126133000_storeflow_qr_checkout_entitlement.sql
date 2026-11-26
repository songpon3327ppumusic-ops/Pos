-- Restrict PromptPay QR, not ordinary bank transfer, to Standard and above.
create or replace function private.storeflow_guard_merchant_qr()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_qr_changed boolean;
begin
 if tg_op='INSERT' then v_qr_changed:=true;
 else
   v_qr_changed :=
     row(new.promptpay_enabled,new.qr_image_path,new.custom_qr_url)
     is distinct from
     row(old.promptpay_enabled,old.qr_image_path,old.custom_qr_url);
 end if;
 if v_qr_changed and (
   coalesce(new.promptpay_enabled,false)
   or nullif(new.qr_image_path,'') is not null
   or nullif(new.custom_qr_url,'') is not null
 ) and not private.storeflow_has_feature(new.organization_id,'store_payment_qr') then
   raise exception 'FEATURE_LOCKED: Store payment QR requires Standard or higher'
     using errcode='P0001';
 end if;
 return new;
end; $$;
drop trigger if exists trg_storeflow_guard_merchant_qr on public.store_payment_settings;
create trigger trg_storeflow_guard_merchant_qr before insert or update on public.store_payment_settings
for each row execute function private.storeflow_guard_merchant_qr();

do $$
declare v_def text;
begin
  select pg_get_functiondef('public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric)'::regprocedure) into v_def;
  if position('store_payment_qr' in v_def)=0 then
    v_def:=replace(v_def,
      'if not private.has_active_store_license(p_organization_id) then raise exception ''Store subscription expired. Renew the plan to resume POS sales.''; end if;',
      'if not private.has_active_store_license(p_organization_id) then raise exception ''Store subscription expired. Renew the plan to resume POS sales.''; end if;'||E'\n '||
      'if lower(coalesce(p_payment_method,'''')) in (''promptpay'',''qr promptpay'',''qr'') and not private.storeflow_has_feature(p_organization_id,''store_payment_qr'') then raise exception ''FEATURE_LOCKED: Store payment QR requires Standard or higher''; end if;');
    execute v_def;
  end if;
  select pg_get_functiondef('public.create_pos_sale_with_payment(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric,numeric,text,text,text,text)'::regprocedure) into v_def;
  if position('store_payment_qr' in v_def)=0 then
    v_def:=replace(v_def,
      'if not private.has_module_access(p_organization_id,''orders'',''create'') then',
      'if v_method in (''promptpay'',''qr promptpay'',''qr'') and not private.storeflow_has_feature(p_organization_id,''store_payment_qr'') then raise exception using errcode=''42501'',message=''การรับชำระผ่าน QR ต้องใช้แพ็กเกจ Standard ขึ้นไป''; end if;'||E'\n '||
      'if not private.has_module_access(p_organization_id,''orders'',''create'') then');
    execute v_def;
  end if;
end $$;