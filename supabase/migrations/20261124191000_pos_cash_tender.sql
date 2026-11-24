begin;
alter table public.sales add column if not exists cash_received numeric(12,2);
alter table public.sales add column if not exists change_due numeric(12,2) not null default 0;
drop function if exists public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid);
create function public.checkout_sale_idempotent(
 p_organization_id uuid,p_items jsonb,p_payment_method text,p_discount numeric default 0,
 p_tax numeric default 0,p_customer_id uuid default null,p_idempotency_key uuid default null,
 p_cash_received numeric default null
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,auth,private as $$
declare v_user uuid:=auth.uid(); v_sale uuid; v_existing uuid; v_total numeric(12,2); v_payment text:=coalesce(nullif(trim(p_payment_method),''),'cash');
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if p_idempotency_key is null then raise exception 'Idempotency key is required'; end if;
 if not private.is_org_member(p_organization_id) then raise exception 'Not an active store member'; end if;
 if lower(v_payment) in ('เงินสด','cash') and (p_cash_received is null or p_cash_received<0) then raise exception 'Cash received amount is required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':'||p_idempotency_key::text,0));
 select sale_id into v_existing from private.pos_order_idempotency where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
 if v_existing is not null then return v_existing; end if;
 insert into private.pos_order_idempotency(organization_id,idempotency_key,created_by) values(p_organization_id,p_idempotency_key,v_user) on conflict do nothing;
 v_sale:=public.checkout_sale(p_organization_id,p_items,v_payment,p_discount,p_tax,p_customer_id);
 select total into v_total from public.sales where id=v_sale and organization_id=p_organization_id;
 if lower(v_payment) in ('เงินสด','cash') then
  if p_cash_received<v_total then raise exception 'Cash received is less than sale total'; end if;
  update public.sales set cash_received=p_cash_received,change_due=round(p_cash_received-v_total,2) where id=v_sale and organization_id=p_organization_id;
 else
  update public.sales set cash_received=null,change_due=0 where id=v_sale and organization_id=p_organization_id;
 end if;
 update private.pos_order_idempotency set sale_id=v_sale where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
 return v_sale;
end; $$;
revoke all on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric) from public,anon;
grant execute on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric) to authenticated;
commit;