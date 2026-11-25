-- One shift per employee/day matches the one-attendance-row-per-day model.
create unique index if not exists shifts_one_per_employee_day_idx on public.shifts(organization_id,employee_id,shift_date);
-- Clock-in is allowed only for the authenticated employee's assigned shift today, from 30 minutes before start until shift end.
create or replace function public.storeflow_clock_in(p_organization_id uuid,p_shift_id uuid default null::uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
 v_employee uuid; v_attendance uuid; v_shift public.shifts%rowtype;
 v_now timestamptz:=clock_timestamp(); v_day date:=(clock_timestamp() at time zone 'Asia/Bangkok')::date;
begin
 if (select auth.uid()) is null then raise exception using errcode='28000',message='Authentication required'; end if;
 if p_shift_id is null then raise exception using errcode='22004',message='ต้องเลือกกะงานที่ได้รับมอบหมาย'; end if;
 select id into v_employee from public.employees
 where organization_id=p_organization_id and user_id=(select auth.uid()) and is_active=true limit 1;
 if v_employee is null or not private.is_org_member(p_organization_id) then
  raise exception using errcode='42501',message='ไม่มีสิทธิ์ลงเวลาในร้านนี้';
 end if;
 select * into v_shift from public.shifts
 where id=p_shift_id and organization_id=p_organization_id and employee_id=v_employee and shift_date=v_day;
 if not found then raise exception using errcode='42501',message='ไม่พบกะงานของวันนี้ที่มอบหมายให้บัญชีนี้'; end if;
 if v_now < v_shift.starts_at-interval '30 minutes' then
  raise exception using errcode='42501',message='ยังไม่ถึงเวลาเริ่มลงเวลา (ลงได้ก่อนกะไม่เกิน 30 นาที)';
 end if;
 if v_now > v_shift.ends_at then raise exception using errcode='42501',message='กะงานสิ้นสุดแล้ว ไม่สามารถลงเวลาเข้างานย้อนหลังได้'; end if;
 insert into public.attendance(organization_id,employee_id,work_date,clock_in,shift_id,status)
 values(p_organization_id,v_employee,v_day,v_now,p_shift_id,'present')
 on conflict(organization_id,employee_id,work_date) do update
 set clock_in=case when public.attendance.clock_in is null then excluded.clock_in else public.attendance.clock_in end,
     shift_id=coalesce(excluded.shift_id,public.attendance.shift_id)
 returning id into v_attendance;
 if (select clock_in from public.attendance where id=v_attendance) <> v_now then
  raise exception using errcode='23505',message='วันนี้ลงเวลาเข้างานแล้ว';
 end if;
 if v_shift.starts_at < v_now then
  update public.attendance set late_minutes=greatest(0,ceil(extract(epoch from (v_now-v_shift.starts_at))/60)::int),
   is_late=(v_now > v_shift.starts_at+interval '5 minutes') where id=v_attendance;
 end if;
 return v_attendance;
end;
$function$;
revoke all on function public.storeflow_clock_in(uuid,uuid) from public,anon;
grant execute on function public.storeflow_clock_in(uuid,uuid) to authenticated;
