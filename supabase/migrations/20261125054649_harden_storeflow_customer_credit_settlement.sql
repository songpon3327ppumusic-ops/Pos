create unique index if not exists customer_credit_charge_sale_uidx on public.customer_credit_ledger(organization_id,sale_id) where entry_type='charge' and sale_id is not null;

do $$
declare v_def text;
begin
 v_def:=pg_get_functiondef('public.create_pos_sale_with_payment(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric,numeric,text,text,text,text)'::regprocedure);
 v_def:=replace(v_def,
 $old$  insert into public.customer_credit_ledger(organization_id,customer_id,sale_id,entry_type,amount,notes,created_by)
  values(p_organization_id,p_customer_id,v_sale,'charge',v_total,'ยอดขายเชื่อ '|| (select receipt_no from public.sales where id=v_sale),v_user);
  update public.customers set credit_balance=coalesce(credit_balance,0)+v_total where id=p_customer_id and organization_id=p_organization_id;$old$,
 $new$  insert into public.customer_credit_ledger(organization_id,customer_id,sale_id,entry_type,amount,notes,created_by)
  values(p_organization_id,p_customer_id,v_sale,'charge',v_total,'ยอดขายเชื่อ '|| (select receipt_no from public.sales where id=v_sale),v_user)
  on conflict do nothing;
  if found then update public.customers set credit_balance=coalesce(credit_balance,0)+v_total where id=p_customer_id and organization_id=p_organization_id; end if;$new$);
 if position('on conflict do nothing' in v_def)=0 then raise exception 'Could not patch idempotent credit ledger';end if;
 execute v_def;
end $$;

create or replace function public.record_customer_credit_payment(p_organization_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_payment_ref text default null)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=(select auth.uid());v_role text;v_balance numeric(12,2);v_cash_enabled boolean;v_remaining numeric(12,2);v_due numeric(12,2);v_apply numeric(12,2);v_sale record;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required';end if;
 select m.role into v_role from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active';
 if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception using errcode='42501',message='ไม่มีสิทธิ์รับชำระหนี้';end if;
 if p_payment_method not in ('เงินสด','cash') then raise exception using errcode='22023',message='การรับชำระหนี้ผ่านระบบนี้รองรับเงินสดเท่านั้น กรุณายืนยันยอดโอนแยกก่อน';end if;
 select coalesce(cash_enabled,false) into v_cash_enabled from public.store_payment_settings where organization_id=p_organization_id;
 if not coalesce(v_cash_enabled,true) then raise exception using errcode='55000',message='ร้านปิดรับชำระเงินสด';end if;
 select credit_balance into v_balance from public.customers where id=p_customer_id and organization_id=p_organization_id for update;
 if not found then raise exception using errcode='23503',message='ไม่พบลูกค้าในร้านนี้';end if;
 if p_amount is null or p_amount<=0 or p_amount>v_balance then raise exception using errcode='22023',message='ยอดรับชำระไม่ถูกต้อง';end if;
 v_remaining:=round(p_amount,2);
 for v_sale in select id,total,coalesce(amount_tendered,0) as paid from public.sales where organization_id=p_organization_id and customer_id=p_customer_id and payment_status in ('unpaid','partial') order by created_at,id for update loop
  exit when v_remaining<=0;v_due:=greatest(0,round(v_sale.total-v_sale.paid,2));v_apply:=least(v_remaining,v_due);
  if v_apply>0 then update public.sales set amount_tendered=coalesce(amount_tendered,0)+v_apply,payment_status=case when coalesce(amount_tendered,0)+v_apply>=total then 'paid' else 'partial' end,paid_at=case when coalesce(amount_tendered,0)+v_apply>=total then now() else null end where id=v_sale.id and organization_id=p_organization_id;
   insert into public.customer_credit_ledger(organization_id,customer_id,sale_id,entry_type,amount,payment_method,payment_ref,notes,created_by) values(p_organization_id,p_customer_id,v_sale.id,'payment',v_apply,'เงินสด',p_payment_ref,'รับชำระยอดขายเชื่อ',v_user);v_remaining:=v_remaining-v_apply;end if;
 end loop;
 if v_remaining>0 then insert into public.customer_credit_ledger(organization_id,customer_id,entry_type,amount,payment_method,payment_ref,notes,created_by) values(p_organization_id,p_customer_id,'payment',v_remaining,'เงินสด',p_payment_ref,'รับชำระยอดค้างเดิม',v_user);end if;
 update public.customers set credit_balance=greatest(0,credit_balance-p_amount) where id=p_customer_id and organization_id=p_organization_id;
end;$function$;
revoke all on function public.record_customer_credit_payment(uuid,uuid,numeric,text,text) from public,anon;
grant execute on function public.record_customer_credit_payment(uuid,uuid,numeric,text,text) to authenticated;