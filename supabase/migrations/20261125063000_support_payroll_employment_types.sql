-- Preserve legacy employment types and support monthly/daily/hourly pay bases.
alter table public.employees drop constraint if exists employees_employment_type_check;
alter table public.employees add constraint employees_employment_type_check
check (employment_type = any(array['permanent','part_time','contract','temporary','monthly','daily','hourly']::text[]));
do $$
declare v_definition text;
begin
 v_definition:=pg_get_functiondef('public.create_storeflow_payroll(uuid,date,date,date)'::regprocedure);
 v_definition:=replace(v_definition,
  $old$in ('hourly','รายชั่วโมง')$old$,
  $new$in ('hourly','รายชั่วโมง','part_time')$new$);
 execute v_definition;
end $$;
