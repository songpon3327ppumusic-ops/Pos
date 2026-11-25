begin;

-- Fold employee self-service visibility into the primary SELECT policies.
drop policy if exists workforce_self_attendance_select on public.attendance;
drop policy if exists workforce_self_shifts_select on public.shifts;
drop policy if exists workforce_self_payroll_items_select on public.payroll_items;
drop policy if exists employees_self_select on public.employees;

drop policy if exists attendance_access_select on public.attendance;
create policy attendance_access_select on public.attendance
for select to authenticated
using (
 private.has_module_access(organization_id,'attendance','read')
 or exists (
  select 1 from public.employees e
  where e.id=attendance.employee_id and e.organization_id=attendance.organization_id
   and e.user_id=(select auth.uid()) and e.is_active=true
 )
);

drop policy if exists shifts_access_select on public.shifts;
create policy shifts_access_select on public.shifts
for select to authenticated
using (
 private.has_module_access(organization_id,'attendance','read')
 or exists (
  select 1 from public.employees e
  where e.id=shifts.employee_id and e.organization_id=shifts.organization_id
   and e.user_id=(select auth.uid()) and e.is_active=true
 )
);

drop policy if exists payroll_items_select_access on public.payroll_items;
create policy payroll_items_select_access on public.payroll_items
for select to authenticated
using (
 private.has_module_access(organization_id,'payroll','read')
 or exists (
  select 1 from public.employees e
  where e.id=payroll_items.employee_id and e.organization_id=payroll_items.organization_id
   and e.user_id=(select auth.uid()) and e.is_active=true
 )
);

drop policy if exists employees_access_select on public.employees;
create policy employees_access_select on public.employees
for select to authenticated
using (
 private.has_module_access(organization_id,'employees','read')
 or (user_id=(select auth.uid()) and is_active=true)
);

-- Remove overlapping SELECT caused by FOR ALL write policies.
drop policy if exists document_sequences_read on public.document_sequences;
drop policy if exists document_sequences_write on public.document_sequences;
create policy document_sequences_read on public.document_sequences
for select to authenticated
using (private.has_module_access(organization_id,'documents','read'));
create policy document_sequences_insert on public.document_sequences
for insert to authenticated
with check (private.has_module_access(organization_id,'documents','update'));
create policy document_sequences_update on public.document_sequences
for update to authenticated
using (private.has_module_access(organization_id,'documents','update'))
with check (private.has_module_access(organization_id,'documents','update'));
create policy document_sequences_delete on public.document_sequences
for delete to authenticated
using (private.has_module_access(organization_id,'documents','update'));

drop policy if exists store_profiles_read on public.store_profiles;
drop policy if exists store_profiles_write on public.store_profiles;
create policy store_profiles_read on public.store_profiles
for select to authenticated
using (private.has_module_access(organization_id,'documents','read'));
create policy store_profiles_insert on public.store_profiles
for insert to authenticated
with check (private.has_module_access(organization_id,'documents','update'));
create policy store_profiles_update on public.store_profiles
for update to authenticated
using (private.has_module_access(organization_id,'documents','update'))
with check (private.has_module_access(organization_id,'documents','update'));
create policy store_profiles_delete on public.store_profiles
for delete to authenticated
using (private.has_module_access(organization_id,'documents','update'));

commit;
