-- StoreFlow workforce + payroll hardening. Extends existing canonical tables in place.
begin;
alter table public.employees
 add column if not exists wage_rate numeric(12,2) not null default 0,
 add column if not exists position_allowance numeric(12,2) not null default 0,
 add column if not exists regular_allowance numeric(12,2) not null default 0,
 add column if not exists overtime_hourly_rate numeric(12,2) not null default 0,
 add column if not exists bank_account_name text,
 add column if not exists bank_account_number text,
 add column if not exists bank_name text;
alter table public.shifts add column if not exists shift_name text not null default 'กะงาน', add column if not exists break_minutes integer not null default 0, add column if not exists notes text;
alter table public.attendance add column if not exists shift_id uuid references public.shifts(id) on delete set null, add column if not exists worked_minutes integer not null default 0, add column if not exists is_late boolean not null default false, add column if not exists is_absent boolean not null default false, add column if not exists notes text;
alter table public.payroll_items add column if not exists regular_hours numeric(10,2) not null default 0, add column if not exists overtime_hours numeric(10,2) not null default 0, add column if not exists days_worked numeric(10,2) not null default 0, add column if not exists employee_name_snapshot text, add column if not exists payment_note text;
create unique index if not exists attendance_org_employee_day_uq on public.attendance(organization_id,employee_id,work_date);
create index if not exists shifts_org_date_idx on public.shifts(organization_id,shift_date);
create index if not exists attendance_org_date_idx on public.attendance(organization_id,work_date desc);
create index if not exists payroll_items_org_employee_idx on public.payroll_items(organization_id,employee_id);

