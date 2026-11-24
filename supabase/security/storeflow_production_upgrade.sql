-- StoreFlow production upgrade bundle
-- Canonical migration history is in supabase/migrations/.
-- This is a reference bundle for review; it is NOT intended to be re-run on a database
-- where these migrations have already been applied. Apply migrations in timestamp order.

\n-- ===== supabase/migrations/20261124180000_storeflow_production_onboarding_offline.sql =====\n-- StoreFlow production onboarding, trial, role guards, idempotent POS sync, and Realtime
begin;

alter table public.organizations
  add column if not exists invite_code text,
  add column if not exists plan_type text not null default 'subscription'
    check (plan_type in ('subscription','lifetime'));

create unique index if not exists organizations_invite_code_uidx
  on public.organizations (upper(invite_code)) where invite_code is not null;

alter table public.organization_members
  add column if not exists membership_status text not null default 'active'
    check (membership_status in ('pending','active','rejected','suspended'));

update public.organization_members
set membership_status = case when is_active then 'active' else 'pending' end
where membership_status is distinct from case when is_active then 'active' else 'pending' end;

create index if not exists organization_members_pending_idx
  on public.organization_members (organization_id, membership_status, created_at desc);

-- Trial metadata already exists in the subscription schema; make the trial policy explicit.
alter table public.organization_subscriptions
  add column if not exists trial_started_at timestamptz,
  add column if not exists plan_type text not null default 'subscription'
    check (plan_type in ('subscription','lifetime'));

update public.organization_subscriptions
set trial_started_at = coalesce(trial_started_at, created_at),
    trial_ends_at = coalesce(trial_ends_at, created_at + interval '7 days')
where status in ('free','trialing') and trial_ends_at is null;

-- Product catalogue / pricing. Stripe price IDs must be configured before accepting live payment.
insert into public.subscription_plans
(id,name,description,monthly_price_thb,yearly_price_thb,limits,features,sort_order,is_active)
values
('lifetime','Lifetime','ซื้อขาด จ่ายครั้งเดียว ใช้งานได้ตลอดชีพ พร้อมอัปเดตฟีเจอร์ฟรี',2590,2590,
 '{"employees":-1,"products":-1,"branches":-1,"storage_mb":51200}'::jsonb,
 '{"pos":true,"inventory":true,"customers":true,"reports_basic":true,"payroll":true,"advanced_reports":true,"priority_support":false,"lifetime_updates":true,"promo_price_thb":2590,"regular_price_thb":3990,"saving_thb":1400}'::jsonb,
 5,true)
on conflict (id) do update set
 name=excluded.name,description=excluded.description,
 monthly_price_thb=2590,yearly_price_thb=2590,
 limits=excluded.limits,features=excluded.features,is_active=true,sort_order=5,updated_at=now();

-- A private lookup avoids exposing invite codes to non-owners.
create or replace function private.is_org_owner(p_org uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id=p_org and m.user_id=(select auth.uid())
      and m.is_active and m.membership_status='active' and m.role='owner'
  );
$$;
revoke all on function private.is_org_owner(uuid) from public, anon;
grant execute on function private.is_org_owner(uuid) to authenticated;

-- Signup metadata is used only by this trusted Auth trigger; it is never used as an RLS claim.
create or replace function private.handle_storeflow_signup()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'onboarding_role','owner');
  v_store_name text := nullif(trim(new.raw_user_meta_data->>'store_name'),'');
  v_invite text := upper(regexp_replace(coalesce(new.raw_user_meta_data->>'invite_code',''), '\s','','g'));
  v_org uuid;
  v_template uuid;
  v_slug text;
  v_invite_code text;
