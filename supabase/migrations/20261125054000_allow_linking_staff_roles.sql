-- Allow approved cashier/manager/HR/accountant memberships to be linked to employee records too.
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
 where m.organization_id=p_organization_id and m.is_active=true and m.membership_status='active' and m.role in ('employee','cashier','manager','hr','accountant')
 order by coalesce(p.display_name,u.email);
end;
$function$;
create or replace function public.link_storeflow_employee_account(p_organization_id uuid,p_employee_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_user uuid := (select auth.uid());
begin
 if v_user is null or not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')) then
  raise exception using errcode='42501',message='ไม่มีสิทธิ์ผูกบัญชีพนักงาน';
 end if;
 if not exists(select 1 from public.employees e where e.id=p_employee_id and e.organization_id=p_organization_id) then
  raise exception using errcode='23503',message='ไม่พบพนักงานในร้านนี้';
 end if;
 if p_user_id is not null and not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=p_user_id and m.is_active=true and m.membership_status='active' and m.role in ('employee','cashier','manager','hr','accountant')) then
  raise exception using errcode='42501',message='บัญชีนี้ยังไม่ได้รับอนุมัติเป็นพนักงานของร้าน';
 end if;
 if p_user_id is not null and exists(select 1 from public.employees e where e.organization_id=p_organization_id and e.user_id=p_user_id and e.id<>p_employee_id) then
  raise exception using errcode='23505',message='บัญชีนี้ถูกผูกกับพนักงานคนอื่นแล้ว';
 end if;
 update public.employees set user_id=p_user_id where id=p_employee_id and organization_id=p_organization_id;
end;
$function$;
revoke all on function public.list_storeflow_employee_accounts(uuid) from public,anon;
grant execute on function public.list_storeflow_employee_accounts(uuid) to authenticated;
revoke all on function public.link_storeflow_employee_account(uuid,uuid,uuid) from public,anon;
grant execute on function public.link_storeflow_employee_account(uuid,uuid,uuid) to authenticated;
