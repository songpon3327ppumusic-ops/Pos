-- StoreFlow security audit hardening (2026-11-25)
-- Re-runnable migration: database changes were applied and verified on the linked project.

begin;

-- Keep the POS payment states used by the checkout and webhook flows.
alter table public.sales drop constraint if exists sales_status_check;
alter table public.sales add constraint sales_status_check
 check (status = any (array[
  'pending'::text,'pending_payment'::text,'payment_failed'::text,
  'completed'::text,'refunded'::text,'cancelled'::text
 ]));

-- Prevent idempotency-key replay from changing an existing sale's payment method.
create or replace function public.create_pos_sale_with_payment(
 p_organization_id uuid,p_items jsonb,p_payment_method text,p_discount numeric,p_tax numeric,
 p_customer_id uuid,p_idempotency_key uuid,p_cash_received numeric,p_amount_tendered numeric,
 p_payment_ref text,p_slip_path text,p_card_approval_code text,p_card_last4 text
) returns uuid
language plpgsql security definer set search_path to ''
as $function$
declare
 v_user uuid:=(select auth.uid());
 v_role text;
 v_sale uuid;
 v_existing uuid;
 v_existing_creator uuid;
 v_existing_method text;
 v_expected_method text;
 v_total numeric(12,2);
 v_method text:=lower(trim(coalesce(p_payment_method,'')));
 v_enabled boolean:=false;
 v_status text:='paid';
 v_sale_status text:='completed';
 v_tendered numeric(12,2):=0;
 v_settings public.store_payment_settings%rowtype;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 if p_idempotency_key is null then raise exception using errcode='22023',message='Idempotency key is required';end if;
 select m.role into v_role from public.organization_members m
 where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active';
 if v_role is null or v_role not in ('owner','admin','manager','cashier') then
  raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระเงิน';
 end if;
 if not private.has_module_access(p_organization_id,'orders','create') then
  raise exception using errcode='42501',message='ไม่มีสิทธิ์สร้างรายการขาย';
 end if;
 select * into v_settings from public.store_payment_settings where organization_id=p_organization_id;
 if v_method in ('cash','เงินสด') then
  v_method:='cash';v_enabled:=coalesce(v_settings.cash_enabled,true);v_tendered:=coalesce(p_cash_received,0);
 elsif v_method in ('promptpay','qr promptpay','qr') then
  v_method:='promptpay';v_enabled:=coalesce(v_settings.promptpay_enabled,false);v_status:='pending';v_sale_status:='pending_payment';
 elsif v_method in ('bank_transfer','โอนเงิน') then
  v_method:='bank_transfer';v_enabled:=coalesce(v_settings.bank_transfer_enabled,false);v_status:='pending';v_sale_status:='pending_payment';
 elsif v_method in ('card_edc','บัตรเครดิต/เดบิต','บัตรเครดิต/เดบิต (edc)') then
  v_method:='card_edc';v_enabled:=coalesce(v_settings.card_edc_enabled,false);
  if nullif(trim(coalesce(p_card_approval_code,'')),'') is null then raise exception using errcode='22023',message='กรุณากรอกรหัสอนุมัติจากเครื่อง EDC';end if;
  if p_card_last4 is not null and p_card_last4 !~ '^[0-9]{4}$' then raise exception using errcode='22023',message='เลขท้ายบัตรต้องมี 4 หลัก';end if;
  v_tendered:=coalesce(p_amount_tendered,0);
 elsif v_method in ('credit','customer_credit','เงินเชื่อ') then
  v_method:='customer_credit';v_enabled:=coalesce(v_settings.credit_enabled,false);v_status:='unpaid';v_tendered:=0;
  if p_customer_id is null then raise exception using errcode='22023',message='กรุณาเลือกลูกค้าก่อนบันทึกเงินเชื่อ';end if;
 elsif v_method in ('stripe','stripe_card') then
  v_method:='stripe_card';v_enabled:=coalesce(v_settings.stripe_enabled,false) and coalesce(v_settings.stripe_charges_enabled,false) and coalesce(v_settings.stripe_webhook_verified,false);v_status:='pending';v_sale_status:='pending_payment';
 else
  raise exception using errcode='22023',message='ไม่รองรับช่องทางชำระเงินนี้';
 end if;
 if not v_enabled then raise exception using errcode='55000',message='ร้านยังไม่ได้เปิดใช้งานช่องทางชำระเงินนี้';end if;
 if v_method='cash' and v_tendered<0 then raise exception using errcode='22023',message='จำนวนเงินรับไม่ถูกต้อง';end if;
 if v_method='card_edc' and coalesce(p_amount_tendered,0)<=0 then raise exception using errcode='22023',message='ยอดชำระผ่าน EDC ไม่ถูกต้อง';end if;
 if p_slip_path is not null and (split_part(p_slip_path,'/',1)<>p_organization_id::text or split_part(p_slip_path,'/',2)<>'slips') then
  raise exception using errcode='22023',message='ตำแหน่งไฟล์สลิปไม่ถูกต้อง';
 end if;

 v_expected_method:=case
  when v_method='cash' then 'เงินสด'
  when v_method='promptpay' then 'QR PromptPay'
  when v_method='bank_transfer' then 'โอนเงิน'
  when v_method='card_edc' then 'บัตรเครดิต/เดบิต (EDC)'
  when v_method='stripe_card' then 'Stripe Online'
  else 'เงินเชื่อ' end;

 perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':'||p_idempotency_key::text,0));
 select sale_id,created_by into v_existing,v_existing_creator
 from private.pos_order_idempotency
 where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
 if v_existing is not null then
  if v_existing_creator is distinct from v_user then
   raise exception using errcode='42501',message='Idempotency key belongs to another cashier';
  end if;
  select payment_method into v_existing_method from public.sales
  where id=v_existing and organization_id=p_organization_id;
  if v_existing_method is distinct from v_expected_method then
   raise exception using errcode='22023',message='Idempotency key was already used for a different payment method';
  end if;
  return v_existing;
 end if;

 v_sale:=public.checkout_sale_idempotent(p_organization_id,p_items,
  case when v_method='cash' then 'เงินสด' when v_method='promptpay' then 'QR PromptPay'
       when v_method='bank_transfer' then 'โอนเงิน' when v_method='card_edc' then 'บัตรเครดิต/เดบิต'
       when v_method='stripe_card' then 'Stripe Online' else 'เงินเชื่อ' end,
  p_discount,p_tax,p_customer_id,p_idempotency_key,
  case when v_method='cash' then p_cash_received else null end);
 select total into v_total from public.sales where id=v_sale and organization_id=p_organization_id;
 if v_method='cash' and v_tendered<v_total then raise exception using errcode='22023',message='เงินสดที่รับน้อยกว่ายอดชำระ';end if;
 if v_method='card_edc' and round(coalesce(p_amount_tendered,0),2)<>round(v_total,2) then
  raise exception using errcode='22023',message='ยอดเครื่อง EDC ต้องตรงกับยอดบิล';
 end if;
 update public.sales set
  payment_method=v_expected_method,payment_status=v_status,status=v_sale_status,
  amount_tendered=case when v_method='cash' then v_tendered when v_method='card_edc' then v_total else 0 end,
  change_amount=case when v_method='cash' then round(v_tendered-v_total,2) else 0 end,
  cash_received=case when v_method='cash' then v_tendered else null end,
  change_due=case when v_method='cash' then round(v_tendered-v_total,2) else 0 end,
  payment_ref=nullif(trim(coalesce(p_payment_ref,'')),''),
  slip_path=p_slip_path,
  card_approval_code=nullif(trim(coalesce(p_card_approval_code,'')),''),
  card_last4=nullif(trim(coalesce(p_card_last4,'')),''),
  paid_at=case when v_status='paid' then now() else null end
 where id=v_sale and organization_id=p_organization_id;
 if v_method='customer_credit' then
  insert into public.customer_credit_ledger(organization_id,customer_id,sale_id,entry_type,amount,notes,created_by)
  values(p_organization_id,p_customer_id,v_sale,'charge',v_total,
   'ยอดขายเชื่อ '||(select receipt_no from public.sales where id=v_sale),v_user)
  on conflict do nothing;
  if found then
   update public.customers set credit_balance=coalesce(credit_balance,0)+v_total
   where id=p_customer_id and organization_id=p_organization_id;
  end if;
 end if;
 return v_sale;