begin
  if v_role not in ('owner','cashier') then
    raise exception 'Invalid onboarding role';
  end if;

  insert into public.profiles(id,display_name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''), split_part(new.email,'@',1)))
  on conflict (id) do nothing;

  if v_role='owner' then
    if v_store_name is null or length(v_store_name)<2 or length(v_store_name)>120 then
      raise exception 'Store name must be between 2 and 120 characters';
    end if;
    v_slug := 'store-' || substr(replace(gen_random_uuid()::text,'-',''),1,12);
    v_invite_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    insert into public.organizations(name,slug,invite_code,plan_type)
    values(v_store_name,v_slug,v_invite_code,'subscription') returning id into v_org;

    insert into public.organization_members(organization_id,user_id,role,is_active,membership_status)
    values(v_org,new.id,'owner',true,'active')
    on conflict (organization_id,user_id) do update
      set role='owner',is_active=true,membership_status='active';

    insert into public.organization_subscriptions
      (organization_id,plan_id,billing_interval,status,trial_started_at,trial_ends_at,plan_type)
    values(v_org,'free','month','trialing',now(),now()+interval '7 days','subscription')
    on conflict (organization_id) do update set
      status='trialing',trial_started_at=now(),trial_ends_at=now()+interval '7 days',
      plan_id='free',plan_type='subscription',updated_at=now();

    select id into v_template from public.organizations where slug='storeflow' limit 1;
    if v_template is not null then
      insert into public.role_permissions(organization_id,role,module,action,allowed)
      select v_org,role,module,action,allowed from public.role_permissions
      where organization_id=v_template on conflict do nothing;
    end if;
  else
    if v_invite='' then raise exception 'Invite code is required for staff signup'; end if;
    select id into v_org from public.organizations
      where upper(invite_code)=v_invite limit 1;
    if v_org is null then raise exception 'Invite code is invalid'; end if;
    insert into public.organization_members(organization_id,user_id,role,is_active,membership_status)
    values(v_org,new.id,'cashier',false,'pending')
    on conflict (organization_id,user_id) do update
      set role='cashier',is_active=false,membership_status='pending';
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_storeflow on auth.users;
create trigger on_auth_user_created_storeflow
after insert on auth.users
for each row execute function private.handle_storeflow_signup();

-- Existing bootstrap function must not silently turn a staff signup into a new Owner account.
create or replace function public.bootstrap_store_owner(p_org_slug text default 'storeflow')
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare v_user uuid := auth.uid(); v_org uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select organization_id into v_org from public.organization_members
  where user_id=v_user and is_active and membership_status='active'
  order by created_at limit 1;
  if v_org is not null then return v_org; end if;
  raise exception 'No active store membership. Owner onboarding is completed during signup; staff must wait for approval.';
end;
$$;
revoke all on function public.bootstrap_store_owner(text) from public, anon;
grant execute on function public.bootstrap_store_owner(text) to authenticated;

create or replace function public.get_my_store_membership_state()
returns table(organization_id uuid, membership_status text, role text, organization_name text)
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select m.organization_id,m.membership_status,m.role,o.name
  from public.organization_members m
  join public.organizations o on o.id=m.organization_id
  where m.user_id=(select auth.uid())
  order by m.created_at desc limit 1;
$$;
revoke all on function public.get_my_store_membership_state() from public, anon;
grant execute on function public.get_my_store_membership_state() to authenticated;

create or replace function public.approve_store_member(p_member_id uuid, p_approve boolean default true)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.organization_members where id=p_member_id;
  if v_org is null or not private.is_org_owner(v_org) then
    raise exception 'Only the store owner can approve staff';
  end if;
  update public.organization_members
  set is_active=p_approve,
      membership_status=case when p_approve then 'active' else 'rejected' end
  where id=p_member_id and membership_status='pending';
  if not found then raise exception 'Pending membership not found'; end if;
end;
$$;
revoke all on function public.approve_store_member(uuid,boolean) from public, anon;
grant execute on function public.approve_store_member(uuid,boolean) to authenticated;

-- Staff may see only same-store products, and only today's sales for their own cashier account.
drop policy if exists sales_cashier_today_guard on public.sales;
create policy sales_cashier_today_guard on public.sales
as restrictive for select to authenticated
using (
  not exists (
    select 1 from public.organization_members m
    where m.organization_id=sales.organization_id and m.user_id=(select auth.uid())
      and m.role='cashier' and m.is_active and m.membership_status='active'
  )
  or (
    cashier_id=(select auth.uid())
    and created_at >= (date_trunc('day', now() at time zone 'Asia/Bangkok') at time zone 'Asia/Bangkok')
    and created_at < ((date_trunc('day', now() at time zone 'Asia/Bangkok') + interval '1 day') at time zone 'Asia/Bangkok')
  )
);

