-- Calculate overtime only after the scheduled shift end; early clock-in does not become overtime.
create or replace function public.storeflow_clock_out(p_organization_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
 v_employee uuid; v_attendance uuid; v_in timestamptz; v_shift_id uuid;
 v_shift public.shifts%rowtype; v_out timestamptz:=clock_timestamp();
 v_work int; v_ot int:=0;
begin
 select id into v_employee from public.employees
 where organization_id=p_organization_id and user_id=(select auth.uid()) and is_active=true limit 1;
 if v_employee is null or not private.is_org_member(p_organization_id) then
  raise exception using errcode='42501',message='ไม่มีสิทธิ์ลงเวลาในร้านนี้';
 end if;
 select id,clock_in,shift_id into v_attendance,v_in,v_shift_id from public.attendance
 where organization_id=p_organization_id and employee_id=v_employee
 and work_date=(clock_timestamp() at time zone 'Asia/Bangkok')::date and clock_out is null
 for update;
 if v_attendance is null or v_in is null then
  raise exception using errcode='P0001',message='ไม่พบรายการเข้างานที่ยังไม่ออกกะ';
 end if;
 v_work:=greatest(0,ceil(extract(epoch from (v_out-v_in))/60)::int);
 if v_shift_id is not null then
  select * into v_shift from public.shifts where id=v_shift_id and organization_id=p_organization_id and employee_id=v_employee;
  if not found then raise exception using errcode='23503',message='ไม่พบกะงานที่ผูกกับรายการลงเวลา'; end if;
  v_ot:=greatest(0,ceil(extract(epoch from (v_out-v_shift.ends_at))/60)::int);
 end if;
 update public.attendance set clock_out=v_out,worked_minutes=v_work,overtime_minutes=v_ot where id=v_attendance;
 return v_attendance;
end;
$function$;
revoke all on function public.storeflow_clock_out(uuid) from public,anon;
grant execute on function public.storeflow_clock_out(uuid) to authenticated;
