-- Payroll regular hours exclude approved overtime minutes to avoid paying OT twice.
do $$
declare v_definition text;
begin
 v_definition:=pg_get_functiondef('public.create_storeflow_payroll(uuid,date,date,date)'::regprocedure);
 v_definition:=replace(v_definition,
  $old$sum(greatest(0,coalesce(at.worked_minutes,0)-coalesce(s.break_minutes,0)))$old$,
  $new$sum(greatest(0,coalesce(at.worked_minutes,0)-coalesce(s.break_minutes,0)-coalesce(at.overtime_minutes,0)))$new$);
 execute v_definition;
end $$;

alter table public.payroll_items
 add constraint payroll_items_amounts_nonnegative check (base_pay>=0 and allowances>=0 and overtime_pay>=0 and commission>=0 and bonus>=0 and deductions>=0 and tax>=0 and social_security>=0 and net_pay>=0) not valid;
alter table public.shifts
 add constraint shifts_valid_duration_and_break check (ends_at>starts_at and break_minutes between 0 and 480) not valid;
alter table public.attendance
 add constraint attendance_minutes_nonnegative check (worked_minutes>=0 and overtime_minutes>=0 and late_minutes>=0) not valid;
alter table public.payroll_items validate constraint payroll_items_amounts_nonnegative;
alter table public.shifts validate constraint shifts_valid_duration_and_break;
alter table public.attendance validate constraint attendance_minutes_nonnegative;
