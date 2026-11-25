do $$
declare v_def text;
begin
 v_def:=pg_get_functiondef('public.create_pos_sale_with_payment(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric,numeric,text,text,text,text)'::regprocedure);
 v_def:=replace(v_def,$old$if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระเงิน';end if;$old$,$new$if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระเงิน';end if;
 if not private.has_module_access(p_organization_id,'orders','create') then raise exception using errcode='42501',message='ไม่มีสิทธิ์สร้างรายการขาย';end if;$new$);
 if position('has_module_access(p_organization_id,''orders'',''create'')' in v_def)=0 then raise exception 'Could not harden POS checkout module permission';end if;
 execute v_def;
 v_def:=pg_get_functiondef('public.confirm_pos_payment(uuid,uuid,text,text)'::regprocedure);
 v_def:=replace(v_def,$old$if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์ยืนยันการชำระเงิน';end if;$old$,$new$if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์ยืนยันการชำระเงิน';end if;
 if not private.has_module_access(p_organization_id,'orders','create') then raise exception using errcode='42501',message='ไม่มีสิทธิ์ยืนยันการชำระเงิน';end if;$new$);
 if position('has_module_access(p_organization_id,''orders'',''create'')' in v_def)=0 then raise exception 'Could not harden payment confirmation module permission';end if;
 execute v_def;
 v_def:=pg_get_functiondef('public.record_customer_credit_payment(uuid,uuid,numeric,text,text)'::regprocedure);
 v_def:=replace(v_def,$old$if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระหนี้';end if;$old$,$new$if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระหนี้';end if;
 if not private.has_module_access(p_organization_id,'orders','create') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระหนี้';end if;$new$);
 if position('has_module_access(p_organization_id,''orders'',''create'')' in v_def)=0 then raise exception 'Could not harden credit settlement module permission';end if;
 execute v_def;
 v_def:=pg_get_functiondef('public.adjust_stock(uuid,uuid,numeric,text)'::regprocedure);
 v_def:=replace(v_def,$old$if v_role is null or v_role not in ('owner','admin','manager') then raise exception 'You do not have permission to adjust stock'; end if;$old$,$new$if v_role is null or v_role not in ('owner','admin','manager') then raise exception 'You do not have permission to adjust stock'; end if;
 if not private.has_module_access(p_organization_id,'inventory','update') then raise exception 'You do not have permission to adjust stock'; end if;$new$);
 if position('has_module_access(p_organization_id,''inventory'',''update'')' in v_def)=0 then raise exception 'Could not harden stock adjustment module permission';end if;
 execute v_def;
end $$;
