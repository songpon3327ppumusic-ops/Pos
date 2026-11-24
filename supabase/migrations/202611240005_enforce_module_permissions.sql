-- Enforce per-module permissions for operational tables
do $$
declare item record;
begin
  for item in
    select * from (values
      ('products','inventory'),('customers','customers'),('employees','employees'),
      ('expenses','expenses'),('sales','orders'),('sale_items','orders'),
      ('stock_movements','inventory'),('audit_logs','audit'),
      ('attendance','attendance'),('shifts','attendance'),('leave_requests','leave')
    ) as x(tbl,mod)
  loop
    execute format('drop policy if exists %I on public.%I',item.tbl||'_member_select',item.tbl);
    execute format('drop policy if exists %I on public.%I',item.tbl||'_manager_insert',item.tbl);
    execute format('drop policy if exists %I on public.%I',item.tbl||'_manager_update',item.tbl);
    execute format('drop policy if exists %I on public.%I',item.tbl||'_admin_delete',item.tbl);
    execute format('create policy %I on public.%I for select to authenticated using (private.has_module_access(organization_id,%L,''read''))',item.tbl||'_access_select',item.tbl,item.mod);
    execute format('create policy %I on public.%I for insert to authenticated with check (private.has_module_access(organization_id,%L,''create''))',item.tbl||'_access_insert',item.tbl,item.mod);
    execute format('create policy %I on public.%I for update to authenticated using (private.has_module_access(organization_id,%L,''update'')) with check (private.has_module_access(organization_id,%L,''update''))',item.tbl||'_access_update',item.tbl,item.mod,item.mod);
    execute format('create policy %I on public.%I for delete to authenticated using (private.has_module_access(organization_id,%L,''delete''))',item.tbl||'_access_delete',item.tbl,item.mod);
  end loop;
end $$;
