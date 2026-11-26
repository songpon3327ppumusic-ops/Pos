-- Private tenant-scoped cloud snapshots, 7-version retention, and v2 document-aware export/restore.
create table if not exists public.store_backups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id),
  backup_type text not null check (backup_type in ('manual','automatic')),
  file_path text not null unique,
  file_size bigint not null check (file_size between 1 and 8388608),
  schema_version integer not null default 2 check (schema_version = 2),
  created_at timestamptz not null default now()
);
alter table public.store_backups alter column created_by set default auth.uid();
create index if not exists store_backups_org_created_idx on public.store_backups(organization_id, created_at desc);
alter table public.store_backups enable row level security;
revoke all on public.store_backups from anon, public;
grant select, insert, delete on public.store_backups to authenticated;

drop policy if exists store_backups_owner_select on public.store_backups;
create policy store_backups_owner_select on public.store_backups for select to authenticated
using (exists (select 1 from public.organization_members m where m.organization_id=store_backups.organization_id and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists store_backups_owner_insert on public.store_backups;
create policy store_backups_owner_insert on public.store_backups for insert to authenticated
with check (created_by=(select auth.uid()) and exists (select 1 from public.organization_members m where m.organization_id=store_backups.organization_id and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists store_backups_owner_delete on public.store_backups;
create policy store_backups_owner_delete on public.store_backups for delete to authenticated
using (exists (select 1 from public.organization_members m where m.organization_id=store_backups.organization_id and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('storeflow-backups','storeflow-backups',false,8388608,array['application/json'])
on conflict (id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['application/json'];

drop policy if exists storeflow_backups_owner_upload on storage.objects;
create policy storeflow_backups_owner_upload on storage.objects for insert to authenticated
with check (bucket_id='storeflow-backups' and exists (select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists storeflow_backups_owner_read on storage.objects;
create policy storeflow_backups_owner_read on storage.objects for select to authenticated
using (bucket_id='storeflow-backups' and exists (select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));
drop policy if exists storeflow_backups_owner_delete on storage.objects;
create policy storeflow_backups_owner_delete on storage.objects for delete to authenticated
using (bucket_id='storeflow-backups' and exists (select 1 from public.organization_members m where m.organization_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active'));

create or replace function private.storeflow_prune_backups() returns trigger
language plpgsql security definer set search_path=''
as $$
begin
 delete from storage.objects o using (
   select file_path from public.store_backups where organization_id=new.organization_id order by created_at desc offset 7
 ) old where o.bucket_id='storeflow-backups' and o.name=old.file_path;
 delete from public.store_backups b where b.organization_id=new.organization_id and b.id in (
   select id from public.store_backups where organization_id=new.organization_id order by created_at desc offset 7
 );
 return new;
end; $$;
revoke all on function private.storeflow_prune_backups() from public,anon,authenticated;
drop trigger if exists storeflow_prune_backups_after_insert on public.store_backups;
create trigger storeflow_prune_backups_after_insert after insert on public.store_backups for each row execute function private.storeflow_prune_backups();

create or replace function public.storeflow_export_backup_v2(p_organization_id uuid) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_role text; v_backup jsonb; v_tables jsonb;
begin
 select role into v_role from public.organization_members where organization_id=p_organization_id and user_id=v_user and is_active and membership_status='active';
 if v_user is null or v_role is distinct from 'owner' then raise exception using errcode='42501',message='เฉพาะเจ้าของร้านเท่านั้น'; end if;
 v_backup:=public.storeflow_export_json(p_organization_id); v_tables:=v_backup->'tables';
 if to_regclass('public.store_documents') is not null then
  v_tables:=v_tables||jsonb_build_object('store_documents',coalesce((select jsonb_agg(to_jsonb(d)) from public.store_documents d where d.organization_id=p_organization_id),'[]'::jsonb));
 end if;
 if to_regclass('public.documents') is not null then
  v_tables:=v_tables||jsonb_build_object('documents',coalesce((select jsonb_agg(to_jsonb(d)) from public.documents d where d.store_id=p_organization_id),'[]'::jsonb));
 end if;
 if to_regclass('public.document_items') is not null then
  v_tables:=v_tables||jsonb_build_object('document_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.document_items i where i.store_id=p_organization_id),'[]'::jsonb));
 end if;
 return jsonb_build_object('app','StoreFlow','schema_version',2,'organization_id',p_organization_id,'exported_at',now(),'tables',v_tables);
end; $$;
revoke all on function public.storeflow_export_backup_v2(uuid) from public,anon;
grant execute on function public.storeflow_export_backup_v2(uuid) to authenticated;

create or replace function public.storeflow_restore_backup_v2(p_organization_id uuid,p_backup jsonb,p_mode text default 'merge') returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid:=auth.uid(); v_role text; v_base jsonb; v_result jsonb; v_table text; v_rows jsonb;
 v_delete_order text[]:=array['document_items','documents','store_documents','audit_logs','role_permissions','pos_payment_events','customer_credit_ledger','payment_slips','payroll_items','payroll_periods','business_document_attachments','business_document_items','business_documents','business_document_sequences','document_sequences','expenses','stock_movements','sale_items','sales','leave_requests','attendance','shifts','product_costs','products','employees','customers','suppliers','store_payment_settings','store_profiles','organization_hardware_settings','organization_business_settings'];
begin
 select role into v_role from public.organization_members where organization_id=p_organization_id and user_id=v_user and is_active and membership_status='active';
 if v_user is null or v_role is distinct from 'owner' then raise exception using errcode='42501',message='เฉพาะเจ้าของร้านเท่านั้น'; end if;
 if p_mode not in ('merge','replace') then raise exception using errcode='22023',message='รูปแบบการกู้คืนไม่ถูกต้อง'; end if;
 if jsonb_typeof(p_backup)<>'object' or p_backup->>'app'<>'StoreFlow' or p_backup->>'schema_version'<>'2' or p_backup->>'organization_id'<>p_organization_id::text or jsonb_typeof(p_backup->'tables')<>'object' or pg_column_size(p_backup)>8*1024*1024 then
  raise exception using errcode='22023',message='ไฟล์สำรองไม่ถูกต้อง หรือไม่ใช่ข้อมูลของร้านนี้';
 end if;
 if p_mode='replace' then
  foreach v_table in array v_delete_order loop
   if to_regclass(format('public.%I',v_table)) is null then continue; end if;
   if v_table in ('document_items','documents') then execute format('delete from public.%I where store_id=$1',v_table) using p_organization_id;
   elsif v_table='store_documents' then execute 'delete from public.store_documents where organization_id=$1' using p_organization_id;
   elsif exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_table and column_name='organization_id') then
    execute format('delete from public.%I where organization_id=$1',v_table) using p_organization_id;
   end if;
  end loop;
 end if;
 v_base:=jsonb_set(p_backup-'schema_version'-'tables','{schema_version}','1'::jsonb,true);
 v_base:=jsonb_set(v_base,'{tables}',(p_backup->'tables')-'store_documents'-'documents'-'document_items',true);
 v_result:=public.storeflow_import_json(p_organization_id,v_base);
 foreach v_table in array array['store_documents','documents','document_items'] loop
  v_rows:=p_backup->'tables'->v_table;
  if v_rows is null then continue; end if;
  if jsonb_typeof(v_rows)<>'array' or jsonb_array_length(v_rows)>20000 then raise exception using errcode='22023',message='ข้อมูลเอกสารในไฟล์สำรองไม่ถูกต้อง'; end if;
  if jsonb_array_length(v_rows)=0 then continue; end if;
  if v_table='store_documents' then
   execute 'insert into public.store_documents select * from jsonb_populate_recordset(null::public.store_documents,$1) on conflict do nothing'
   using (select jsonb_agg(jsonb_set(x,'{organization_id}',to_jsonb(p_organization_id),true)) from jsonb_array_elements(v_rows) x);
  elsif v_table='documents' then
   execute 'insert into public.documents select * from jsonb_populate_recordset(null::public.documents,$1) on conflict do nothing'
   using (select jsonb_agg(jsonb_set(x,'{store_id}',to_jsonb(p_organization_id),true)) from jsonb_array_elements(v_rows) x);
  else
   execute 'insert into public.document_items select * from jsonb_populate_recordset(null::public.document_items,$1) on conflict do nothing'
   using (select jsonb_agg(jsonb_set(x,'{store_id}',to_jsonb(p_organization_id),true)) from jsonb_array_elements(v_rows) x);
  end if;
 end loop;
 return jsonb_build_object('mode',p_mode,'result',v_result);
end; $$;
revoke all on function public.storeflow_restore_backup_v2(uuid,jsonb,text) from public,anon;
grant execute on function public.storeflow_restore_backup_v2(uuid,jsonb,text) to authenticated;
