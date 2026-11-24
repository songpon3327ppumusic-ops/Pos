begin;
-- SECURITY DEFINER POS functions must enforce the license themselves because they bypass client RLS.
create or replace function public.checkout_sale_idempotent(
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
 if not private.has_active_store_license(p_organization_id) then raise exception 'Store subscription expired. Renew the plan to resume POS sales.'; end if;
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

create or replace function public.adjust_stock(p_organization_id uuid,p_product_id uuid,p_quantity_delta numeric,p_note text default null)
returns numeric language plpgsql security definer
set search_path=public,auth,private as $$
declare v_user uuid:=auth.uid(); v_role text; v_product public.products%rowtype; v_new_stock numeric(12,3);
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if not private.is_org_member(p_organization_id) then raise exception 'Not an active store member'; end if;
 if not private.has_active_store_license(p_organization_id) then raise exception 'Store subscription expired. Renew the plan to adjust stock.'; end if;
 if p_quantity_delta=0 then raise exception 'Stock adjustment cannot be zero'; end if;
 select role into v_role from public.organization_members where organization_id=p_organization_id and user_id=v_user and is_active and membership_status='active';
 if v_role is null or v_role not in ('owner','admin','manager') then raise exception 'You do not have permission to adjust stock'; end if;
 select * into v_product from public.products where id=p_product_id and organization_id=p_organization_id for update;
 if not found then raise exception 'Product not found'; end if;
 v_new_stock:=v_product.stock+p_quantity_delta;
 if v_new_stock<0 then raise exception 'Stock cannot be negative'; end if;
 update public.products set stock=v_new_stock,updated_at=now() where id=p_product_id and organization_id=p_organization_id;
 insert into public.stock_movements(organization_id,product_id,movement_type,quantity_delta,note,created_by)
 values(p_organization_id,p_product_id,'adjustment',p_quantity_delta,p_note,v_user);
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(p_organization_id,v_user,'stock_adjustment','product',p_product_id::text,jsonb_build_object('delta',p_quantity_delta,'new_stock',v_new_stock,'note',p_note));
 return v_new_stock;
end; $$;

-- The public API must use the idempotent, license-aware checkout wrapper only.
revoke all on function public.checkout_sale(uuid,jsonb,text,numeric,numeric,uuid) from public,anon,authenticated;
revoke all on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric) from public,anon;
grant execute on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric) to authenticated;
commit;