drop policy if exists sale_items_cashier_today_guard on public.sale_items;
create policy sale_items_cashier_today_guard on public.sale_items
as restrictive for select to authenticated
using (
  not exists (
    select 1 from public.organization_members m
    where m.organization_id=sale_items.organization_id and m.user_id=(select auth.uid())
      and m.role='cashier' and m.is_active and m.membership_status='active'
  )
  or exists (
    select 1 from public.sales s
    where s.id=sale_items.sale_id and s.organization_id=sale_items.organization_id
      and s.cashier_id=(select auth.uid())
      and s.created_at >= (date_trunc('day', now() at time zone 'Asia/Bangkok') at time zone 'Asia/Bangkok')
      and s.created_at < ((date_trunc('day', now() at time zone 'Asia/Bangkok') + interval '1 day') at time zone 'Asia/Bangkok')
  )
);

-- Role permission rows: cashiers can read stock and create POS orders, not inventory mutations or financial modules.
insert into public.role_permissions(organization_id,role,module,action,allowed)
select o.id,'cashier',v.module,v.action,v.allowed
from public.organizations o
cross join (values
 ('dashboard','read',true),('pos','read',true),('pos','create',true),
 ('inventory','read',true),('orders','read',true),('orders','create',true),
 ('inventory','create',false),('inventory','update',false),('inventory','delete',false),
 ('reports','read',false),('expenses','read',false),('payroll','read',false),
 ('permissions','read',false),('permissions','update',false),('billing','read',false)
) as v(module,action,allowed)
on conflict (organization_id,role,module,action) do update set allowed=excluded.allowed;

-- A durable idempotency ledger makes retries safe when a client loses the network after checkout committed.
create table if not exists private.pos_order_idempotency (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  idempotency_key uuid not null,
  sale_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key)
);
alter table private.pos_order_idempotency enable row level security;
revoke all on private.pos_order_idempotency from public, anon, authenticated;

create or replace function public.checkout_sale_idempotent(
  p_organization_id uuid,
  p_items jsonb,
  p_payment_method text,
  p_discount numeric default 0,
  p_tax numeric default 0,
  p_customer_id uuid default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare v_user uuid := auth.uid(); v_sale uuid; v_existing uuid; v_key uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null then raise exception 'Idempotency key is required'; end if;
  if not private.is_org_member(p_organization_id) then raise exception 'Not an active store member'; end if;
  v_key:=p_idempotency_key;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || v_key::text,0));
  select sale_id into v_existing from private.pos_order_idempotency
    where organization_id=p_organization_id and idempotency_key=v_key;
  if v_existing is not null then return v_existing; end if;
  insert into private.pos_order_idempotency(organization_id,idempotency_key,created_by)
  values(p_organization_id,v_key,v_user)
  on conflict do nothing;
  v_sale:=public.checkout_sale(p_organization_id,p_items,p_payment_method,p_discount,p_tax,p_customer_id);
  update private.pos_order_idempotency set sale_id=v_sale
  where organization_id=p_organization_id and idempotency_key=v_key;
  return v_sale;
end;
$$;
revoke all on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid) from public, anon;
grant execute on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid) to authenticated;

-- Realtime publication is opt-in per table; avoid duplicate publication errors.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='products') then
      alter publication supabase_realtime add table public.products;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='sales') then
      alter publication supabase_realtime add table public.sales;
    end if;
  end if;
end $$;

create index if not exists sales_org_created_idx on public.sales(organization_id,created_at desc);
create index if not exists sales_org_cashier_created_idx on public.sales(organization_id,cashier_id,created_at desc);

