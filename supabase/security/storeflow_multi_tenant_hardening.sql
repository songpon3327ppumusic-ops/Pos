-- StoreFlow Multi-tenant Security Hardening
-- Canonical tenant key in this project: organization_id (not store_id).
-- Safe to re-run. Run in Supabase SQL Editor as project owner.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.is_org_member(p_organization_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(
  select 1 from public.organization_members m
  where m.organization_id=p_organization_id
    and m.user_id=(select auth.uid()) and m.is_active=true
 );
$$;
revoke all on function private.is_org_member(uuid) from public,anon;
grant execute on function private.is_org_member(uuid) to authenticated;

-- Apply restrictive guards to every tenant table, including existing role policies.
do $$
declare r record;
begin
 for r in
  select c.table_name
  from information_schema.columns c
  join information_schema.tables t on t.table_schema=c.table_schema and t.table_name=c.table_name
  where c.table_schema='public' and c.column_name='organization_id'
    and t.table_type='BASE TABLE'
    and c.table_name<>'subscription_billing_events'
 loop
  execute format('alter table public.%I enable row level security',r.table_name);
  execute format('drop policy if exists %I on public.%I','tenant_guard_'||r.table_name,r.table_name);
  execute format(
   'create policy %I on public.%I as restrictive for all to authenticated using (private.is_org_member(organization_id)) with check (private.is_org_member(organization_id))',
   'tenant_guard_'||r.table_name,r.table_name
  );
 end loop;
end $$;

-- Billing events are platform-admin-only today; allow platform admins while
-- ensuring tenant members cannot access events belonging to another tenant.
drop policy if exists tenant_guard_subscription_billing_events on public.subscription_billing_events;
create policy tenant_guard_subscription_billing_events
on public.subscription_billing_events as restrictive for all to authenticated
using (
 private.is_org_member(organization_id)
 or exists(select 1 from public.platform_admins a where a.user_id=(select auth.uid()))
)
with check (
 private.is_org_member(organization_id)
 or exists(select 1 from public.platform_admins a where a.user_id=(select auth.uid()))
);

-- Make tenant ownership immutable after row creation.
create or replace function private.prevent_organization_id_change()
returns trigger language plpgsql set search_path=''
as $$
begin
 if new.organization_id is distinct from old.organization_id then
  raise exception using errcode='42501',message='Changing organization_id is not allowed';
 end if;
 return new;
end;
$$;
revoke all on function private.prevent_organization_id_change() from public,anon,authenticated;

do $$
declare r record;
begin
 for r in
  select c.table_name
  from information_schema.columns c
  join information_schema.tables t on t.table_schema=c.table_schema and t.table_name=c.table_name
  where c.table_schema='public' and c.column_name='organization_id'
    and t.table_type='BASE TABLE' and c.table_name<>'subscription_billing_events'
 loop
  execute format('drop trigger if exists prevent_org_change on public.%I',r.table_name);
  execute format('create trigger prevent_org_change before update of organization_id on public.%I for each row execute function private.prevent_organization_id_change()',r.table_name);
 end loop;
end $$;

-- Validate that foreign-key-like references never cross organizations.
create or replace function private.enforce_tenant_relationships()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_org uuid:=new.organization_id;
begin
 if tg_table_name='sales' then
  if new.customer_id is not null and not exists(select 1 from public.customers c where c.id=new.customer_id and c.organization_id=v_org) then
   raise exception using errcode='23503',message='customer_id must belong to the same organization';
  end if;
 elsif tg_table_name='employees' then
  if new.user_id is not null and not exists(select 1 from public.organization_members m where m.organization_id=v_org and m.user_id=new.user_id and m.is_active=true) then
   raise exception using errcode='23503',message='employee user must be an active member of the same organization';
  end if;
 elsif tg_table_name='sale_items' then
  if not exists(select 1 from public.sales s where s.id=new.sale_id and s.organization_id=v_org) then
   raise exception using errcode='23503',message='sale_id must belong to the same organization';
  end if;
  if new.product_id is not null and not exists(select 1 from public.products p where p.id=new.product_id and p.organization_id=v_org) then
   raise exception using errcode='23503',message='product_id must belong to the same organization';
  end if;
 elsif tg_table_name='stock_movements' then
  if not exists(select 1 from public.products p where p.id=new.product_id and p.organization_id=v_org) then
   raise exception using errcode='23503',message='product_id must belong to the same organization';
  end if;
 elsif tg_table_name in ('shifts','attendance','leave_requests') then
  if not exists(select 1 from public.employees e where e.id=new.employee_id and e.organization_id=v_org) then
   raise exception using errcode='23503',message='employee_id must belong to the same organization';
  end if;
 elsif tg_table_name='payroll_items' then
  if not exists(select 1 from public.payroll_periods p where p.id=new.payroll_period_id and p.organization_id=v_org) then
   raise exception using errcode='23503',message='payroll_period_id must belong to the same organization';
  end if;
  if not exists(select 1 from public.employees e where e.id=new.employee_id and e.organization_id=v_org) then
   raise exception using errcode='23503',message='employee_id must belong to the same organization';
  end if;
 elsif tg_table_name='business_documents' then
  if new.customer_id is not null and not exists(select 1 from public.customers c where c.id=new.customer_id and c.organization_id=v_org) then
   raise exception using errcode='23503',message='customer_id must belong to the same organization';
  end if;
  if new.supplier_id is not null and not exists(select 1 from public.suppliers s where s.id=new.supplier_id and s.organization_id=v_org) then
   raise exception using errcode='23503',message='supplier_id must belong to the same organization';
  end if;
  if new.source_sale_id is not null and not exists(select 1 from public.sales s where s.id=new.source_sale_id and s.organization_id=v_org) then
   raise exception using errcode='23503',message='source_sale_id must belong to the same organization';
  end if;
  if new.related_document_id is not null and not exists(select 1 from public.business_documents d where d.id=new.related_document_id and d.organization_id=v_org) then
   raise exception using errcode='23503',message='related_document_id must belong to the same organization';
  end if;
 elsif tg_table_name='business_document_items' then
  if not exists(select 1 from public.business_documents d where d.id=new.document_id and d.organization_id=v_org) then
   raise exception using errcode='23503',message='document_id must belong to the same organization';
  end if;
  if new.product_id is not null and not exists(select 1 from public.products p where p.id=new.product_id and p.organization_id=v_org) then
   raise exception using errcode='23503',message='product_id must belong to the same organization';
  end if;
 end if;
 return new;
end;
$$;
revoke all on function private.enforce_tenant_relationships() from public,anon,authenticated;

do $$
declare r text;
begin
 foreach r in array array[
  'sales','employees','sale_items','stock_movements','shifts',
  'attendance','leave_requests','payroll_items','business_documents','business_document_items'
 ] loop
  execute format('drop trigger if exists enforce_tenant_relationships on public.%I',r);
  execute format('create trigger enforce_tenant_relationships before insert or update on public.%I for each row execute function private.enforce_tenant_relationships()',r);
 end loop;
end $$;

-- Private asset bucket. Paths must be:
-- <organization-uuid>/<product-images|store-logos|employee-avatars>/<filename>
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('store-assets','store-assets',false,10485760,array['image/jpeg','image/png','image/webp','image/svg+xml'])
on conflict(id) do update set public=false,file_size_limit=10485760,
 allowed_mime_types=array['image/jpeg','image/png','image/webp','image/svg+xml'];

drop policy if exists store_assets_member_select on storage.objects;
create policy store_assets_member_select on storage.objects for select to authenticated
using(bucket_id='store-assets' and exists(
 select 1 from public.organization_members m
 where m.organization_id::text=(storage.foldername(name))[1]
 and m.user_id=(select auth.uid()) and m.is_active=true
));

drop policy if exists store_assets_member_insert on storage.objects;
create policy store_assets_member_insert on storage.objects for insert to authenticated
with check(bucket_id='store-assets' and array_length(storage.foldername(name),1)>=2 and exists(
 select 1 from public.organization_members m
 where m.organization_id::text=(storage.foldername(name))[1]
 and m.user_id=(select auth.uid()) and m.is_active=true
));

drop policy if exists store_assets_member_update on storage.objects;
create policy store_assets_member_update on storage.objects for update to authenticated
using(bucket_id='store-assets' and exists(
 select 1 from public.organization_members m
 where m.organization_id::text=(storage.foldername(name))[1]
 and m.user_id=(select auth.uid()) and m.is_active=true
))
with check(bucket_id='store-assets' and array_length(storage.foldername(name),1)>=2 and exists(
 select 1 from public.organization_members m
 where m.organization_id::text=(storage.foldername(name))[1]
 and m.user_id=(select auth.uid()) and m.is_active=true
));

drop policy if exists store_assets_member_delete on storage.objects;
create policy store_assets_member_delete on storage.objects for delete to authenticated
using(bucket_id='store-assets' and exists(
 select 1 from public.organization_members m
 where m.organization_id::text=(storage.foldername(name))[1]
 and m.user_id=(select auth.uid()) and m.is_active=true
));
