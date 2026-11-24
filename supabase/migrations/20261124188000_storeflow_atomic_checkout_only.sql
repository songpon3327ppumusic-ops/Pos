-- Sales and line-item writes must go through the atomic, idempotent checkout RPC.
drop policy if exists sales_no_direct_insert on public.sales;
create policy sales_no_direct_insert on public.sales as restrictive
for insert to authenticated with check(false);
drop policy if exists sale_items_no_direct_insert on public.sale_items;
create policy sale_items_no_direct_insert on public.sale_items as restrictive
for insert to authenticated with check(false);