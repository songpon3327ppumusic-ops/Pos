-- Employee self-service payslips: only their own approved/paid payroll rows are returned.
create or replace function public.get_my_storeflow_pay_slips(p_organization_id uuid)
returns table(
 period_id uuid,period_start date,period_end date,pay_date date,period_status text,
 base_pay numeric,allowances numeric,overtime_pay numeric,commission numeric,bonus numeric,
 deductions numeric,tax numeric,social_security numeric,net_pay numeric,
 regular_hours numeric,overtime_hours numeric,days_worked numeric,employee_name text
)
language plpgsql stable security definer set search_path=''
as $function$
declare v_user uuid := (select auth.uid());
begin
 if v_user is null or not private.is_org_member(p_organization_id) then
  raise exception using errcode='42501',message='ไม่มีสิทธิ์ดูสลิปเงินเดือน';
 end if;
 if not exists(select 1 from public.employees e where e.organization_id=p_organization_id and e.user_id=v_user and e.is_active=true) then
  raise exception using errcode='42501',message='บัญชีนี้ยังไม่ได้ผูกกับทะเบียนพนักงาน';
 end if;
 return query
 select p.id,p.period_start,p.period_end,p.pay_date,p.status,
  i.base_pay,i.allowances,i.overtime_pay,i.commission,i.bonus,i.deductions,i.tax,i.social_security,i.net_pay,
  i.regular_hours,i.overtime_hours,i.days_worked,coalesce(i.employee_name_snapshot,e.full_name)
 from public.payroll_items i
 join public.payroll_periods p on p.id=i.payroll_period_id and p.organization_id=i.organization_id
 join public.employees e on e.id=i.employee_id and e.organization_id=i.organization_id
 where i.organization_id=p_organization_id and e.user_id=v_user and e.is_active=true
  and p.status in ('approved','paid')
 order by p.period_start desc;
end;
$function$;
revoke all on function public.get_my_storeflow_pay_slips(uuid) from public,anon;
grant execute on function public.get_my_storeflow_pay_slips(uuid) to authenticated;
