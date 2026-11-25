-- Payroll net_pay is a generated column; do not insert/update it explicitly.
-- Reject duplicate payroll periods and validate owner/admin before creating the batch.
create or replace function public.create_storeflow_payroll(
 p_organization_id uuid,p_period_start date,p_period_end date,p_pay_date date
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_user uuid := (select auth.uid()); v_period_id uuid;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required'; end if;
 if p_organization_id is null or p_period_start is null or p_period_end is null or p_period_end<p_period_start then
  raise exception using errcode='22007',message='ช่วงวันที่เงินเดือนไม่ถูกต้อง';
 end if;
 if not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active=true and m.membership_status='active' and m.role in ('owner','admin')) then
  raise exception using errcode='42501',message='เฉพาะเจ้าของร้านหรือผู้ดูแลที่ได้รับอนุญาตเท่านั้น';
 end if;
 if not private.has_active_store_license(p_organization_id) then
  raise exception using errcode='42501',message='แพ็กเกจร้านค้าไม่อนุญาตให้สร้างรายการเงินเดือน';
 end if;
 if exists(select 1 from public.payroll_periods p where p.organization_id=p_organization_id and p.period_start=p_period_start and p.period_end=p_period_end) then
  raise exception using errcode='23505',message='มีรอบเงินเดือนช่วงวันที่นี้แล้ว';
 end if;
 insert into public.payroll_periods(organization_id,period_start,period_end,pay_date,status)
 values(p_organization_id,p_period_start,p_period_end,p_pay_date,'draft') returning id into v_period_id;
 insert into public.payroll_items(
  organization_id,payroll_period_id,employee_id,base_pay,allowances,overtime_pay,
  commission,bonus,deductions,tax,social_security,regular_hours,overtime_hours,
  days_worked,employee_name_snapshot
 )
 select p_organization_id,v_period_id,e.id,
  case
   when lower(coalesce(e.employment_type,'monthly')) in ('daily','รายวัน') then coalesce(nullif(e.wage_rate,0),e.base_salary,0)*coalesce(a.days_worked,0)
   when lower(coalesce(e.employment_type,'monthly')) in ('hourly','รายชั่วโมง') then coalesce(nullif(e.wage_rate,0),e.base_salary,0)*coalesce(a.regular_hours,0)
   else coalesce(e.base_salary,0)
  end,
  coalesce(e.position_allowance,0)+coalesce(e.regular_allowance,0),
  coalesce(e.overtime_hourly_rate,0)*coalesce(a.overtime_hours,0),
  0,0,0,0,0,coalesce(a.regular_hours,0),coalesce(a.overtime_hours,0),coalesce(a.days_worked,0),e.full_name
 from public.employees e
 left join lateral (
  select round(coalesce(sum(greatest(0,coalesce(at.worked_minutes,0)-coalesce(s.break_minutes,0))),0)/60.0,2) as regular_hours,
   round(coalesce(sum(coalesce(at.overtime_minutes,0)),0)/60.0,2) as overtime_hours,
   count(*) filter(where at.clock_in is not null) as days_worked
  from public.attendance at
  left join public.shifts s on s.id=at.shift_id and s.organization_id=at.organization_id
  where at.organization_id=e.organization_id and at.employee_id=e.id and at.work_date between p_period_start and p_period_end
 ) a on true
 where e.organization_id=p_organization_id and e.is_active=true;
 if not exists(select 1 from public.payroll_items i where i.payroll_period_id=v_period_id and i.organization_id=p_organization_id) then
  raise exception using errcode='P0001',message='ไม่พบพนักงานที่เปิดใช้งานในร้านนี้';
 end if;
 return v_period_id;
end;
$function$;
revoke all on function public.create_storeflow_payroll(uuid,date,date,date) from public,anon;
grant execute on function public.create_storeflow_payroll(uuid,date,date,date) to authenticated;