commit;
\n\n-- ===== supabase/migrations/20261124181000_storeflow_subscription_write_lock.sql =====\n-- Enforce subscription expiry at the database boundary while preserving read/export access.
begin;
create or replace function private.has_active_store_license(p_org uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select exists (
    select 1 from public.organization_subscriptions s
    where s.organization_id=p_org
      and (
        (s.plan_type='lifetime' and s.status='active')
        or (s.status='active' and (s.current_period_end is null or s.current_period_end>now()))
        or (s.status='trialing' and s.trial_ends_at>now())
      )
  );
$$;
revoke all on function private.has_active_store_license(uuid) from public, anon;
grant execute on function private.has_active_store_license(uuid) to authenticated;

do $$
declare t record;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    where c.table_schema='public' and c.column_name='organization_id'
      and c.table_name not in ('organization_members','organization_subscriptions','subscription_billing_events')
  loop
    execute format('drop policy if exists license_write_insert_%I on public.%I',t.table_name,t.table_name);
    execute format('drop policy if exists license_write_update_%I on public.%I',t.table_name,t.table_name);
    execute format('drop policy if exists license_write_delete_%I on public.%I',t.table_name,t.table_name);
    execute format('create policy license_write_insert_%I on public.%I as restrictive for insert to authenticated with check (private.has_active_store_license(organization_id))',t.table_name,t.table_name);
    execute format('create policy license_write_update_%I on public.%I as restrictive for update to authenticated using (private.has_active_store_license(organization_id)) with check (private.has_active_store_license(organization_id))',t.table_name,t.table_name);
    execute format('create policy license_write_delete_%I on public.%I as restrictive for delete to authenticated using (private.has_active_store_license(organization_id))',t.table_name,t.table_name);
  end loop;
end $$;
commit;
\n\n-- ===== supabase/migrations/20261124182000_storeflow_private_product_costs.sql =====\n-- Isolate product cost data so cashier accounts cannot read purchase costs or margin.
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

commit;\n\n-- ===== supabase/migrations/20261124183000_storeflow_private_invites.sql =====\n-- Keep invitation secrets out of the member-readable organizations table.
begin;
create table if not exists private.organization_invites(
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 invite_code text not null unique,
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);
alter table private.organization_invites enable row level security;
revoke all on private.organization_invites from public,anon,authenticated;
insert into private.organization_invites(organization_id,invite_code)
select id,invite_code from public.organizations where invite_code is not null
on conflict(organization_id) do update set invite_code=excluded.invite_code;

create or replace function private.handle_storeflow_signup()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,auth,private
as $$
declare
 v_role text:=coalesce(new.raw_user_meta_data->>'onboarding_role','owner');
 v_store_name text:=nullif(trim(new.raw_user_meta_data->>'store_name'),'');
 v_invite text:=upper(regexp_replace(coalesce(new.raw_user_meta_data->>'invite_code',''),'\s','','g'));
 v_org uuid; v_template uuid; v_slug text; v_code text;
begin
 if v_role not in ('owner','cashier') then raise exception 'Invalid onboarding role'; end if;
 insert into public.profiles(id,display_name)
 values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1)))
 on conflict(id) do nothing;
 if v_role='owner' then
  if v_store_name is null or length(v_store_name)<2 or length(v_store_name)>120 then raise exception 'Store name must be between 2 and 120 characters'; end if;
  v_slug:='store-'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,16));
  insert into public.organizations(name,slug,plan_type) values(v_store_name,v_slug,'subscription') returning id into v_org;
  insert into private.organization_invites(organization_id,invite_code) values(v_org,v_code);
  insert into public.organization_members(organization_id,user_id,role,is_active,membership_status) values(v_org,new.id,'owner',true,'active')
  on conflict(organization_id,user_id) do update set role='owner',is_active=true,membership_status='active';
  insert into public.organization_subscriptions(organization_id,plan_id,billing_interval,status,trial_started_at,trial_ends_at,plan_type)
  values(v_org,'free','month','trialing',now(),now()+interval '7 days','subscription')
  on conflict(organization_id) do update set status='trialing',trial_started_at=now(),trial_ends_at=now()+interval '7 days',plan_id='free',plan_type='subscription',updated_at=now();
  select id into v_template from public.organizations where slug='storeflow' limit 1;
  if v_template is not null then
   insert into public.role_permissions(organization_id,role,module,action,allowed)
   select v_org,role,module,action,allowed from public.role_permissions where organization_id=v_template on conflict do nothing;
  end if;
 else
  if v_invite='' then raise exception 'Invite code is required for staff signup'; end if;
  select organization_id into v_org from private.organization_invites where upper(invite_code)=v_invite and is_active limit 1;
  if v_org is null then raise exception 'Invite code is invalid'; end if;
  insert into public.organization_members(organization_id,user_id,role,is_active,membership_status)
  values(v_org,new.id,'cashier',false,'pending')
  on conflict(organization_id,user_id) do update set role='cashier',is_active=false,membership_status='pending';
 end if;
 return new;
end;
$$;

create or replace function public.get_store_invite_code()
returns text language plpgsql stable security definer
set search_path=pg_catalog,public,auth,private
as $$
declare v_code text;
begin
 select i.invite_code into v_code
 from private.organization_invites i
 join public.organization_members m on m.organization_id=i.organization_id
 where m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active' and i.is_active
 order by m.created_at limit 1;
 if v_code is null then raise exception 'Only active store owners can view invite code'; end if;
 return v_code;
