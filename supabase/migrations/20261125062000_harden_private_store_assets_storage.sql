-- Keep store-assets private, restrict file types/size, and require active membership.
begin;
update storage.buckets
set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp']
where id='store-assets';
drop policy if exists store_assets_member_select on storage.objects;
drop policy if exists store_assets_member_insert on storage.objects;
drop policy if exists store_assets_member_update on storage.objects;
drop policy if exists store_assets_member_delete on storage.objects;
create policy store_assets_member_select on storage.objects for select to authenticated
using(bucket_id='store-assets' and exists(select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active'));
create policy store_assets_member_insert on storage.objects for insert to authenticated
with check(bucket_id='store-assets' and array_length(storage.foldername(name),1)>=2 and exists(select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active'));
create policy store_assets_member_update on storage.objects for update to authenticated
using(bucket_id='store-assets' and exists(select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active'))
with check(bucket_id='store-assets' and array_length(storage.foldername(name),1)>=2 and exists(select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active'));
create policy store_assets_member_delete on storage.objects for delete to authenticated
using(bucket_id='store-assets' and exists(select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.is_active=true and m.membership_status='active'));
commit;
