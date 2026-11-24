-- StoreFlow live operations: first-owner bootstrap, atomic POS checkout, stock adjustment.
create or replace function public.bootstrap_store_owner(p_org_slug text default 'storeflow')
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select id into v_org from public.organizations where slug = p_org_slug;
  if v_org is null then raise exception 'Store organization not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text, 0));
  if exists (select 1 from public.organization_members where organization_id = v_org) then
    if exists (select 1 from public.organization_members where organization_id = v_org and user_id = v_user and is_active) then return v_org; end if;
    raise exception 'This store already has an owner. Ask the store owner to invite you.';
  end if;
  insert into public.profiles (id, display_name)
  values (v_user, coalesce((select raw_user_meta_data->>'full_name' from auth.users where id = v_user), split_part((select email from auth.users where id = v_user), '@', 1)))
  on conflict (id) do nothing;
  insert into public.organization_members (organization_id, user_id, role, is_active)
  values (v_org, v_user, 'owner', true)
  on conflict (organization_id, user_id) do update set role = 'owner', is_active = true;
  return v_org;
end;
$$;
revoke all on function public.bootstrap_store_owner(text) from public, anon;
grant execute on function public.bootstrap_store_owner(text) to authenticated;

create or replace function public.checkout_sale(
  p_organization_id uuid, p_items jsonb, p_payment_method text,
  p_discount numeric default 0, p_tax numeric default 0, p_customer_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty numeric(12,3);
  v_subtotal numeric(12,2) := 0;
  v_total numeric(12,2);
  v_sale_id uuid;
  v_receipt text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Cart is empty'; end if;
  if exists (select 1 from (select value->>'product_id' as product_id from jsonb_array_elements(p_items) group by value->>'product_id' having count(*) > 1) d) then raise exception 'Duplicate products in cart'; end if;
  if coalesce(p_discount, 0) < 0 or coalesce(p_tax, 0) < 0 then raise exception 'Discount and tax must not be negative'; end if;
  select role into v_role from public.organization_members
  where organization_id = p_organization_id and user_id = v_user and is_active;
  if v_role is null or v_role not in ('owner','admin','manager','cashier') then raise exception 'You do not have permission to create a sale'; end if;
  if p_customer_id is not null and not exists (select 1 from public.customers where id = p_customer_id and organization_id = p_organization_id) then raise exception 'Customer does not belong to this store'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::numeric;
    if v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    select * into v_product from public.products
    where id = (v_item->>'product_id')::uuid and organization_id = p_organization_id and is_active = true for update;
    if not found then raise exception 'Product not found or inactive'; end if;
    if v_product.stock < v_qty then raise exception 'Insufficient stock for %', v_product.name; end if;
    v_subtotal := v_subtotal + round(v_product.price * v_qty, 2);
  end loop;
  if coalesce(p_discount, 0) > v_subtotal then raise exception 'Discount exceeds subtotal'; end if;
  if coalesce(p_tax, 0) > v_subtotal * 0.3 then raise exception 'Tax amount is outside the allowed range'; end if;
  v_total := round(v_subtotal - coalesce(p_discount, 0) + coalesce(p_tax, 0), 2);
  v_sale_id := gen_random_uuid();
  v_receipt := 'SF-' || to_char(now() at time zone 'Asia/Bangkok', 'YYYYMMDD') || '-' || upper(substr(replace(v_sale_id::text, '-', ''), 1, 8));
  insert into public.sales (id, organization_id, receipt_no, customer_id, cashier_id, subtotal, discount, tax, total, payment_method, status)
  values (v_sale_id, p_organization_id, v_receipt, p_customer_id, v_user, v_subtotal, coalesce(p_discount, 0), coalesce(p_tax, 0), v_total, coalesce(nullif(trim(p_payment_method), ''), 'cash'), 'completed');
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::numeric;
    select * into v_product from public.products where id = (v_item->>'product_id')::uuid and organization_id = p_organization_id for update;
    insert into public.sale_items (organization_id, sale_id, product_id, product_name, quantity, unit_price, unit_cost, line_total)
    values (p_organization_id, v_sale_id, v_product.id, v_product.name, v_qty, v_product.price, v_product.cost, round(v_product.price * v_qty, 2));
    update public.products set stock = stock - v_qty, updated_at = now() where id = v_product.id and organization_id = p_organization_id;
    insert into public.stock_movements (organization_id, product_id, movement_type, quantity_delta, reference, note, created_by)
    values (p_organization_id, v_product.id, 'sale', -v_qty, v_receipt, 'POS sale', v_user);
  end loop;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
  values (p_organization_id, v_user, 'checkout', 'sale', v_sale_id::text, jsonb_build_object('receipt_no', v_receipt, 'total', v_total, 'item_count', jsonb_array_length(p_items)));
  return v_sale_id;
end;
$$;
revoke all on function public.checkout_sale(uuid, jsonb, text, numeric, numeric, uuid) from public, anon;
grant execute on function public.checkout_sale(uuid, jsonb, text, numeric, numeric, uuid) to authenticated;

create or replace function public.adjust_stock(p_organization_id uuid, p_product_id uuid, p_quantity_delta numeric, p_note text default null)
returns numeric
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_product public.products%rowtype;
  v_new_stock numeric(12,3);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_quantity_delta = 0 then raise exception 'Stock adjustment cannot be zero'; end if;
  select role into v_role from public.organization_members
  where organization_id = p_organization_id and user_id = v_user and is_active;
  if v_role is null or v_role not in ('owner','admin','manager') then raise exception 'You do not have permission to adjust stock'; end if;
  select * into v_product from public.products where id = p_product_id and organization_id = p_organization_id for update;
  if not found then raise exception 'Product not found'; end if;
  v_new_stock := v_product.stock + p_quantity_delta;
  if v_new_stock < 0 then raise exception 'Stock cannot be negative'; end if;
  update public.products set stock = v_new_stock, updated_at = now() where id = p_product_id and organization_id = p_organization_id;
  insert into public.stock_movements (organization_id, product_id, movement_type, quantity_delta, note, created_by)
  values (p_organization_id, p_product_id, 'adjustment', p_quantity_delta, p_note, v_user);
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, details)
  values (p_organization_id, v_user, 'stock_adjustment', 'product', p_product_id::text, jsonb_build_object('delta', p_quantity_delta, 'new_stock', v_new_stock, 'note', p_note));
  return v_new_stock;
end;
$$;
revoke all on function public.adjust_stock(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.adjust_stock(uuid, uuid, numeric, text) to authenticated;
