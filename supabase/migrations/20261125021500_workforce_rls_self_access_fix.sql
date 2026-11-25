-- Workforce RLS correction: employee self-read is allowed without granting payroll writes.
begin;
drop policy if exists payroll_items_owner_write_guard on public.payroll_items;
drop policy if exists payroll_items_owner_insert_guard on public.payroll_items;
drop policy if exists payroll_items_owner_update_guard on public.payroll_items;
drop policy if exists payroll_items_owner_delete_guard on public.payroll_items;
drop policy if exists workforce_self_payroll_items_select on public.payroll_items;
drop policy if exists workforce_self_attendance_select on public.attendance;
drop policy if exists workforce_self_shifts_select on public.shifts;
create policy payroll_items_owner_insert_guard on public.payroll_items as restrictive for insert to authenticated
with check (exists(select 1 from public.organization_members m where m.organization_id=payroll_items.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')));
create policy payroll_items_owner_update_guard on public.payroll_items as restrictive for update to authenticated
using (exists(select 1 from public.organization_members m where m.organization_id=payroll_items.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')))
with check (exists(select 1 from public.organization_members m where m.organization_id=payroll_items.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')));
create policy payroll_items_owner_delete_guard on public.payroll_items as restrictive for delete to authenticated
using (exists(select 1 from public.organization_members m where m.organization_id=payroll_items.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')));
create policy workforce_self_payroll_items_select on public.payroll_items as permissive for select to authenticated
using (exists(select 1 from public.employees e where e.id=payroll_items.employee_id and e.organization_id=payroll_items.organization_id and e.user_id=(select auth.uid()) and e.is_active=true));
create policy workforce_self_attendance_select on public.attendance as permissive for select to authenticated
using (exists(select 1 from public.employees e where e.id=attendance.employee_id and e.organization_id=attendance.organization_id and e.user_id=(select auth.uid()) and e.is_active=true));
create policy workforce_self_shifts_select on public.shifts as permissive for select to authenticated
using (exists(select 1 from public.employees e where e.id=shifts.employee_id and e.organization_id=shifts.organization_id and e.user_id=(select auth.uid()) and e.is_active=true));
drop policy if exists payroll_periods_owner_write_guard on public.payroll_periods;
create policy payroll_periods_owner_write_guard on public.payroll_periods as restrictive for all to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')))
with check(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')));
create index if not exists attendance_shift_id_idx on public.attendance(shift_id);
create index if not exists employees_user_id_idx on public.employees(user_id);
create index if not exists shifts_employee_id_idx on public.shifts(employee_id);
create index if not exists payroll_items_employee_id_idx on public.payroll_items(employee_id);
do $fix$
declare v_definition text;
begin
 v_definition:=pg_get_functiondef('public.create_storeflow_payroll(uuid,date,date,date)'::regprocedure);
 v_definition:=replace(v_definition,'coalesce(e.wage_rate,e.base_salary,0)','coalesce(nullif(e.wage_rate,0),e.base_salary,0)');
 execute v_definition;
end $fix$;
alter table public.employees
 add constraint employees_wage_rate_nonnegative check (wage_rate >= 0) not valid,
 add constraint employees_position_allowance_nonnegative check (position_allowance >= 0) not valid,
 add constraint employees_regular_allowance_nonnegative check (regular_allowance >= 0) not valid,
 add constraint employees_overtime_rate_nonnegative check (overtime_hourly_rate >= 0) not valid;
alter table public.employees validate constraint employees_wage_rate_nonnegative;
alter table public.employees validate constraint employees_position_allowance_nonnegative;
alter table public.employees validate constraint employees_regular_allowance_nonnegative;
alter table public.employees validate constraint employees_overtime_rate_nonnegative;
commit;
