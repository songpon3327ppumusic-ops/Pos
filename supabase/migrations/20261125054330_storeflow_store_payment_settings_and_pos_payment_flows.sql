begin;

create table if not exists public.store_payment_settings (
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 cash_enabled boolean not null default true,
 promptpay_enabled boolean not null default false,
 bank_transfer_enabled boolean not null default false,
 card_edc_enabled boolean not null default false,
 credit_enabled boolean not null default false,
 stripe_enabled boolean not null default false,
 omise_enabled boolean not null default false,
 promptpay_mode text not null default 'dynamic' check(promptpay_mode in ('dynamic','uploaded')),
 promptpay_id text,
 promptpay_name text,
 qr_image_path text,
 bank_name text,
 bank_account_name text,
 bank_account_number text,
 stripe_connect_account_id text,
 stripe_charges_enabled boolean not null default false,
 stripe_payouts_enabled boolean not null default false,
 stripe_webhook_verified boolean not null default false,
 omise_connected boolean not null default false,
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default now(),
 constraint store_payment_settings_promptpay_id_check check(promptpay_id is null or promptpay_id ~ '^(0[0-9]{9}|[0-9]{13})$')
);

alter table public.sales
 add column if not exists payment_status text not null default 'paid',
 add column if not exists amount_tendered numeric(12,2),
 add column if not exists change_amount numeric(12,2) not null default 0,
 add column if not exists payment_ref text,
 add column if not exists slip_path text,
 add column if not exists card_approval_code text,
 add column if not exists card_last4 text,
 add column if not exists paid_at timestamptz;

update public.sales set amount_tendered=coalesce(amount_tendered,cash_received,total),change_amount=coalesce(change_amount,change_due,0),paid_at=coalesce(paid_at,created_at) where payment_status='paid';
alter table public.sales drop constraint if exists sales_payment_status_check;
alter table public.sales add constraint sales_payment_status_check check(payment_status in ('pending','paid','unpaid','partial','failed','refunded'));
alter table public.customers add column if not exists credit_balance numeric(12,2) not null default 0;

