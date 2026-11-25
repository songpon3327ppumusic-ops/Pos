-- Serialize payroll creation per organization to prevent concurrent duplicate periods.
create index if not exists payroll_periods_org_date_lookup_idx on public.payroll_periods(organization_id,period_start,period_end);
do $$
declare v_definition text;
begin
 v_definition:=pg_get_functiondef('public.create_storeflow_payroll(uuid,date,date,date)'::regprocedure);
 v_definition:=replace(v_definition,
  $old$if exists(select 1 from public.payroll_periods p where p.organization_id=p_organization_id and p.period_start=p_period_start and p.period_end=p_period_end) then$old$,
  $new$perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text,0));
 if exists(select 1 from public.payroll_periods p where p.organization_id=p_organization_id and p.period_start=p_period_start and p.period_end=p_period_end) then$new$);
 execute v_definition;
end $$;

-- Enable Realtime for workforce tables used by the StoreFlow client.
do $$
declare t text;
begin
 foreach t in array array['shifts','attendance','payroll_items'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;
