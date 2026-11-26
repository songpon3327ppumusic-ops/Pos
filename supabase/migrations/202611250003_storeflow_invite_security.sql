-- StoreFlow invitation hardening (2026-11-25)
alter table private.organization_invites
  add column if not exists expires_at timestamptz not null default (now()+interval '30 days');

create or replace function public.get_store_invite_code()
returns text language plpgsql security definer set search_path = ''
as $$
declare
  v_org uuid;
  v_code text := upper(encode(extensions.gen_random_bytes(16),'hex'));
  v_expires timestamptz := now()+interval '30 days';
  v_result text;
begin
  if (select auth.uid()) is null then raise exception using errcode='28000',message='Authentication required'; end if;
  select m.organization_id into v_org from public.organization_members m
  where m.user_id=(select auth.uid()) and m.role='owner' and m.is_active
    and m.membership_status='active' order by m.created_at limit 1;
  if v_org is null then raise exception using errcode='42501',message='Only active store owners can view invite code'; end if;
  insert into private.organization_invites(organization_id,invite_code,is_active,expires_at)
  values(v_org,v_code,true,v_expires)
  on conflict(organization_id) do update set
    invite_code=case when length(private.organization_invites.invite_code)<>32
      or private.organization_invites.is_active=false or private.organization_invites.expires_at<=now()
      then excluded.invite_code else private.organization_invites.invite_code end,
    is_active=true,
    expires_at=case when length(private.organization_invites.invite_code)<>32
      or private.organization_invites.is_active=false or private.organization_invites.expires_at<=now()
      then excluded.expires_at else private.organization_invites.expires_at end
  returning invite_code into v_result;
  return v_result;
end;
$$;
revoke all on function public.get_store_invite_code() from public,anon;
grant execute on function public.get_store_invite_code() to authenticated;

create or replace function public.storeflow_join_by_invite(p_invite_code text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid:=auth.uid(); v_org uuid; v_existing_role text;
  v_existing_active boolean; v_existing_status text;
begin
  if v_user is null then raise exception using errcode='28000',message='Authentication required'; end if;
  if nullif(trim(p_invite_code),'') is null or length(trim(p_invite_code))<>32 then
    raise exception using errcode='22023',message='กรุณากรอกรหัสเชิญที่ถูกต้อง';
  end if;
  select organization_id into v_org from private.organization_invites
  where invite_code=upper(trim(p_invite_code)) and is_active=true and expires_at>now() limit 1;
  if v_org is null then raise exception using errcode='P0002',message='รหัสเชิญไม่ถูกต้องหรือหมดอายุ'; end if;
  select role,is_active,membership_status into v_existing_role,v_existing_active,v_existing_status
  from public.organization_members where organization_id=v_org and user_id=v_user for update;
  if found then
    if v_existing_active and v_existing_status='active' then return v_org; end if;
    raise exception using errcode='42501',message='บัญชีนี้ถูกระงับหรือยังไม่ได้รับอนุมัติ กรุณาติดต่อเจ้าของร้าน';
  end if;
  insert into public.organization_members(organization_id,user_id,role,is_active,membership_status)
  values(v_org,v_user,'employee',true,'active');
  return v_org;
end;
$$;
revoke all on function public.storeflow_join_by_invite(text) from public,anon;
grant execute on function public.storeflow_join_by_invite(text) to authenticated;
