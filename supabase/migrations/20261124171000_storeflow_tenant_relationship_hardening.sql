-- Complete tenant guard for platform billing events while preserving platform-admin access.
drop policy if exists tenant_guard_subscription_billing_events on public.subscription_billing_events;
create policy tenant_guard_subscription_billing_events on public.subscription_billing_events as restrictive for all to authenticated
using (private.is_org_member(organization_id) or exists(select 1 from public.platform_admins a where a.user_id=(select auth.uid())))
with check (private.is_org_member(organization_id) or exists(select 1 from public.platform_admins a where a.user_id=(select auth.uid())));

create or replace function private.enforce_tenant_relationships()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_org uuid:=new.organization_id;
begin
 if tg_table_name='sales' then
  if new.customer_id is not null and not exists(select 1 from public.customers c where c.id=new.customer_id and c.organization_id=v_org) then raise exception using errcode='23503',message='customer_id must belong to the same organization'; end if;
 elsif tg_table_name='employees' then
  if new.user_id is not null and not exists(select 1 from public.organization_members m where m.organization_id=v_org and m.user_id=new.user_id and m.is_active=true) then raise exception using errcode='23503',message='employee user must be an active member of the same organization'; end if;
 elsif tg_table_name='sale_items' then
  if not exists(select 1 from public.sales s where s.id=new.sale_id and s.organization_id=v_org) then raise exception using errcode='23503',message='sale_id must belong to the same organization'; end if;
  if new.product_id is not null and not exists(select 1 from public.products p where p.id=new.product_id and p.organization_id=v_org) then raise exception using errcode='23503',message='product_id must belong to the same organization'; end if;
 elsif tg_table_name='stock_movements' then
  if not exists(select 1 from public.products p where p.id=new.product_id and p.organization_id=v_org) then raise exception using errcode='23503',message='product_id must belong to the same organization'; end if;
 elsif tg_table_name in ('shifts','attendance','leave_requests') then
  if not exists(select 1 from public.employees e where e.id=new.employee_id and e.organization_id=v_org) then raise exception using errcode='23503',message='employee_id must belong to the same organization'; end if;
 elsif tg_table_name='payroll_items' then
  if not exists(select 1 from public.payroll_periods p where p.id=new.payroll_period_id and p.organization_id=v_org) then raise exception using errcode='23503',message='payroll_period_id must belong to the same organization'; end if;
  if not exists(select 1 from public.employees e where e.id=new.employee_id and e.organization_id=v_org) then raise exception using errcode='23503',message='employee_id must belong to the same organization'; end if;
 elsif tg_table_name='business_documents' then
  if new.customer_id is not null and not exists(select 1 from public.customers c where c.id=new.customer_id and c.organization_id=v_org) then raise exception using errcode='23503',message='customer_id must belong to the same organization'; end if;
  if new.supplier_id is not null and not exists(select 1 from public.suppliers s where s.id=new.supplier_id and s.organization_id=v_org) then raise exception using errcode='23503',message='supplier_id must belong to the same organization'; end if;
  if new.source_sale_id is not null and not exists(select 1 from public.sales s where s.id=new.source_sale_id and s.organization_id=v_org) then raise exception using errcode='23503',message='source_sale_id must belong to the same organization'; end if;
  if new.related_document_id is not null and not exists(select 1 from public.business_documents d where d.id=new.related_document_id and d.organization_id=v_org) then raise exception using errcode='23503',message='related_document_id must belong to the same organization'; end if;
 elsif tg_table_name='business_document_items' then
  if not exists(select 1 from public.business_documents d where d.id=new.document_id and d.organization_id=v_org) then raise exception using errcode='23503',message='document_id must belong to the same organization'; end if;
  if new.product_id is not null and not exists(select 1 from public.products p where p.id=new.product_id and p.organization_id=v_org) then raise exception using errcode='23503',message='product_id must belong to the same organization'; end if;
 end if;
 return new;
end; $$;
drop trigger if exists enforce_tenant_relationships on public.sales;
create trigger enforce_tenant_relationships before insert or update on public.sales for each row execute function private.enforce_tenant_relationships();
drop trigger if exists enforce_tenant_relationships on public.employees;
create trigger enforce_tenant_relationships before insert or update on public.employees for each row execute function private.enforce_tenant_relationships();
