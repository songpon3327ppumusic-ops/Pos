-- Isolate product cost data so cashier accounts cannot read purchase costs or margin.
begin;
create table if not exists public.product_costs (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  cost numeric(12,2) not null default 0 check (cost >= 0),
  updated_at timestamptz not null default now(),
  primary key (organization_id,product_id)
);
insert into public.product_costs(organization_id,product_id,cost)
select organization_id,id,cost from public.products
on conflict (organization_id,product_id) do update set cost=excluded.cost,updated_at=now();

alter table public.product_costs enable row level security;
drop policy if exists tenant_guard_product_costs on public.product_costs;
create policy tenant_guard_product_costs on public.product_costs as restrictive for all to authenticated
using (private.is_org_member(organization_id))
with check (private.is_org_member(organization_id));
create or replace function private.is_org_manager(p_org uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,auth
as $$
 select exists(select 1 from public.organization_members m
 where m.organization_id=p_org and m.user_id=(select auth.uid())
 and m.is_active and m.membership_status='active'
 and m.role in ('owner','admin','manager'));
$$;
revoke all on function private.is_org_manager(uuid) from public,anon;
grant execute on function private.is_org_manager(uuid) to authenticated;
create policy product_costs_select_managers on public.product_costs for select to authenticated using (private.is_org_manager(organization_id));
create policy product_costs_insert_managers on public.product_costs for insert to authenticated with check (private.is_org_manager(organization_id));
create policy product_costs_update_managers on public.product_costs for update to authenticated using (private.is_org_manager(organization_id)) with check (private.is_org_manager(organization_id));
create policy product_costs_delete_managers on public.product_costs for delete to authenticated using (private.is_org_manager(organization_id));
create policy product_costs_license_insert on public.product_costs as restrictive for insert to authenticated with check (private.has_active_store_license(organization_id));
create policy product_costs_license_update on public.product_costs as restrictive for update to authenticated using (private.has_active_store_license(organization_id)) with check (private.has_active_store_license(organization_id));
create policy product_costs_license_delete on public.product_costs as restrictive for delete to authenticated using (private.has_active_store_license(organization_id));

alter table public.products drop column if exists cost;

-- Keep cost snapshots in sale_items; only the trusted checkout routine reads product_costs.
create or replace function public.checkout_sale(
 p_organization_id uuid,p_items jsonb,p_payment_method text,
 p_discount numeric default 0,p_tax numeric default 0,p_customer_id uuid default null
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,auth,private
as $$
declare
 v_user uuid:=auth.uid(); v_role text; v_item jsonb; v_product public.products%rowtype;
 v_qty numeric(12,3); v_subtotal numeric(12,2):=0; v_total numeric(12,2);
 v_sale_id uuid; v_receipt text; v_cost numeric(12,2);
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Cart is empty'; end if;
 if exists(select 1 from (select value->>'product_id' product_id from jsonb_array_elements(p_items) group by value->>'product_id' having count(*)>1) d) then raise exception 'Duplicate products in cart'; end if;
 if coalesce(p_discount,0)<0 or coalesce(p_tax,0)<0 then raise exception 'Discount and tax must not be negative'; end if;
 if not private.is_org_member(p_organization_id) or not private.has_active_store_license(p_organization_id) then raise exception 'Store access is not active'; end if;
 select role into v_role from public.organization_members where organization_id=p_organization_id and user_id=v_user and is_active and membership_status='active';
 if v_role not in ('owner','admin','manager','cashier') then raise exception 'You do not have permission to create a sale'; end if;
 if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and organization_id=p_organization_id) then raise exception 'Customer does not belong to this store'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'quantity')::numeric;
  if v_qty<=0 then raise exception 'Quantity must be greater than zero'; end if;
  select * into v_product from public.products where id=(v_item->>'product_id')::uuid and organization_id=p_organization_id and is_active for update;
  if not found then raise exception 'Product not found or inactive'; end if;
  if v_product.stock<v_qty then raise exception 'Insufficient stock for %',v_product.name; end if;
  v_subtotal:=v_subtotal+round(v_product.price*v_qty,2);
 end loop;
 if coalesce(p_discount,0)>v_subtotal then raise exception 'Discount exceeds subtotal'; end if;
 if coalesce(p_tax,0)>v_subtotal*0.3 then raise exception 'Tax amount is outside the allowed range'; end if;
 v_total:=round(v_subtotal-coalesce(p_discount,0)+coalesce(p_tax,0),2);
 v_sale_id:=gen_random_uuid();
 v_receipt:='SF-'||to_char(now() at time zone 'Asia/Bangkok','YYYYMMDD')||'-'||upper(substr(replace(v_sale_id::text,'-',''),1,8));
 insert into public.sales(id,organization_id,receipt_no,customer_id,cashier_id,subtotal,discount,tax,total,payment_method,status)
 values(v_sale_id,p_organization_id,v_receipt,p_customer_id,v_user,v_subtotal,coalesce(p_discount,0),coalesce(p_tax,0),v_total,coalesce(nullif(trim(p_payment_method),''),'cash'),'completed');
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'quantity')::numeric;
  select * into v_product from public.products where id=(v_item->>'product_id')::uuid and organization_id=p_organization_id for update;
  select coalesce(pc.cost,0) into v_cost from public.product_costs pc where pc.organization_id=p_organization_id and pc.product_id=v_product.id;
  insert into public.sale_items(organization_id,sale_id,product_id,product_name,quantity,unit_price,unit_cost,line_total)
  values(p_organization_id,v_sale_id,v_product.id,v_product.name,v_qty,v_product.price,coalesce(v_cost,0),round(v_product.price*v_qty,2));
  update public.products set stock=stock-v_qty,updated_at=now() where id=v_product.id and organization_id=p_organization_id;
  insert into public.stock_movements(organization_id,product_id,movement_type,quantity_delta,reference,note,created_by)
  values(p_organization_id,v_product.id,'sale',-v_qty,v_receipt,'POS sale',v_user);
 end loop;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(p_organization_id,v_user,'checkout','sale',v_sale_id::text,jsonb_build_object('receipt_no',v_receipt,'total',v_total,'item_count',jsonb_array_length(p_items)));
 return v_sale_id;