end;
$$;
revoke all on function public.get_store_invite_code() from public,anon;
grant execute on function public.get_store_invite_code() to authenticated;

alter table public.organizations drop column if exists invite_code;

drop policy if exists sale_items_cashier_today_guard on public.sale_items;
create policy sale_items_cashier_today_guard on public.sale_items as restrictive for select to authenticated
using (not exists(select 1 from public.organization_members m where m.organization_id=sale_items.organization_id and m.user_id=(select auth.uid()) and m.role='cashier' and m.is_active and m.membership_status='active'));

create policy pos_idempotency_deny_all on private.pos_order_idempotency
for all to public using(false) with check(false);
create index if not exists pos_order_idempotency_created_by_idx on private.pos_order_idempotency(created_by);
commit;\n\n-- ===== supabase/migrations/20261124184000_storeflow_private_invite_policy.sql =====\nbegin;
drop policy if exists organization_invites_deny_all on private.organization_invites;
create policy organization_invites_deny_all on private.organization_invites
for all to public using(false) with check(false);
commit;\n\n-- ===== supabase/migrations/20261124185000_storeflow_legacy_trial_grace.sql =====\n-- Grandfather existing Free stores with a fresh 7-day transition trial; do not unexpectedly lock legacy tenants.
update public.organization_subscriptions
set status='trialing',trial_started_at=now(),trial_ends_at=now()+interval '7 days',updated_at=now()
where status='free' and plan_id='free' and trial_ends_at<=now();\n\n-- ===== supabase/migrations/20261124186000_storeflow_cashier_today_sales.sql =====\ndrop policy if exists sales_cashier_today_guard on public.sales;
create policy sales_cashier_today_guard on public.sales
as restrictive for select to authenticated
using (
 not exists(select 1 from public.organization_members m
   where m.organization_id=sales.organization_id and m.user_id=(select auth.uid())
     and m.role='cashier' and m.is_active and m.membership_status='active')
 or (
   created_at >= (date_trunc('day',now() at time zone 'Asia/Bangkok') at time zone 'Asia/Bangkok')
   and created_at < ((date_trunc('day',now() at time zone 'Asia/Bangkok')+interval '1 day') at time zone 'Asia/Bangkok')
 )
);\n\n-- ===== supabase/migrations/20261124187000_storeflow_cashier_hard_role_cap.sql =====\ncreate or replace function private.has_module_access(p_organization_id uuid,p_module text,p_action text)
returns boolean language plpgsql stable security definer set search_path=''
as $$
declare v_role text; v_allowed boolean;
begin
 if auth.uid() is null then return false; end if;
 select m.role into v_role from public.organization_members m
 where m.organization_id=p_organization_id and m.user_id=(select auth.uid())
 and m.is_active=true and m.membership_status='active' limit 1;
 if v_role is null then return false; end if;
 if v_role in ('owner','admin') then return true; end if;
 -- Cashier is a hard-capped role; tenant-configurable permission rows cannot expand it.
 if v_role='cashier' then
  return case
   when p_module='pos' then p_action in ('read','create')
   when p_module='orders' then p_action in ('read','create')
   when p_module='inventory' then p_action='read'
   else false
  end;
 end if;
 select rp.allowed into v_allowed from public.role_permissions rp
 where rp.organization_id=p_organization_id and rp.role=v_role
 and rp.module=p_module and rp.action=p_action limit 1;
 if v_allowed is not null then return v_allowed; end if;
 return case v_role
  when 'manager' then p_action in ('read','create','update') and p_module not in ('payroll','permissions','audit')
  when 'hr' then p_module in ('employees','attendance','leave','payroll') and p_action in ('read','create','update')
  when 'accountant' then p_module in ('reports','expenses','payroll','orders') and p_action in ('read','create','update','approve')
  when 'employee' then p_module in ('dashboard','attendance','leave') and p_action in ('read','create')
  else false
 end;
end;
$$;\n\n-- ===== supabase/migrations/20261124188000_storeflow_atomic_checkout_only.sql =====\n-- Sales and line-item writes must go through the atomic, idempotent checkout RPC.
drop policy if exists sales_no_direct_insert on public.sales;
create policy sales_no_direct_insert on public.sales as restrictive
for insert to authenticated with check(false);
drop policy if exists sale_items_no_direct_insert on public.sale_items;
create policy sale_items_no_direct_insert on public.sale_items as restrictive
for insert to authenticated with check(false);