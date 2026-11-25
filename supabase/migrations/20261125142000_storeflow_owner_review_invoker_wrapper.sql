-- Keep the owner manual-review RPC invoker-facing. The guarded implementation
-- lives in the private schema and is called only after auth.uid() is evaluated.

begin;
create or replace function private.owner_review_pos_slip_impl(
 p_organization_id uuid,p_sale_id uuid,p_approve boolean,p_transaction_ref text,p_note text default null
) returns void language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=(select auth.uid());v_sale public.sales%rowtype;v_role text;v_duplicate_receipt text;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 select role into v_role from public.organization_members
 where organization_id=p_organization_id and user_id=v_user and is_active and membership_status='active';
 if v_role <> 'owner' then raise exception using errcode='42501',message='เฉพาะเจ้าของร้านเท่านั้นที่ตรวจสอบและอนุมัติสลิปเองได้';end if;
 select * into v_sale from public.sales where id=p_sale_id and organization_id=p_organization_id for update;
 if not found or v_sale.payment_status<>'pending' or v_sale.verification_status not in ('pending_review','not_required') then raise exception using errcode='55000',message='ไม่พบบิลที่รอเจ้าของร้านตรวจสอบ';end if;
 if p_approve then
  if nullif(trim(v_sale.slip_url),'') is null or nullif(trim(coalesce(p_transaction_ref,'')),'') is null then raise exception using errcode='22023',message='ต้องมีรูปสลิปและเลขอ้างอิงธุรกรรมก่อนอนุมัติ';end if;
  if split_part(v_sale.slip_url,'/',1)<>p_organization_id::text or split_part(v_sale.slip_url,'/',2)<>'slips' or split_part(v_sale.slip_url,'/',3)<>p_sale_id::text then raise exception using errcode='22023',message='ตำแหน่งไฟล์สลิปไม่ตรงกับบิล';end if;
  select s.receipt_no into v_duplicate_receipt from public.sales s where s.organization_id=p_organization_id and s.transaction_ref=trim(p_transaction_ref) and s.id<>p_sale_id limit 1;
  if v_duplicate_receipt is null then
   select s.receipt_no into v_duplicate_receipt from public.payment_slips ps join public.sales s on s.id=ps.sale_id
   where ps.organization_id=p_organization_id and ps.transaction_ref=trim(p_transaction_ref) and ps.sale_id<>p_sale_id limit 1;
  end if;
  if v_duplicate_receipt is not null then raise exception using errcode='23505',message='สลิปนี้ถูกใช้งานไปแล้วในบิลเลขที่ '||v_duplicate_receipt;end if;
  update public.sales set transaction_ref=trim(p_transaction_ref) where id=p_sale_id and organization_id=p_organization_id;
  insert into public.payment_slips(organization_id,sale_id,transaction_ref,slip_url,provider,verification_status,amount,currency,receiver,verification_response,uploaded_by,verified_at)
  values(p_organization_id,p_sale_id,trim(p_transaction_ref),v_sale.slip_url,'owner_manual','manual_verified',v_sale.total,'THB','{}'::jsonb,jsonb_build_object('review_note',left(coalesce(p_note,''),1000)),v_user,now());
  update public.sales set verification_status='manual_verified',verification_provider='owner_manual',verification_response=jsonb_build_object('review_note',left(coalesce(p_note,''),1000),'reviewed_by',v_user),verified_at=now(),payment_status='paid',status='completed',paid_at=now(),amount_tendered=total where id=p_sale_id and organization_id=p_organization_id;
 else
  update public.sales set verification_status='rejected',verification_provider='owner_manual',verification_response=jsonb_build_object('review_note',left(coalesce(p_note,''),1000),'reviewed_by',v_user),payment_status='failed',status='payment_failed' where id=p_sale_id and organization_id=p_organization_id;
 end if;
end;$function$;
revoke all on function private.owner_review_pos_slip_impl(uuid,uuid,boolean,text,text) from public,anon;
grant execute on function private.owner_review_pos_slip_impl(uuid,uuid,boolean,text,text) to authenticated;

create or replace function public.owner_review_pos_slip(p_organization_id uuid,p_sale_id uuid,p_approve boolean,p_transaction_ref text,p_note text default null)
returns void language plpgsql security invoker set search_path to ''
as $function$
begin
 perform private.owner_review_pos_slip_impl(p_organization_id,p_sale_id,p_approve,p_transaction_ref,p_note);
end;$function$;
revoke all on function public.owner_review_pos_slip(uuid,uuid,boolean,text,text) from public,anon;
grant execute on function public.owner_review_pos_slip(uuid,uuid,boolean,text,text) to authenticated;
commit;