end;
$function$;

-- Audit logs are append-only to authenticated clients; trusted database functions
-- (owned by the database owner) continue to record events.
drop policy if exists audit_logs_access_insert on public.audit_logs;
drop policy if exists audit_logs_access_update on public.audit_logs;
drop policy if exists audit_logs_access_delete on public.audit_logs;
revoke insert,update,delete on table public.audit_logs from authenticated;

-- Permission definitions cannot be changed by a delegated manager permission.
drop policy if exists role_permissions_owner_insert_guard on public.role_permissions;
drop policy if exists role_permissions_owner_update_guard on public.role_permissions;
drop policy if exists role_permissions_owner_delete_guard on public.role_permissions;

create policy role_permissions_owner_insert_guard on public.role_permissions as restrictive
for insert to authenticated with check (
 exists(select 1 from public.organization_members m
  where m.organization_id=role_permissions.organization_id and m.user_id=(select auth.uid())
   and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin'))
);

create policy role_permissions_owner_update_guard on public.role_permissions as restrictive
for update to authenticated using (
 exists(select 1 from public.organization_members m
  where m.organization_id=role_permissions.organization_id and m.user_id=(select auth.uid())
   and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin'))
) with check (
 exists(select 1 from public.organization_members m
  where m.organization_id=role_permissions.organization_id and m.user_id=(select auth.uid())
   and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin'))
);

create policy role_permissions_owner_delete_guard on public.role_permissions as restrictive
for delete to authenticated using (
 exists(select 1 from public.organization_members m
  where m.organization_id=role_permissions.organization_id and m.user_id=(select auth.uid())
   and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin'))
);

-- Number allocation is only invoked from the atomic document-creation RPC.
revoke execute on function public.next_business_document_number(uuid,text,text) from authenticated,anon,public;

-- Only the trusted payment integration may update provider-verified connection state.
create or replace function private.guard_store_payment_gateway_state()
returns trigger language plpgsql set search_path to ''
as $function$
declare v_jwt_role text:=coalesce(auth.jwt()->>'role','');
begin
 if v_jwt_role <> 'service_role' then
  if tg_op='INSERT' then
   if new.stripe_connect_account_id is not null
      or coalesce(new.stripe_charges_enabled,false)
      or coalesce(new.stripe_payouts_enabled,false)
      or coalesce(new.stripe_webhook_verified,false)
      or coalesce(new.omise_connected,false) then
    raise exception using errcode='42501',message='Gateway verification state can only be changed by the trusted payment service';
   end if;
  elsif new.stripe_connect_account_id is distinct from old.stripe_connect_account_id
     or new.stripe_charges_enabled is distinct from old.stripe_charges_enabled
     or new.stripe_payouts_enabled is distinct from old.stripe_payouts_enabled
     or new.stripe_webhook_verified is distinct from old.stripe_webhook_verified
     or new.omise_connected is distinct from old.omise_connected then
   raise exception using errcode='42501',message='Gateway verification state can only be changed by the trusted payment service';
  end if;
 end if;
 return new;
end;
$function$;
revoke all on function private.guard_store_payment_gateway_state() from public,anon,authenticated;
drop trigger if exists guard_store_payment_gateway_state on public.store_payment_settings;
create trigger guard_store_payment_gateway_state before insert or update
on public.store_payment_settings for each row
execute function private.guard_store_payment_gateway_state();

-- Require both active flag and active membership status in tenant checks.
create or replace function private.is_org_member(p_organization_id uuid)
returns boolean language sql stable security definer set search_path to ''
as $function$
 select exists (
  select 1 from public.organization_members m
  where m.organization_id=p_organization_id
   and m.user_id=(select auth.uid())
   and m.is_active=true and m.membership_status='active'
 );
$function$;

-- Business document attachments and private settings assets follow document
-- module/owner permissions instead of granting every store member access.
drop policy if exists business_document_attachments_member_select on public.business_document_attachments;
create policy business_document_attachments_member_select
on public.business_document_attachments
for select to authenticated
using (private.is_org_member(organization_id)
 and private.has_module_access(organization_id,'documents','read'));

drop policy if exists business_documents_storage_select on storage.objects;
create policy business_documents_storage_select
on storage.objects
for select to authenticated
using (
 bucket_id='business-documents'
 and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and (
  (
   (storage.foldername(name))[2]='settings'
   and exists (
    select 1 from public.organization_members m
    where m.organization_id=((storage.foldername(name))[1])::uuid
     and m.user_id=(select auth.uid())
     and m.is_active=true and m.membership_status='active'
     and m.role in ('owner','admin')
   )
  )
  or
  (
   (storage.foldername(name))[2]='documents'
   and private.has_module_access(((storage.foldername(name))[1])::uuid,'documents','read')
  )
 )
);

-- Tighten active-status checks on organization settings and organization lookup.
drop policy if exists business_settings_owner_write on public.organization_business_settings;
create policy business_settings_owner_write on public.organization_business_settings
for all to authenticated
using (exists(select 1 from public.organization_members m
 where m.organization_id=organization_business_settings.organization_id
 and m.user_id=(select auth.uid()) and m.is_active=true
 and m.membership_status='active' and m.role in ('owner','admin')))
with check (exists(select 1 from public.organization_members m
 where m.organization_id=organization_business_settings.organization_id
 and m.user_id=(select auth.uid()) and m.is_active=true
 and m.membership_status='active' and m.role in ('owner','admin')));

drop policy if exists hardware_settings_owner_write on public.organization_hardware_settings;
create policy hardware_settings_owner_write on public.organization_hardware_settings
for all to authenticated
using (exists(select 1 from public.organization_members m
 where m.organization_id=organization_hardware_settings.organization_id
 and m.user_id=(select auth.uid()) and m.is_active=true
 and m.membership_status='active' and m.role in ('owner','admin')))
with check (exists(select 1 from public.organization_members m
 where m.organization_id=organization_hardware_settings.organization_id
 and m.user_id=(select auth.uid()) and m.is_active=true
 and m.membership_status='active' and m.role in ('owner','admin')));

drop policy if exists "organization members read org" on public.organizations;
create policy "organization members read org" on public.organizations
for select to authenticated
using (exists(select 1 from public.organization_members m
 where m.organization_id=organizations.id and m.user_id=(select auth.uid())
 and m.is_active=true and m.membership_status='active'));

drop policy if exists business_documents_storage_insert on storage.objects;
create policy business_documents_storage_insert on storage.objects
for insert to authenticated
with check (
 bucket_id='business-documents'
 and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and (
  ((storage.foldername(name))[2]='settings' and exists(
   select 1 from public.organization_members m
   where m.organization_id=((storage.foldername(objects.name))[1])::uuid
    and m.user_id=(select auth.uid()) and m.is_active=true
    and m.membership_status='active' and m.role in ('owner','admin')))
  or ((storage.foldername(name))[2]='documents'
   and private.has_module_access(((storage.foldername(name))[1])::uuid,'documents','create'))
 )
);

drop policy if exists business_documents_storage_delete on storage.objects;
create policy business_documents_storage_delete on storage.objects
for delete to authenticated
using (
 bucket_id='business-documents'
 and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and (
  ((storage.foldername(name))[2]='settings' and exists(
   select 1 from public.organization_members m
   where m.organization_id=((storage.foldername(objects.name))[1])::uuid
    and m.user_id=(select auth.uid()) and m.is_active=true
    and m.membership_status='active' and m.role in ('owner','admin')))
  or ((storage.foldername(name))[2]='documents'
   and private.has_module_access(((storage.foldername(name))[1])::uuid,'documents','delete'))
 )
);

commit;
