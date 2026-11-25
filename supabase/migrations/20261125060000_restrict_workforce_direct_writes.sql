-- Direct employee, attendance and shift writes are limited to authorized managers.
-- Employee clock-in/out remains available only through SECURITY DEFINER RPCs.
begin;
create policy employees_workforce_insert_guard on public.employees as restrictive for insert to authenticated
with check(exists(select 1 from public.organization_members m where m.organization_id=employees.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')));
create policy employees_workforce_update_guard on public.employees as restrictive for update to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=employees.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')))
with check(exists(select 1 from public.organization_members m where m.organization_id=employees.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')));
create policy employees_workforce_delete_guard on public.employees as restrictive for delete to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=employees.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')));
create policy attendance_workforce_insert_guard on public.attendance as restrictive for insert to authenticated
with check(exists(select 1 from public.organization_members m where m.organization_id=attendance.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','manager','hr')));
create policy attendance_workforce_update_guard on public.attendance as restrictive for update to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=attendance.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','manager','hr')))
with check(exists(select 1 from public.organization_members m where m.organization_id=attendance.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','manager','hr')));
create policy attendance_workforce_delete_guard on public.attendance as restrictive for delete to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=attendance.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','manager','hr')));
create policy shifts_workforce_insert_guard on public.shifts as restrictive for insert to authenticated
with check(exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')));
create policy shifts_workforce_update_guard on public.shifts as restrictive for update to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')))
with check(exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')));
create policy shifts_workforce_delete_guard on public.shifts as restrictive for delete to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr')));
commit;
