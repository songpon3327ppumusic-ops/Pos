-- Enforce payroll approval/paid immutability at the database layer.
create or replace function private.guard_storeflow_payroll_period()
returns trigger language plpgsql set search_path=''
as $function$
begin
 if tg_op='DELETE' then
  if old.status<>'draft' then raise exception using errcode='55000',message='ลบรอบเงินเดือนที่อนุมัติหรือจ่ายแล้วไม่ได้'; end if;
  return old;
 end if;
 if tg_op='UPDATE' then
  if old.status='draft' and new.status not in ('draft','approved') then
   raise exception using errcode='55000',message='รอบเงินเดือนต้องอนุมัติก่อนจึงจะบันทึกจ่ายได้';
  elsif old.status='approved' and new.status not in ('approved','paid') then
   raise exception using errcode='55000',message='รอบเงินเดือนที่อนุมัติแล้วเปลี่ยนสถานะย้อนกลับไม่ได้';
  elsif old.status='paid' and new.status<>'paid' then
   raise exception using errcode='55000',message='รอบเงินเดือนที่จ่ายแล้วแก้สถานะไม่ได้';
  end if;
  if old.status<>'draft' and (new.period_start is distinct from old.period_start or new.period_end is distinct from old.period_end or new.pay_date is distinct from old.pay_date) then
   raise exception using errcode='55000',message='แก้ไขช่วงรอบเงินเดือนหลังอนุมัติไม่ได้';
  end if;
  return new;
 end if;
 return new;
end;
$function$;
drop trigger if exists trg_guard_storeflow_payroll_period on public.payroll_periods;
create trigger trg_guard_storeflow_payroll_period before update or delete on public.payroll_periods
for each row execute function private.guard_storeflow_payroll_period();

create or replace function private.guard_storeflow_payroll_item_editability()
returns trigger language plpgsql set search_path=''
as $function$
declare v_period_id uuid; v_status text; v_org uuid;
begin
 if tg_op='DELETE' then v_period_id:=old.payroll_period_id; v_org:=old.organization_id;
 else v_period_id:=new.payroll_period_id; v_org:=new.organization_id; end if;
 select p.status into v_status from public.payroll_periods p where p.id=v_period_id and p.organization_id=v_org;
 if v_status is distinct from 'draft' then
  raise exception using errcode='55000',message='แก้ไขรายการเงินเดือนได้เฉพาะรอบฉบับร่าง';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$function$;
drop trigger if exists trg_guard_storeflow_payroll_item_editability on public.payroll_items;
create trigger trg_guard_storeflow_payroll_item_editability before insert or update or delete on public.payroll_items
for each row execute function private.guard_storeflow_payroll_item_editability();
