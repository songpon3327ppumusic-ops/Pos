create or replace function public.get_store_invite_code()
returns text language plpgsql volatile security definer set search_path=''
as $function$
declare v_org uuid;v_code text;
begin
 if (select auth.uid()) is null then raise exception using errcode='28000',message='Authentication required';end if;
 select m.organization_id into v_org from public.organization_members m
 where m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'
 order by m.created_at limit 1;
 if v_org is null then raise exception using errcode='42501',message='Only active store owners can view invite code';end if;
 insert into private.organization_invites(organization_id,invite_code,is_active)
 values(v_org,upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,16)),true)
 on conflict(organization_id) do update set is_active=true returning invite_code into v_code;
 return v_code;
end;$function$;
revoke all on function public.get_store_invite_code() from public,anon;
grant execute on function public.get_store_invite_code() to authenticated;