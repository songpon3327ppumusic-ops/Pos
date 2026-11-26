-- StoreFlow storage authorization hardening (2026-11-25)

-- Only store managers can change shared store assets. All active members may
-- still read product/store images according to the read policy.
drop policy if exists store_assets_member_insert on storage.objects;
create policy store_assets_member_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='store-assets'
  and array_length(storage.foldername(name),1)>=2
  and private.is_org_manager(((storage.foldername(name))[1])::uuid)
);

drop policy if exists store_assets_member_update on storage.objects;
create policy store_assets_member_update on storage.objects
for update to authenticated
using (
  bucket_id='store-assets'
  and private.is_org_manager(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id='store-assets'
  and array_length(storage.foldername(name),1)>=2
  and private.is_org_manager(((storage.foldername(name))[1])::uuid)
);

drop policy if exists store_assets_member_delete on storage.objects;
create policy store_assets_member_delete on storage.objects
for delete to authenticated
using (
  bucket_id='store-assets'
  and private.is_org_manager(((storage.foldername(name))[1])::uuid)
);

-- Restrict slip upload to POS roles and to an existing unpaid sale in the
-- same organization; no ordinary employee account may attach a payment slip.
drop policy if exists "Store members upload pending POS slips" on storage.objects;
create policy "Store members upload pending POS slips" on storage.objects
for insert to authenticated
with check (
  bucket_id='storeflow-pos-slips'
  and name ~ '^[0-9a-fA-F-]{36}/slips/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]+$'
  and exists (
    select 1 from public.sales s
    join public.organization_members m on m.organization_id=s.organization_id
    where s.organization_id=(split_part(objects.name,'/',1))::uuid
      and s.id=(split_part(objects.name,'/',3))::uuid
      and s.payment_status='pending' and s.status='pending_payment'
      and m.user_id=(select auth.uid()) and m.is_active
      and m.membership_status='active'
      and m.role in ('owner','admin','manager','cashier')
  )
);

create or replace function public.storeflow_attach_pos_slip(
  p_organization_id uuid,p_sale_id uuid,p_slip_path text,p_transaction_ref text
)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_sale public.sales%rowtype;
begin
  if v_user is null then raise exception using errcode='28000',message='Authentication required'; end if;
  if not exists(select 1 from public.organization_members m
    where m.organization_id=p_organization_id and m.user_id=v_user
      and m.is_active and m.membership_status='active'
      and m.role in ('owner','admin','manager','cashier')) then
    raise exception using errcode='42501',message='ไม่มีสิทธิ์แนบสลิปการชำระเงิน';
  end if;
  if p_slip_path is null or split_part(p_slip_path,'/',1)<>p_organization_id::text
    or split_part(p_slip_path,'/',2)<>'slips'
    or split_part(p_slip_path,'/',3)<>p_sale_id::text then
    raise exception using errcode='22023',message='ตำแหน่งไฟล์สลิปไม่ถูกต้อง';
  end if;
  if nullif(trim(coalesce(p_transaction_ref,'')),'') is null
    or length(trim(p_transaction_ref))>256 then
    raise exception using errcode='22023',message='ไม่พบรหัสอ้างอิงธุรกรรมจาก QR บนสลิป';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':slip:'||trim(p_transaction_ref),0));
  select * into v_sale from public.sales where id=p_sale_id and organization_id=p_organization_id for update;
  if not found or v_sale.payment_status<>'pending' or v_sale.status<>'pending_payment'
    or v_sale.payment_method not in ('QR PromptPay','โอนเงิน') then
    raise exception using errcode='55000',message='ไม่พบบิล QR ที่รอแนบสลิป';
  end if;
  if exists(select 1 from public.sales s where s.organization_id=p_organization_id
      and s.transaction_ref=trim(p_transaction_ref) and s.id<>p_sale_id)
    or exists(select 1 from public.payment_slips ps where ps.organization_id=p_organization_id
      and ps.transaction_ref=trim(p_transaction_ref) and ps.sale_id<>p_sale_id) then
    raise exception using errcode='23505',message='สลิปนี้ถูกใช้กับรายการอื่นแล้ว';
  end if;
  update public.sales set slip_url=p_slip_path,slip_path=p_slip_path,
    transaction_ref=trim(p_transaction_ref),verification_status='pending_review'
  where id=p_sale_id and organization_id=p_organization_id;
end;
$$;
revoke all on function public.storeflow_attach_pos_slip(uuid,uuid,text,text) from public,anon;
grant execute on function public.storeflow_attach_pos_slip(uuid,uuid,text,text) to authenticated;
