-- Ensure the email column from auth.users is explicitly cast to the declared RPC return type.
create or replace function public.list_storeflow_employee_accounts(p_organization_id uuid)
returns table(user_id uuid,display_name text,email text,linked_employee_id uuid)
language plpgsql stable security definer set search_path=''
as $function$
declare v_user uuid := (select auth.uid());
begin
 if v_user is null or not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')) then
  raise exception using errcode='42501',message='ไม่มีสิทธิ์ดูบัญชีพนักงาน';
 end if;
 return query
 select m.user_id,coalesce(p.display_name,u.raw_user_meta_data->>'full_name','พนักงาน')::text,u.email::text,e.id
 from public.organization_members m
 join auth.users u on u.id=m.user_id
 left join public.profiles p on p.id=m.user_id
 left join public.employees e on e.organization_id=m.organization_id and e.user_id=m.user_id
 where m.organization_id=p_organization_id and m.is_active=true and m.membership_status='active' and m.role='employee'
 order by coalesce(p.display_name,u.email);
end;
$function$;
revoke all on function public.list_storeflow_employee_accounts(uuid) from public,anon;
grant execute on function public.list_storeflow_employee_accounts(uuid) to authenticated;
