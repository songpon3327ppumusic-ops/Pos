-- Permit cascading deletion of draft payroll periods while keeping approved/paid items immutable.
create or replace function private.guard_storeflow_payroll_item_editability()
returns trigger language plpgsql set search_path=''
as $function$
declare v_period_id uuid; v_status text; v_org uuid;
begin
 if tg_op='DELETE' then v_period_id:=old.payroll_period_id; v_org:=old.organization_id;
 else v_period_id:=new.payroll_period_id; v_org:=new.organization_id; end if;
 select p.status into v_status from public.payroll_periods p where p.id=v_period_id and p.organization_id=v_org;
 if tg_op='DELETE' and v_status is null then return old; end if;
 if v_status is distinct from 'draft' then
  raise exception using errcode='55000',message='แก้ไขรายการเงินเดือนได้เฉพาะรอบฉบับร่าง';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$function$;
