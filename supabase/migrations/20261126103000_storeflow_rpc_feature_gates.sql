-- Enforce plan permissions inside SECURITY DEFINER RPCs.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.create_storeflow_payroll(uuid,date,date,date)'::regprocedure) into v_def;
  if position('storeflow_has_feature' in v_def)=0 then
    v_def:=replace(v_def,
      'if not private.has_active_store_license(p_organization_id) then raise exception using errcode=''42501'',message=''แพ็กเกจร้านค้าไม่อนุญาตให้สร้างรายการเงินเดือน''; end if;',
      'if not private.storeflow_has_feature(p_organization_id,''payroll_auto'') then raise exception using errcode=''42501'',message=''ฟีเจอร์คำนวณเงินเดือนต้องใช้แพ็กเกจ Premium''; end if;'||E'\n  '||
      'if not private.has_active_store_license(p_organization_id) then raise exception using errcode=''42501'',message=''แพ็กเกจร้านค้าไม่อนุญาตให้สร้างรายการเงินเดือน''; end if;');
    execute v_def;
  end if;
  select pg_get_functiondef('public.storeflow_clock_in(uuid,uuid)'::regprocedure) into v_def;
  if position('storeflow_has_feature' in v_def)=0 then
    v_def:=replace(v_def,
      'if p_shift_id is null then raise exception using errcode=''22004'',message=''ต้องเลือกกะงานที่ได้รับมอบหมาย''; end if;',
      'if not private.storeflow_has_feature(p_organization_id,''attendance'') then raise exception using errcode=''42501'',message=''กะงานและลงเวลาต้องใช้แพ็กเกจ Standard ขึ้นไป''; end if;'||E'\n '||
      'if p_shift_id is null then raise exception using errcode=''22004'',message=''ต้องเลือกกะงานที่ได้รับมอบหมาย''; end if;');
    execute v_def;
  end if;
  select pg_get_functiondef('public.storeflow_clock_out(uuid)'::regprocedure) into v_def;
  if position('storeflow_has_feature' in v_def)=0 then
    v_def:=replace(v_def,
      'select id into v_employee from public.employees',
      'if not private.storeflow_has_feature(p_organization_id,''attendance'') then raise exception using errcode=''42501'',message=''กะงานและลงเวลาต้องใช้แพ็กเกจ Standard ขึ้นไป''; end if;'||E'\n '||
      'select id into v_employee from public.employees');
    execute v_def;
  end if;
end $$;