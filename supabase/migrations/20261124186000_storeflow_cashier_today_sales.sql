drop policy if exists sales_cashier_today_guard on public.sales;
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
);