create table if not exists public.customer_credit_ledger (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 customer_id uuid not null references public.customers(id) on delete restrict,
 sale_id uuid references public.sales(id) on delete set null,
 entry_type text not null check(entry_type in ('charge','payment','adjustment')),
 amount numeric(12,2) not null check(amount>0),
 payment_method text,
 payment_ref text,
 notes text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create index if not exists customer_credit_ledger_org_customer_created_idx on public.customer_credit_ledger(organization_id,customer_id,created_at desc);
create index if not exists sales_org_payment_status_created_idx on public.sales(organization_id,payment_status,created_at desc);

alter table public.store_payment_settings enable row level security;
alter table public.customer_credit_ledger enable row level security;

drop policy if exists store_payment_settings_member_read on public.store_payment_settings;
create policy store_payment_settings_member_read on public.store_payment_settings for select to authenticated using(private.is_org_member(organization_id));
drop policy if exists store_payment_settings_owner_insert on public.store_payment_settings;
create policy store_payment_settings_owner_insert on public.store_payment_settings for insert to authenticated with check(exists(select 1 from public.organization_members m where m.organization_id=store_payment_settings.organization_id and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists store_payment_settings_owner_update on public.store_payment_settings;
create policy store_payment_settings_owner_update on public.store_payment_settings for update to authenticated using(exists(select 1 from public.organization_members m where m.organization_id=store_payment_settings.organization_id and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active')) with check(exists(select 1 from public.organization_members m where m.organization_id=store_payment_settings.organization_id and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists store_payment_settings_owner_delete on public.store_payment_settings;
create policy store_payment_settings_owner_delete on public.store_payment_settings for delete to authenticated using(exists(select 1 from public.organization_members m where m.organization_id=store_payment_settings.organization_id and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));

drop policy if exists customer_credit_ledger_member_read on public.customer_credit_ledger;
create policy customer_credit_ledger_member_read on public.customer_credit_ledger for select to authenticated using(private.is_org_member(organization_id));
revoke insert,update,delete on public.customer_credit_ledger from anon,authenticated;
grant select on public.customer_credit_ledger to authenticated;
revoke all on public.store_payment_settings from anon;
grant select,insert,update,delete on public.store_payment_settings to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('store-payment-assets','store-payment-assets',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/png','image/jpeg','image/webp'];

drop policy if exists store_payment_assets_member_read on storage.objects;
create policy store_payment_assets_member_read on storage.objects for select to authenticated using(bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and private.is_org_member(((storage.foldername(name))[1])::uuid));
drop policy if exists store_payment_assets_owner_qr_insert on storage.objects;
create policy store_payment_assets_owner_qr_insert on storage.objects for insert to authenticated with check(bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and (storage.foldername(name))[2]='qr' and exists(select 1 from public.organization_members m where m.organization_id=((storage.foldername(name))[1])::uuid and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists store_payment_assets_owner_qr_delete on storage.objects;
create policy store_payment_assets_owner_qr_delete on storage.objects for delete to authenticated using(bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and (storage.foldername(name))[2]='qr' and exists(select 1 from public.organization_members m where m.organization_id=((storage.foldername(name))[1])::uuid and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists store_payment_assets_member_slip_insert on storage.objects;
create policy store_payment_assets_member_slip_insert on storage.objects for insert to authenticated with check(bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and (storage.foldername(name))[2]='slips' and private.is_org_member(((storage.foldername(name))[1])::uuid) and exists(select 1 from public.sales s where s.organization_id=((storage.foldername(name))[1])::uuid and s.id=((storage.foldername(name))[3])::uuid));
drop policy if exists store_payment_assets_member_slip_delete on storage.objects;
create policy store_payment_assets_member_slip_delete on storage.objects for delete to authenticated using(bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and (storage.foldername(name))[2]='slips' and private.is_org_member(((storage.foldername(name))[1])::uuid));

create or replace function public.create_pos_sale_with_payment(p_organization_id uuid,p_items jsonb,p_payment_method text,p_discount numeric,p_tax numeric,p_customer_id uuid,p_idempotency_key uuid,p_cash_received numeric,p_amount_tendered numeric,p_payment_ref text,p_slip_path text,p_card_approval_code text,p_card_last4 text)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=(select auth.uid());v_role text;v_sale uuid;v_total numeric(12,2);v_method text:=lower(trim(coalesce(p_payment_method,'')));v_enabled boolean:=false;v_status text:='paid';v_sale_status text:='completed';v_tendered numeric(12,2):=0;v_settings public.store_payment_settings%rowtype;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 select m.role into v_role from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active';
 if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระเงิน';end if;
 select * into v_settings from public.store_payment_settings where organization_id=p_organization_id;
 if v_method in ('cash','เงินสด') then v_method:='cash';v_enabled:=coalesce(v_settings.cash_enabled,true);v_tendered:=coalesce(p_cash_received,0);
 elsif v_method in ('promptpay','qr promptpay','qr') then v_method:='promptpay';v_enabled:=coalesce(v_settings.promptpay_enabled,false);v_status:='pending';v_sale_status:='pending_payment';
 elsif v_method in ('bank_transfer','โอนเงิน') then v_method:='bank_transfer';v_enabled:=coalesce(v_settings.bank_transfer_enabled,false);v_status:='pending';v_sale_status:='pending_payment';
 elsif v_method in ('card_edc','บัตรเครดิต/เดบิต','บัตรเครดิต/เดบิต (edc)') then v_method:='card_edc';v_enabled:=coalesce(v_settings.card_edc_enabled,false);if nullif(trim(coalesce(p_card_approval_code,'')),'') is null then raise exception using errcode='22023',message='กรุณากรอกรหัสอนุมัติจากเครื่อง EDC';end if;if p_card_last4 is not null and p_card_last4 !~ '^[0-9]{4}$' then raise exception using errcode='22023',message='เลขท้ายบัตรต้องมี 4 หลัก';end if;v_tendered:=coalesce(p_amount_tendered,0);
 elsif v_method in ('credit','customer_credit','เงินเชื่อ') then v_method:='customer_credit';v_enabled:=coalesce(v_settings.credit_enabled,false);v_status:='unpaid';v_tendered:=0;if p_customer_id is null then raise exception using errcode='22023',message='กรุณาเลือกลูกค้าก่อนบันทึกเงินเชื่อ';end if;
 elsif v_method in ('stripe','stripe_card') then raise exception using errcode='0A000',message='ยังไม่ได้เชื่อมต่อ Stripe Connect สำหรับร้านนี้';
 else raise exception using errcode='22023',message='ไม่รองรับช่องทางชำระเงินนี้';end if;
 if not v_enabled then raise exception using errcode='55000',message='ร้านยังไม่ได้เปิดใช้งานช่องทางชำระเงินนี้';end if;
 if v_method='cash' and v_tendered<0 then raise exception using errcode='22023',message='จำนวนเงินรับไม่ถูกต้อง';end if;
 if v_method='card_edc' and coalesce(p_amount_tendered,0)<=0 then raise exception using errcode='22023',message='ยอดชำระผ่าน EDC ไม่ถูกต้อง';end if;
 if p_slip_path is not null and (split_part(p_slip_path,'/',1)<>p_organization_id::text or split_part(p_slip_path,'/',2)<>'slips') then raise exception using errcode='22023',message='ตำแหน่งไฟล์สลิปไม่ถูกต้อง';end if;
 v_sale:=public.checkout_sale_idempotent(p_organization_id,p_items,case when v_method='cash' then 'เงินสด' when v_method='promptpay' then 'QR PromptPay' when v_method='bank_transfer' then 'โอนเงิน' when v_method='card_edc' then 'บัตรเครดิต/เดบิต' else 'เงินเชื่อ' end,p_discount,p_tax,p_customer_id,p_idempotency_key,case when v_method='cash' then p_cash_received else null end);
 select total into v_total from public.sales where id=v_sale and organization_id=p_organization_id;
 if v_method='cash' and v_tendered<v_total then raise exception using errcode='22023',message='เงินสดที่รับน้อยกว่ายอดชำระ';end if;
 if v_method='card_edc' and round(coalesce(p_amount_tendered,0),2)<>round(v_total,2) then raise exception using errcode='22023',message='ยอดเครื่อง EDC ต้องตรงกับยอดบิล';end if;
 update public.sales set payment_method=case when v_method='cash' then 'เงินสด' when v_method='promptpay' then 'QR PromptPay' when v_method='bank_transfer' then 'โอนเงิน' when v_method='card_edc' then 'บัตรเครดิต/เดบิต (EDC)' else 'เงินเชื่อ' end,payment_status=v_status,status=v_sale_status,amount_tendered=case when v_method='cash' then v_tendered when v_method='card_edc' then v_total else 0 end,change_amount=case when v_method='cash' then round(v_tendered-v_total,2) else 0 end,cash_received=case when v_method='cash' then v_tendered else null end,change_due=case when v_method='cash' then round(v_tendered-v_total,2) else 0 end,payment_ref=nullif(trim(coalesce(p_payment_ref,'')),''),slip_path=p_slip_path,card_approval_code=nullif(trim(coalesce(p_card_approval_code,'')),''),card_last4=nullif(trim(coalesce(p_card_last4,'')),''),paid_at=case when v_status='paid' then now() else null end where id=v_sale and organization_id=p_organization_id;
 if v_method='customer_credit' then insert into public.customer_credit_ledger(organization_id,customer_id,sale_id,entry_type,amount,notes,created_by) values(p_organization_id,p_customer_id,v_sale,'charge',v_total,'ยอดขายเชื่อ '||(select receipt_no from public.sales where id=v_sale),v_user) on conflict do nothing;if found then update public.customers set credit_balance=coalesce(credit_balance,0)+v_total where id=p_customer_id and organization_id=p_organization_id;end if;end if;
 return v_sale;
end;$function$;

create or replace function public.confirm_pos_payment(p_organization_id uuid,p_sale_id uuid,p_payment_ref text default null,p_slip_path text default null)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=(select auth.uid());v_role text;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 select m.role into v_role from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active';
 if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์ยืนยันการชำระเงิน';end if;
 if p_slip_path is not null and (split_part(p_slip_path,'/',1)<>p_organization_id::text or split_part(p_slip_path,'/',2)<>'slips' or split_part(p_slip_path,'/',3)<>p_sale_id::text) then raise exception using errcode='22023',message='ไฟล์สลิปไม่ตรงกับบิล';end if;
 update public.sales set payment_status='paid',status='completed',paid_at=now(),payment_ref=coalesce(nullif(trim(coalesce(p_payment_ref,'')),''),payment_ref),slip_path=coalesce(p_slip_path,slip_path),amount_tendered=total where id=p_sale_id and organization_id=p_organization_id and payment_status='pending' and payment_method in ('QR PromptPay','โอนเงิน');
 if not found then raise exception using errcode='55000',message='ไม่พบรายการรอชำระ หรือบิลนี้ถูกยืนยันแล้ว';end if;
end;$function$;

create or replace function public.record_customer_credit_payment(p_organization_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_payment_ref text default null)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=(select auth.uid());v_role text;v_balance numeric(12,2);v_cash_enabled boolean;v_remaining numeric(12,2);v_due numeric(12,2);v_apply numeric(12,2);v_sale record;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 select m.role into v_role from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active';
 if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระหนี้';end if;
 if p_payment_method not in ('เงินสด','cash') then raise exception using errcode='22023',message='การรับชำระหนี้ผ่านระบบนี้รองรับเงินสดเท่านั้น กรุณายืนยันยอดโอนแยกก่อน';end if;
 select coalesce(cash_enabled,false) into v_cash_enabled from public.store_payment_settings where organization_id=p_organization_id;
 if not coalesce(v_cash_enabled,true) then raise exception using errcode='55000',message='ร้านปิดรับชำระเงินสด';end if;
 select credit_balance into v_balance from public.customers where id=p_customer_id and organization_id=p_organization_id for update;
 if not found then raise exception using errcode='23503',message='ไม่พบลูกค้าในร้านนี้';end if;
 if p_amount is null or p_amount<=0 or p_amount>v_balance then raise exception using errcode='22023',message='ยอดรับชำระไม่ถูกต้อง';end if;
 v_remaining:=round(p_amount,2);
 for v_sale in select id,total,coalesce(amount_tendered,0) as paid from public.sales where organization_id=p_organization_id and customer_id=p_customer_id and payment_status in ('unpaid','partial') order by created_at,id for update loop
  exit when v_remaining<=0;v_due:=greatest(0,round(v_sale.total-v_sale.paid,2));v_apply:=least(v_remaining,v_due);
  if v_apply>0 then update public.sales set amount_tendered=coalesce(amount_tendered,0)+v_apply,payment_status=case when coalesce(amount_tendered,0)+v_apply>=total then 'paid' else 'partial' end,paid_at=case when coalesce(amount_tendered,0)+v_apply>=total then now() else null end where id=v_sale.id and organization_id=p_organization_id;
   insert into public.customer_credit_ledger(organization_id,customer_id,sale_id,entry_type,amount,payment_method,payment_ref,notes,created_by) values(p_organization_id,p_customer_id,v_sale.id,'payment',v_apply,'เงินสด',p_payment_ref,'รับชำระยอดขายเชื่อ',v_user);v_remaining:=v_remaining-v_apply;end if;
 end loop;
 if v_remaining>0 then insert into public.customer_credit_ledger(organization_id,customer_id,entry_type,amount,payment_method,payment_ref,notes,created_by) values(p_organization_id,p_customer_id,'payment',v_remaining,'เงินสด',p_payment_ref,'รับชำระยอดค้างเดิม',v_user);end if;
 update public.customers set credit_balance=greatest(0,credit_balance-p_amount) where id=p_customer_id and organization_id=p_organization_id;
end;$function$;
revoke all on function public.create_pos_sale_with_payment(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric,numeric,text,text,text,text) from public,anon;
grant execute on function public.create_pos_sale_with_payment(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric,numeric,text,text,text,text) to authenticated;
revoke all on function public.confirm_pos_payment(uuid,uuid,text,text) from public,anon;
grant execute on function public.confirm_pos_payment(uuid,uuid,text,text) to authenticated;
revoke all on function public.record_customer_credit_payment(uuid,uuid,numeric,text,text) from public,anon;
grant execute on function public.record_customer_credit_payment(uuid,uuid,numeric,text,text) to authenticated;

commit;