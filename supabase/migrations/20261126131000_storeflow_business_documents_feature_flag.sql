do $$
declare v_def text;
begin
  select pg_get_functiondef('private.storeflow_has_feature(uuid,text)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    'when ''shifts'',''attendance'',''store_payment_qr'' then return v_plan=''standard'';',
    'when ''shifts'',''attendance'',''store_payment_qr'',''business_documents'' then return v_plan=''standard'';');
  execute v_def;
end $$;