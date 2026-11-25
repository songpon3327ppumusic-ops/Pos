do $$
declare v_def text;
begin
 v_def:=pg_get_functiondef('public.create_pos_sale_with_payment(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric,numeric,text,text,text,text)'::regprocedure);
 v_def:=replace(v_def,
 $old$ elsif v_method in ('stripe','stripe_card') then
  raise exception using errcode='0A000',message='ยังไม่ได้เชื่อมต่อ Stripe Connect สำหรับร้านนี้';$old$,
 $new$ elsif v_method in ('stripe','stripe_card') then
  v_method:='stripe_card';v_enabled:=coalesce(v_settings.stripe_enabled,false) and coalesce(v_settings.stripe_charges_enabled,false) and coalesce(v_settings.stripe_webhook_verified,false);v_status:='pending';v_sale_status:='pending_payment';$new$);
 v_def:=replace(v_def,$old$when v_method='card_edc' then 'บัตรเครดิต/เดบิต' else 'เงินเชื่อ' end,$old$,$new$when v_method='card_edc' then 'บัตรเครดิต/เดบิต' when v_method='stripe_card' then 'Stripe Online' else 'เงินเชื่อ' end,$new$);
 v_def:=replace(v_def,$old$when v_method='card_edc' then 'บัตรเครดิต/เดบิต (EDC)' else 'เงินเชื่อ' end,$old$,$new$when v_method='card_edc' then 'บัตรเครดิต/เดบิต (EDC)' when v_method='stripe_card' then 'Stripe Online' else 'เงินเชื่อ' end,$new$);
 if position('v_method:=''stripe_card''' in v_def)=0 or position('Stripe Online' in v_def)=0 then raise exception 'Could not enable Stripe card payment path';end if;
 execute v_def;
end $$;