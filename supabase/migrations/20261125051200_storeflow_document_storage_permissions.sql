-- Restrict private business document uploads by tenant and module permission.
drop policy if exists business_documents_storage_insert on storage.objects;
create policy business_documents_storage_insert on storage.objects
for insert to authenticated with check (
 bucket_id='business-documents'
 and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and (
   ((storage.foldername(name))[2]='settings' and exists(
     select 1 from public.organization_members m
     where m.organization_id=((storage.foldername(name))[1])::uuid
       and m.user_id=(select auth.uid()) and m.is_active
       and m.membership_status='active' and m.role in ('owner','admin')
   ))
   or
   ((storage.foldername(name))[2]='documents'
     and private.has_module_access(((storage.foldername(name))[1])::uuid,'documents','create'))
 )
);
drop policy if exists business_documents_storage_delete on storage.objects;
create policy business_documents_storage_delete on storage.objects
for delete to authenticated using (
 bucket_id='business-documents'
 and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
 and (
   ((storage.foldername(name))[2]='settings' and exists(
     select 1 from public.organization_members m
     where m.organization_id=((storage.foldername(name))[1])::uuid
       and m.user_id=(select auth.uid()) and m.is_active
       and m.membership_status='active' and m.role in ('owner','admin')
   ))
   or
   ((storage.foldername(name))[2]='documents'
     and private.has_module_access(((storage.foldername(name))[1])::uuid,'documents','delete'))
 )
);