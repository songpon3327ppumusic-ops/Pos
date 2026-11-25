-- Restrict employee records containing compensation/bank data and permit employees to read their own row.
-- Payroll period read visibility is distinct from owner/admin write privileges.
begin;
drop policy if exists employees_workforce_visibility on public.employees;
drop policy if exists employees_self_select on public.employees;
create policy employees_workforce_visibility on public.employees as restrictive for select to authenticated
using (
 user_id=(select auth.uid())
 or exists(select 1 from public.organization_members m where m.organization_id=employees.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr'))
);
create policy employees_self_select on public.employees as permissive for select to authenticated
using (user_id=(select auth.uid()) and is_active=true);
drop policy if exists payroll_periods_owner_write_guard on public.payroll_periods;
drop policy if exists payroll_periods_read_guard on public.payroll_periods;
drop policy if exists payroll_periods_insert_guard on public.payroll_periods;
drop policy if exists payroll_periods_update_guard on public.payroll_periods;
drop policy if exists payroll_periods_delete_guard on public.payroll_periods;
create policy payroll_periods_read_guard on public.payroll_periods as restrictive for select to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin','hr','accountant')));
create policy payroll_periods_insert_guard on public.payroll_periods as restrictive for insert to authenticated
with check(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')));
create policy payroll_periods_update_guard on public.payroll_periods as restrictive for update to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')))
with check(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')));
create policy payroll_periods_delete_guard on public.payroll_periods as restrictive for delete to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')));
commit;
