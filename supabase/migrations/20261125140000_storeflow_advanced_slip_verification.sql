-- StoreFlow advanced bank slip verification
-- Applied to the linked StoreFlow Supabase project on 2026-11-25.

alter table public.sales
 add column if not exists slip_url text,
 add column if not exists transaction_ref text,
 add column if not exists verification_status text not null default 'not_required',
 add column if not exists verification_provider text,
 add column if not exists verified_at timestamptz,
 add column if not exists verification_response jsonb not null default '{}'::jsonb;

alter table public.sales drop constraint if exists sales_verification_status_check;
alter table public.sales add constraint sales_verification_status_check
 check (verification_status in ('not_required','pending_review','verified','manual_verified','rejected'));
create unique index if not exists sales_org_transaction_ref_unique
 on public.sales(organization_id,transaction_ref) where transaction_ref is not null;

create table if not exists public.payment_slips (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 sale_id uuid not null references public.sales(id) on delete cascade,
 transaction_ref text not null, slip_url text not null, provider text not null,
 verification_status text not null check (verification_status in ('verified','manual_verified','rejected','pending_review')),
 amount numeric(12,2), currency text not null default 'THB', transfer_at timestamptz,
 receiver jsonb not null default '{}'::jsonb, verification_response jsonb not null default '{}'::jsonb,
 uploaded_by uuid references auth.users(id), verified_at timestamptz, created_at timestamptz not null default now(),
 constraint payment_slips_org_transaction_ref_unique unique(organization_id,transaction_ref),
 constraint payment_slips_org_sale_unique unique(organization_id,sale_id)
);
alter table public.payment_slips enable row level security;
drop policy if exists payment_slips_owner_audit_read on public.payment_slips;
create policy payment_slips_owner_audit_read on public.payment_slips for select to authenticated using (
 exists(select 1 from public.organization_members m where m.organization_id=payment_slips.organization_id
 and m.user_id=(select auth.uid()) and m.is_active and m.membership_status='active'
 and m.role in ('owner','admin','manager','accountant'))
);
revoke insert,update,delete on public.payment_slips from anon,authenticated;
grant select on public.payment_slips to authenticated;

