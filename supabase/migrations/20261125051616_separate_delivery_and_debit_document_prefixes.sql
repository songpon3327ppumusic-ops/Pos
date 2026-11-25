do $$
declare v_def text;
begin
 v_def:=pg_get_functiondef('public.next_business_document_number(uuid,text,text)'::regprocedure);
 v_def:=replace(v_def, 'when ''delivery_note'' then ''DN''', 'when ''delivery_note'' then ''DLV''');
 execute v_def;
end $$;