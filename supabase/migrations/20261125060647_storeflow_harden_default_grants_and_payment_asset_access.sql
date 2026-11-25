begin;
drop policy if exists store_payment_settings_member_read on public.store_payment_settings;
create policy store_payment_settings_pos_read on public.store_payment_settings for select to authenticated
using (exists(select 1 from public.organization_members m where m.organization_id=store_payment_settings.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.membership_status='active' and m.role in ('owner','admin','manager','cashier','accountant')));

drop policy if exists customer_credit_ledger_member_read on public.customer_credit_ledger;
create policy customer_credit_ledger_finance_read on public.customer_credit_ledger for select to authenticated
using (private.has_module_access(organization_id,'customers','read') or private.has_module_access(organization_id,'orders','read'));

drop policy if exists store_payment_assets_member_read on storage.objects;
create policy store_payment_assets_qr_read on storage.objects for select to authenticated
using (bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and (storage.foldername(name))[2]='qr'
and exists(select 1 from public.organization_members m where m.organization_id=((storage.foldername(objects.name))[1])::uuid and m.user_id=(select auth.uid()) and m.is_active and m.membership_status='active' and m.role in ('owner','admin','manager','cashier')));

create policy store_payment_assets_slip_read on storage.objects for select to authenticated
using (bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and (storage.foldername(name))[2]='slips'
and exists(select 1 from public.organization_members m where m.organization_id=((storage.foldername(objects.name))[1])::uuid and m.user_id=(select auth.uid()) and m.is_active and m.membership_status='active' and m.role in ('owner','admin','manager','cashier','accountant')));

drop policy if exists store_payment_assets_member_slip_insert on storage.objects;
create policy store_payment_assets_cashier_slip_insert on storage.objects for insert to authenticated
with check (bucket_id='store-payment-assets' and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' and (storage.foldername(name))[2]='slips'
and exists(select 1 from public.organization_members m join public.sales s on s.organization_id=m.organization_id
where m.organization_id=((storage.foldername(objects.name))[1])::uuid and m.user_id=(select auth.uid()) and m.is_active and m.membership_status='active'
and m.role in ('owner','admin','manager','cashier') and s.id=((storage.foldername(objects.name))[3])::uuid));
commit;