create table if not exists public.store_slip_provider_credentials (
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 provider text not null check(provider in ('easyslip')), encrypted_api_key text not null, nonce text not null,
 configured_by uuid references auth.users(id), configured_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.store_slip_provider_credentials enable row level security;
revoke all on public.store_slip_provider_credentials from anon,authenticated;
grant all on public.store_slip_provider_credentials to service_role;

create or replace function public.finalize_verified_pos_slip(
 p_organization_id uuid,p_sale_id uuid,p_slip_url text,p_transaction_ref text,p_provider text,
 p_amount numeric,p_currency text,p_transfer_at timestamptz,p_receiver jsonb,p_verification_response jsonb,p_uploaded_by uuid
) returns void language plpgsql security definer set search_path to ''
as $function$
declare v_sale public.sales%rowtype;
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' then raise exception using errcode='42501',message='Only the verified payment service can finalize a bank slip';end if;
 if p_slip_url is null or p_transaction_ref is null or length(trim(p_transaction_ref))=0 then raise exception using errcode='22023',message='Slip image and transaction reference are required';end if;
 select * into v_sale from public.sales where id=p_sale_id and organization_id=p_organization_id for update;
 if not found then raise exception using errcode='P0002',message='ไม่พบบิล';end if;
 if v_sale.payment_status <> 'pending' or v_sale.payment_method not in ('QR PromptPay','โอนเงิน','bank_transfer','transfer') then raise exception using errcode='55000',message='บิลไม่อยู่ในสถานะรอตรวจสอบการโอน';end if;
 if round(coalesce(p_amount,0),2) <> round(v_sale.total,2) or upper(coalesce(p_currency,'')) <> 'THB' then raise exception using errcode='22023',message='ยอดเงินหรือสกุลเงินไม่ตรงกับบิล';end if;
 insert into public.payment_slips(organization_id,sale_id,transaction_ref,slip_url,provider,verification_status,amount,currency,transfer_at,receiver,verification_response,uploaded_by,verified_at)
 values(p_organization_id,p_sale_id,trim(p_transaction_ref),p_slip_url,p_provider,'verified',p_amount,'THB',p_transfer_at,coalesce(p_receiver,'{}'::jsonb),coalesce(p_verification_response,'{}'::jsonb),p_uploaded_by,now());
 update public.sales set slip_url=p_slip_url,slip_path=p_slip_url,transaction_ref=trim(p_transaction_ref),payment_ref=trim(p_transaction_ref),
 verification_status='verified',verification_provider=p_provider,verification_response=coalesce(p_verification_response,'{}'::jsonb),
 verified_at=now(),payment_status='paid',status='completed',paid_at=now(),amount_tendered=total
 where id=p_sale_id and organization_id=p_organization_id and payment_status='pending';
 if not found then raise exception using errcode='55000',message='บิลถูกเปลี่ยนสถานะระหว่างตรวจสอบ';end if;
end;$function$;
revoke all on function public.finalize_verified_pos_slip(uuid,uuid,text,text,text,numeric,text,timestamptz,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.finalize_verified_pos_slip(uuid,uuid,text,text,text,numeric,text,timestamptz,jsonb,jsonb,uuid) to service_role;

drop function if exists public.owner_review_pos_slip(uuid,uuid,boolean,text);
create or replace function public.owner_review_pos_slip(p_organization_id uuid,p_sale_id uuid,p_approve boolean,p_transaction_ref text,p_note text default null)
returns void language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=(select auth.uid());v_sale public.sales%rowtype;v_role text;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 select role into v_role from public.organization_members where organization_id=p_organization_id and user_id=v_user and is_active and membership_status='active';
 if v_role <> 'owner' then raise exception using errcode='42501',message='เฉพาะเจ้าของร้านเท่านั้นที่ตรวจสอบและอนุมัติสลิปเองได้';end if;
 select * into v_sale from public.sales where id=p_sale_id and organization_id=p_organization_id for update;
 if not found or v_sale.payment_status<>'pending' or v_sale.verification_status not in ('pending_review','not_required') then raise exception using errcode='55000',message='ไม่พบบิลที่รอเจ้าของร้านตรวจสอบ';end if;
 if p_approve then
  if nullif(trim(v_sale.slip_url),'') is null or nullif(trim(coalesce(p_transaction_ref,'')),'') is null then raise exception using errcode='22023',message='ต้องมีรูปสลิปและเลขอ้างอิงธุรกรรมก่อนอนุมัติ';end if;
  if split_part(v_sale.slip_url,'/',1)<>p_organization_id::text or split_part(v_sale.slip_url,'/',2)<>'slips' or split_part(v_sale.slip_url,'/',3)<>p_sale_id::text then raise exception using errcode='22023',message='ตำแหน่งไฟล์สลิปไม่ตรงกับบิล';end if;
  update public.sales set transaction_ref=trim(p_transaction_ref) where id=p_sale_id and organization_id=p_organization_id;
  insert into public.payment_slips(organization_id,sale_id,transaction_ref,slip_url,provider,verification_status,amount,currency,receiver,verification_response,uploaded_by,verified_at)
  values(p_organization_id,p_sale_id,trim(p_transaction_ref),v_sale.slip_url,'owner_manual','manual_verified',v_sale.total,'THB','{}'::jsonb,jsonb_build_object('review_note',left(coalesce(p_note,''),1000)),v_user,now());
  update public.sales set verification_status='manual_verified',verification_provider='owner_manual',
   verification_response=jsonb_build_object('review_note',left(coalesce(p_note,''),1000),'reviewed_by',v_user),
   verified_at=now(),payment_status='paid',status='completed',paid_at=now(),amount_tendered=total
  where id=p_sale_id and organization_id=p_organization_id;
 else
  update public.sales set verification_status='rejected',verification_provider='owner_manual',
   verification_response=jsonb_build_object('review_note',left(coalesce(p_note,''),1000),'reviewed_by',v_user),
   payment_status='failed',status='payment_failed' where id=p_sale_id and organization_id=p_organization_id;
 end if;
end;$function$;
revoke all on function public.owner_review_pos_slip(uuid,uuid,boolean,text,text) from public,anon;
grant execute on function public.owner_review_pos_slip(uuid,uuid,boolean,text,text) to authenticated;

create or replace function private.guard_verified_bank_payment()
returns trigger language plpgsql set search_path to ''
as $function$
begin
 if current_user not in ('postgres','service_role') and (
  new.payment_status is distinct from old.payment_status or new.verification_status is distinct from old.verification_status
  or new.transaction_ref is distinct from old.transaction_ref or new.slip_url is distinct from old.slip_url or new.verified_at is distinct from old.verified_at
 ) then raise exception using errcode='42501',message='Payment verification fields can only be changed by trusted payment workflows';end if;
 if new.payment_method in ('QR PromptPay','โอนเงิน','bank_transfer','transfer') and new.payment_status='paid' then
  if nullif(trim(new.slip_url),'') is null or nullif(trim(new.transaction_ref),'') is null or new.verification_status not in ('verified','manual_verified') then
   raise exception using errcode='23514',message='การชำระด้วย QR/โอนเงินต้องมีสลิปและผลตรวจสอบที่ผ่านก่อนออกใบเสร็จ';
  end if;
 end if;
 return new;
end;$function$;
revoke all on function private.guard_verified_bank_payment() from public,anon,authenticated;
drop trigger if exists guard_verified_bank_payment on public.sales;
create trigger guard_verified_bank_payment before update on public.sales for each row execute function private.guard_verified_bank_payment();
revoke execute on function public.confirm_pos_payment(uuid,uuid,text,text) from public,anon,authenticated;
update storage.buckets set file_size_limit=4194304 where id='store-payment-assets';