drop policy if exists workforce_attendance_visibility on public.attendance;
create policy workforce_attendance_visibility on public.attendance as restrictive for select to authenticated using (
 exists(select 1 from public.employees e where e.id=attendance.employee_id and e.organization_id=attendance.organization_id and e.user_id=(select auth.uid()))
 or exists(select 1 from public.organization_members m where m.organization_id=attendance.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin','manager','hr'))
);
drop policy if exists workforce_shifts_visibility on public.shifts;
create policy workforce_shifts_visibility on public.shifts as restrictive for select to authenticated using (
 exists(select 1 from public.employees e where e.id=shifts.employee_id and e.organization_id=shifts.organization_id and e.user_id=(select auth.uid()))
 or exists(select 1 from public.organization_members m where m.organization_id=shifts.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin','manager','hr'))
);
drop policy if exists workforce_payroll_items_visibility on public.payroll_items;
create policy workforce_payroll_items_visibility on public.payroll_items as restrictive for select to authenticated using (
 exists(select 1 from public.employees e where e.id=payroll_items.employee_id and e.organization_id=payroll_items.organization_id and e.user_id=(select auth.uid()))
 or exists(select 1 from public.organization_members m where m.organization_id=payroll_items.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin','hr','accountant'))
);
drop policy if exists payroll_periods_owner_write_guard on public.payroll_periods;
create policy payroll_periods_owner_write_guard on public.payroll_periods as restrictive for all to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin')))
with check(exists(select 1 from public.organization_members m where m.organization_id=payroll_periods.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin')));
drop policy if exists payroll_items_owner_write_guard on public.payroll_items;
create policy payroll_items_owner_write_guard on public.payroll_items as restrictive for all to authenticated
using(exists(select 1 from public.organization_members m where m.organization_id=payroll_items.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin')))
with check(exists(select 1 from public.organization_members m where m.organization_id=payroll_items.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin')));

create or replace function public.create_storeflow_payroll(p_organization_id uuid,p_period_start date,p_period_end date,p_pay_date date)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=(select auth.uid()); v_period_id uuid;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required'; end if;
 if p_period_start is null or p_period_end is null or p_period_end<p_period_start then raise exception using errcode='22007',message='ช่วงวันที่เงินเดือนไม่ถูกต้อง'; end if;
 if not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active' and m.role in ('owner','admin')) then raise exception using errcode='42501',message='เฉพาะเจ้าของร้านหรือผู้ดูแลเท่านั้น'; end if;
 if not private.has_active_store_license(p_organization_id) then raise exception using errcode='42501',message='แพ็กเกจร้านค้าไม่อนุญาตให้สร้างรายการเงินเดือน'; end if;
 insert into public.payroll_periods(organization_id,period_start,period_end,pay_date,status) values(p_organization_id,p_period_start,p_period_end,p_pay_date,'draft') returning id into v_period_id;
 insert into public.payroll_items(organization_id,payroll_period_id,employee_id,base_pay,allowances,overtime_pay,commission,bonus,deductions,tax,social_security,net_pay,regular_hours,overtime_hours,days_worked,employee_name_snapshot)
 select p_organization_id,v_period_id,e.id,
 case when lower(coalesce(e.employment_type,'monthly')) in ('daily','รายวัน') then coalesce(nullif(e.wage_rate,0),e.base_salary,0)*coalesce(a.days_worked,0)
 when lower(coalesce(e.employment_type,'monthly')) in ('hourly','รายชั่วโมง') then coalesce(nullif(e.wage_rate,0),e.base_salary,0)*coalesce(a.regular_hours,0) else coalesce(e.base_salary,0) end,
 coalesce(e.position_allowance,0)+coalesce(e.regular_allowance,0),coalesce(e.overtime_hourly_rate,0)*coalesce(a.overtime_hours,0),0,0,0,0,0,
 greatest(0,(case when lower(coalesce(e.employment_type,'monthly')) in ('daily','รายวัน') then coalesce(nullif(e.wage_rate,0),e.base_salary,0)*coalesce(a.days_worked,0) when lower(coalesce(e.employment_type,'monthly')) in ('hourly','รายชั่วโมง') then coalesce(nullif(e.wage_rate,0),e.base_salary,0)*coalesce(a.regular_hours,0) else coalesce(e.base_salary,0) end)+coalesce(e.position_allowance,0)+coalesce(e.regular_allowance,0)+coalesce(e.overtime_hourly_rate,0)*coalesce(a.overtime_hours,0)),
 coalesce(a.regular_hours,0),coalesce(a.overtime_hours,0),coalesce(a.days_worked,0),e.full_name
 from public.employees e left join lateral (
 select round(sum(greatest(0,coalesce(at.worked_minutes,0)-coalesce(s.break_minutes,0)))/60.0,2) regular_hours,
 round(sum(coalesce(at.overtime_minutes,0))/60.0,2) overtime_hours,count(*) filter(where at.clock_in is not null) days_worked
 from public.attendance at left join public.shifts s on s.id=at.shift_id and s.organization_id=at.organization_id
 where at.organization_id=e.organization_id and at.employee_id=e.id and at.work_date between p_period_start and p_period_end
 ) a on true where e.organization_id=p_organization_id and e.is_active;
 if not exists(select 1 from public.payroll_items i where i.payroll_period_id=v_period_id and i.organization_id=p_organization_id) then raise exception using errcode='P0001',message='ไม่พบพนักงานที่เปิดใช้งาน'; end if;
 return v_period_id;
end; $$;
revoke all on function public.create_storeflow_payroll(uuid,date,date,date) from public,anon;
grant execute on function public.create_storeflow_payroll(uuid,date,date,date) to authenticated;

create or replace function public.storeflow_clock_in(p_organization_id uuid,p_shift_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_employee uuid; v_id uuid; v_shift public.shifts%rowtype; v_now timestamptz:=clock_timestamp(); v_day date:=(clock_timestamp() at time zone 'Asia/Bangkok')::date; v_old timestamptz;
begin
 select id into v_employee from public.employees where organization_id=p_organization_id and user_id=(select auth.uid()) and is_active limit 1;
 if v_employee is null or not private.is_org_member(p_organization_id) then raise exception using errcode='42501',message='ไม่มีบัญชีพนักงานที่ผูกกับผู้ใช้นี้'; end if;
 if p_shift_id is not null then select * into v_shift from public.shifts where id=p_shift_id and organization_id=p_organization_id and employee_id=v_employee; if not found then raise exception using errcode='42501',message='ไม่พบกะงานของพนักงานนี้'; end if; end if;
 insert into public.attendance(organization_id,employee_id,work_date,clock_in,shift_id,status) values(p_organization_id,v_employee,v_day,v_now,p_shift_id,'present')
 on conflict(organization_id,employee_id,work_date) do update set clock_in=coalesce(public.attendance.clock_in,excluded.clock_in),shift_id=coalesce(excluded.shift_id,public.attendance.shift_id) returning id,clock_in into v_id,v_old;
 if v_old is distinct from v_now then raise exception using errcode='23505',message='วันนี้ลงเวลาเข้างานแล้ว'; end if;
 if p_shift_id is not null then update public.attendance set late_minutes=greatest(0,ceil(extract(epoch from(v_now-v_shift.starts_at))/60)::int),is_late=(v_now>v_shift.starts_at+interval '5 minutes') where id=v_id; end if;
 return v_id;
end; $$;
create or replace function public.storeflow_clock_out(p_organization_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_employee uuid; v_id uuid; v_in timestamptz; v_shift_id uuid; v_end timestamptz:=clock_timestamp(); v_work int; v_shift_end timestamptz;
begin
 select id into v_employee from public.employees where organization_id=p_organization_id and user_id=(select auth.uid()) and is_active limit 1;
 if v_employee is null or not private.is_org_member(p_organization_id) then raise exception using errcode='42501',message='ไม่มีสิทธิ์ลงเวลาในร้านนี้'; end if;
 select id,clock_in,shift_id into v_id,v_in,v_shift_id from public.attendance where organization_id=p_organization_id and employee_id=v_employee and work_date=(clock_timestamp() at time zone 'Asia/Bangkok')::date and clock_out is null for update;
 if v_id is null or v_in is null then raise exception using errcode='P0001',message='ไม่พบรายการเข้างานที่ยังไม่ออกกะ'; end if;
 v_work:=greatest(0,ceil(extract(epoch from(v_end-v_in))/60)::int);
 if v_shift_id is not null then select ends_at into v_shift_end from public.shifts where id=v_shift_id; end if;
 update public.attendance set clock_out=v_end,worked_minutes=v_work,overtime_minutes=case when v_shift_end is null then 0 else greatest(0,v_work-ceil(extract(epoch from(v_shift_end-v_in))/60)::int) end where id=v_id;
 return v_id;
end; $$;
revoke all on function public.storeflow_clock_in(uuid,uuid) from public,anon;
revoke all on function public.storeflow_clock_out(uuid) from public,anon;
grant execute on function public.storeflow_clock_in(uuid,uuid) to authenticated;
grant execute on function public.storeflow_clock_out(uuid) to authenticated;
commit;