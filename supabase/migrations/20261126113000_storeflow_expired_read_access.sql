-- Expired stores remain read-only: preserve historical module SELECT access.
do $$
declare v_def text;
begin
  select pg_get_functiondef('private.has_module_access(uuid,text,text)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    'if p_module in (''attendance'',''shifts'') and v_plan not in (''standard'',''premium'',''lifetime'') then',
    'if v_plan<>''expired'' and p_module in (''attendance'',''shifts'') and v_plan not in (''standard'',''premium'',''lifetime'') then');
  v_def:=replace(v_def,
    'if p_module=''payroll'' and v_plan not in (''premium'',''lifetime'') then',
    'if v_plan<>''expired'' and p_module=''payroll'' and v_plan not in (''premium'',''lifetime'') then');
  v_def:=replace(v_def,
    'if p_module in (''documents'',''tax_documents'',''business_documents'') and v_plan not in (''premium'',''lifetime'') then',
    'if v_plan<>''expired'' and p_module in (''documents'',''tax_documents'',''business_documents'') and v_plan not in (''premium'',''lifetime'') then');
  execute v_def;
end $$;