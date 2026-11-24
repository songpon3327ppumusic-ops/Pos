-- StoreFlow payroll access controls and editable role defaults
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.has_module_access(
  p_organization_id uuid,
  p_module text,
  p_action text
) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_allowed boolean;
begin
  if auth.uid() is null then return false; end if;
  select m.role into v_role
  from public.organization_members m
  where m.organization_id = p_organization_id
    and m.user_id = (select auth.uid())
    and m.is_active = true
  limit 1;
  if v_role is null then return false; end if;
  if v_role in ('owner','admin') then return true; end if;

  select rp.allowed into v_allowed
  from public.role_permissions rp
  where rp.organization_id = p_organization_id
    and rp.role = v_role
    and rp.module = p_module
    and rp.action = p_action
  limit 1;

  if v_allowed is not null then return v_allowed; end if;

  return case v_role
    when 'manager' then p_action in ('read','create','update') and p_module not in ('payroll','permissions','audit')
    when 'cashier' then (p_module in ('pos','orders') and p_action in ('read','create'))
    when 'hr' then (p_module in ('employees','attendance','leave','payroll') and p_action in ('read','create','update'))
    when 'accountant' then (p_module in ('reports','expenses','payroll','orders') and p_action in ('read','create','update','approve'))
    when 'employee' then (p_module in ('dashboard','attendance','leave') and p_action in ('read','create'))
    else false
  end;
end;
$$;

revoke all on function private.has_module_access(uuid,text,text) from public, anon;
grant execute on function private.has_module_access(uuid,text,text) to authenticated;

insert into public.role_permissions (organization_id, role, module, action, allowed)
select o.id, r.role, m.module, a.action,
  case
    when r.role in ('owner','admin') then true
    when r.role='manager' then a.action in ('read','create','update') and m.module not in ('payroll','permissions','audit')
    when r.role='cashier' then m.module in ('pos','orders') and a.action in ('read','create')
    when r.role='hr' then m.module in ('employees','attendance','leave','payroll') and a.action in ('read','create','update')
    when r.role='accountant' then m.module in ('reports','expenses','payroll','orders') and a.action in ('read','create','update','approve')
    when r.role='employee' then m.module in ('dashboard','attendance','leave') and a.action in ('read','create')
    else false
  end
from public.organizations o
cross join (values ('owner'),('admin'),('manager'),('cashier'),('hr'),('accountant'),('employee')) r(role)
cross join (values ('dashboard'),('pos'),('orders'),('inventory'),('customers'),('employees'),('expenses'),('reports'),('payroll'),('permissions'),('audit'),('attendance'),('leave')) m(module)
cross join (values ('read'),('create'),('update'),('delete'),('approve')) a(action)
on conflict (organization_id,role,module,action) do nothing;

drop policy if exists payroll_periods_member_select on public.payroll_periods;
drop policy if exists payroll_periods_manager_insert on public.payroll_periods;
drop policy if exists payroll_periods_manager_update on public.payroll_periods;
drop policy if exists payroll_periods_admin_delete on public.payroll_periods;
create policy payroll_periods_select_access on public.payroll_periods for select to authenticated using (private.has_module_access(organization_id,'payroll','read'));
create policy payroll_periods_insert_access on public.payroll_periods for insert to authenticated with check (private.has_module_access(organization_id,'payroll','create'));
create policy payroll_periods_update_access on public.payroll_periods for update to authenticated using (private.has_module_access(organization_id,'payroll','update') or private.has_module_access(organization_id,'payroll','approve')) with check (private.has_module_access(organization_id,'payroll','update') or private.has_module_access(organization_id,'payroll','approve'));
create policy payroll_periods_delete_access on public.payroll_periods for delete to authenticated using (private.has_module_access(organization_id,'payroll','delete'));

drop policy if exists payroll_items_member_select on public.payroll_items;
drop policy if exists payroll_items_manager_insert on public.payroll_items;
drop policy if exists payroll_items_manager_update on public.payroll_items;
drop policy if exists payroll_items_admin_delete on public.payroll_items;
create policy payroll_items_select_access on public.payroll_items for select to authenticated using (private.has_module_access(organization_id,'payroll','read'));
create policy payroll_items_insert_access on public.payroll_items for insert to authenticated with check (private.has_module_access(organization_id,'payroll','create'));
create policy payroll_items_update_access on public.payroll_items for update to authenticated using (private.has_module_access(organization_id,'payroll','update') or private.has_module_access(organization_id,'payroll','approve')) with check (private.has_module_access(organization_id,'payroll','update') or private.has_module_access(organization_id,'payroll','approve'));
create policy payroll_items_delete_access on public.payroll_items for delete to authenticated using (private.has_module_access(organization_id,'payroll','delete'));

drop policy if exists role_permissions_member_select on public.role_permissions;
drop policy if exists role_permissions_manager_insert on public.role_permissions;
drop policy if exists role_permissions_manager_update on public.role_permissions;
drop policy if exists role_permissions_admin_delete on public.role_permissions;
create policy role_permissions_select_admin on public.role_permissions for select to authenticated using (private.has_module_access(organization_id,'permissions','read'));
create policy role_permissions_insert_admin on public.role_permissions for insert to authenticated with check (private.has_module_access(organization_id,'permissions','update'));
create policy role_permissions_update_admin on public.role_permissions for update to authenticated using (private.has_module_access(organization_id,'permissions','update')) with check (private.has_module_access(organization_id,'permissions','update'));
create policy role_permissions_delete_admin on public.role_permissions for delete to authenticated using (private.has_module_access(organization_id,'permissions','update'));

create index if not exists payroll_periods_org_start_idx on public.payroll_periods(organization_id,period_start desc);
create index if not exists payroll_items_org_period_idx on public.payroll_items(organization_id,payroll_period_id);
