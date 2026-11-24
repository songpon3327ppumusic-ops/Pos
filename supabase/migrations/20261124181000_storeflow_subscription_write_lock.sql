-- Enforce subscription expiry at the database boundary while preserving read/export access.
begin;
create or replace function private.has_active_store_license(p_org uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select exists (
    select 1 from public.organization_subscriptions s
    where s.organization_id=p_org
      and (
        (s.plan_type='lifetime' and s.status='active')
        or (s.status='active' and (s.current_period_end is null or s.current_period_end>now()))
        or (s.status='trialing' and s.trial_ends_at>now())
      )
  );
$$;
revoke all on function private.has_active_store_license(uuid) from public, anon;
grant execute on function private.has_active_store_license(uuid) to authenticated;

do $$
declare t record;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    where c.table_schema='public' and c.column_name='organization_id'
      and c.table_name not in ('organization_members','organization_subscriptions','subscription_billing_events')
  loop
    execute format('drop policy if exists license_write_insert_%I on public.%I',t.table_name,t.table_name);
    execute format('drop policy if exists license_write_update_%I on public.%I',t.table_name,t.table_name);
    execute format('drop policy if exists license_write_delete_%I on public.%I',t.table_name,t.table_name);
    execute format('create policy license_write_insert_%I on public.%I as restrictive for insert to authenticated with check (private.has_active_store_license(organization_id))',t.table_name,t.table_name);
    execute format('create policy license_write_update_%I on public.%I as restrictive for update to authenticated using (private.has_active_store_license(organization_id)) with check (private.has_active_store_license(organization_id))',t.table_name,t.table_name);
    execute format('create policy license_write_delete_%I on public.%I as restrictive for delete to authenticated using (private.has_active_store_license(organization_id))',t.table_name,t.table_name);
  end loop;
end $$;
commit;