end;
$$;

-- Direct non-idempotent checkout is not exposed to browser clients.
revoke all on function public.checkout_sale(uuid,jsonb,text,numeric,numeric,uuid) from public,anon,authenticated;
grant execute on function public.checkout_sale(uuid,jsonb,text,numeric,numeric,uuid) to postgres;

-- Restrict privileged stock adjustments to stores with an active paid/trial license.
create or replace function public.adjust_stock(p_organization_id uuid,p_product_id uuid,p_quantity_delta numeric,p_note text default null)
returns numeric language plpgsql security definer set search_path=pg_catalog,public,auth,private
as $$
declare v_user uuid:=auth.uid(); v_role text; v_product public.products%rowtype; v_new_stock numeric(12,3);
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if not private.has_active_store_license(p_organization_id) then raise exception 'Subscription expired. Renew to change stock.'; end if;
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
end;
$$;

-- Owner-only pending member queue, without granting direct access to auth.users.
create or replace function public.list_pending_store_members()
returns table(member_id uuid, user_id uuid, display_name text, email text, requested_at timestamptz)
language plpgsql stable security definer set search_path=pg_catalog,public,auth
as $$
declare v_org uuid;
begin
 select m.organization_id into v_org from public.organization_members m
 where m.user_id=(select auth.uid()) and m.is_active and m.membership_status='active' and m.role='owner'
 order by m.created_at limit 1;
 if v_org is null then raise exception 'Only store owner can view pending requests'; end if;
 return query select m.id,m.user_id,coalesce(p.display_name,'พนักงาน'),u.email,m.created_at
 from public.organization_members m
 join auth.users u on u.id=m.user_id
 left join public.profiles p on p.id=m.user_id
 where m.organization_id=v_org and m.membership_status='pending'
 order by m.created_at;
end;
$$;
revoke all on function public.list_pending_store_members() from public,anon;
grant execute on function public.list_pending_store_members() to authenticated;

commit;