-- StoreFlow security audit hardening (2026-11-25)
-- Applied to project tjunaxajcxwxirneopar; keep this file in source control.

-- Make every license gate restrictive. RLS permissive policies are OR'ed;
-- a license-only permissive policy can otherwise bypass tenant/module guards.
do $$
declare r record; v_pred text;
begin
  for r in
    select schemaname,tablename,policyname,cmd
    from pg_policies
    where schemaname='public' and permissive='PERMISSIVE'
      and (coalesce(qual,'') ilike '%has_active_store_license%'
        or coalesce(with_check,'') ilike '%has_active_store_license%')
  loop
    v_pred := 'private.is_org_member(organization_id) AND private.has_active_store_license(organization_id)';
    execute format('drop policy %I on %I.%I',r.policyname,r.schemaname,r.tablename);
    if r.cmd='INSERT' then
      execute format('create policy %I on %I.%I as restrictive for insert to authenticated with check (%s)',
        r.policyname,r.schemaname,r.tablename,v_pred);
    elsif r.cmd='UPDATE' then
      execute format('create policy %I on %I.%I as restrictive for update to authenticated using (%s) with check (%s)',
        r.policyname,r.schemaname,r.tablename,v_pred,v_pred);
    elsif r.cmd='DELETE' then
      execute format('create policy %I on %I.%I as restrictive for delete to authenticated using (%s)',
        r.policyname,r.schemaname,r.tablename,v_pred);
    end if;
  end loop;
end $$;

-- Prevent clients from calling the lower-level checkout RPC directly. POS
-- payments must pass through create_pos_sale_with_payment, which validates
-- enabled payment methods and pending/verified payment states.
revoke all on function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric)
  from public,anon,authenticated;

-- Export store-owned data only. The caller must be an active store owner.
create or replace function public.storeflow_export_json(p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_table text;
  v_rows jsonb;
  v_tables jsonb := '{}'::jsonb;
  v_allowed text[] := array[
    'organization_business_settings','organization_hardware_settings','store_profiles',
    'store_payment_settings','suppliers','customers','employees','products','product_costs',
    'shifts','attendance','leave_requests','sales','sale_items','stock_movements',
    'expenses','document_sequences','business_document_sequences','business_documents',
    'business_document_items','business_document_attachments','payroll_periods','payroll_items',
    'payment_slips','customer_credit_ledger','pos_payment_events','role_permissions','audit_logs'
  ];
begin
  if v_user is null then raise exception using errcode='28000', message='Authentication required'; end if;
  select role into v_role from public.organization_members
  where organization_id=p_organization_id and user_id=v_user
    and is_active and membership_status='active';
  if v_role <> 'owner' then raise exception using errcode='42501', message='เฉพาะเจ้าของร้านเท่านั้น'; end if;
  foreach v_table in array v_allowed loop
    if exists (select 1 from information_schema.columns where table_schema='public'
      and table_name=v_table and column_name='organization_id') then
      execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I t where organization_id=$1',v_table)
        into v_rows using p_organization_id;
      v_tables := v_tables || jsonb_build_object(v_table,coalesce(v_rows,'[]'::jsonb));
    end if;
  end loop;
  return jsonb_build_object('app','StoreFlow','schema_version',1,
    'organization_id',p_organization_id,'exported_at',now(),'tables',v_tables);
end;
$$;
revoke all on function public.storeflow_export_json(uuid) from public,anon;
grant execute on function public.storeflow_export_json(uuid) to authenticated;

-- Import uses merge-only semantics and validates every foreign-key reference
-- against the same organization before inserting; auth.users references must
-- be active members of that same organization.
create or replace function public.storeflow_import_json(p_organization_id uuid,p_backup jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_table text;
  v_rows jsonb;
  v_count integer;
  v_result jsonb := '{}'::jsonb;
  v_fk record;
  v_match text;
  v_nonnull text;
  v_scope text;
  v_invalid boolean;
  v_order text[] := array[
    'organization_business_settings','organization_hardware_settings','store_profiles',
    'store_payment_settings','suppliers','customers','employees','products','product_costs',
    'shifts','attendance','leave_requests','sales','sale_items','stock_movements',
    'expenses','document_sequences','business_document_sequences','business_documents',
    'business_document_items','business_document_attachments','payroll_periods','payroll_items',
    'payment_slips','customer_credit_ledger','pos_payment_events','role_permissions','audit_logs'
  ];
begin
  if v_user is null then raise exception using errcode='28000', message='Authentication required'; end if;
  select role into v_role from public.organization_members where organization_id=p_organization_id
    and user_id=v_user and is_active and membership_status='active';
  if v_role <> 'owner' then raise exception using errcode='42501', message='เฉพาะเจ้าของร้านเท่านั้น'; end if;
  if pg_column_size(p_backup)>8*1024*1024 then
    raise exception using errcode='22023', message='ไฟล์สำรองมีขนาดเกิน 8 MB';
  end if;
  if jsonb_typeof(p_backup)<>'object' or p_backup->>'app'<>'StoreFlow'
    or p_backup->>'schema_version'<>'1' or p_backup->>'organization_id'<>p_organization_id::text
    or jsonb_typeof(p_backup->'tables')<>'object' then
    raise exception using errcode='22023', message='ไฟล์สำรองไม่ถูกต้อง หรือไม่ใช่ข้อมูลของร้านนี้';
  end if;

  foreach v_table in array v_order loop
    v_rows := p_backup->'tables'->v_table;
    if v_rows is null then continue; end if;
    if jsonb_typeof(v_rows)<>'array' then
      raise exception using errcode='22023', message='รูปแบบข้อมูลตารางไม่ถูกต้อง: '||v_table;
    end if;
    if jsonb_array_length(v_rows)>20000 then
      raise exception using errcode='22023', message='จำนวนข้อมูลเกินขีดจำกัดในตาราง: '||v_table;
    end if;
    if not exists(select 1 from information_schema.columns where table_schema='public'
      and table_name=v_table and column_name='organization_id') then continue; end if;
    if jsonb_array_length(v_rows)=0 then
      v_result:=v_result||jsonb_build_object(v_table,0); continue;
    end if;

    select jsonb_agg(jsonb_set(x,'{organization_id}',to_jsonb(p_organization_id),true))
      into v_rows from jsonb_array_elements(v_rows) x;

    for v_fk in
      select c.oid,c.conname,tn.nspname target_schema,tc.relname target_table,
        exists(select 1 from information_schema.columns ic where ic.table_schema=tn.nspname
          and ic.table_name=tc.relname and ic.column_name='organization_id') has_org_id,
        (tn.nspname='auth' and tc.relname='users') is_auth_user
      from pg_constraint c join pg_class tc on tc.oid=c.confrelid
      join pg_namespace tn on tn.oid=tc.relnamespace
      where c.contype='f' and c.conrelid=format('public.%I',v_table)::regclass
    loop
      select string_agg(format('t.%I::text = r->>%L',ta.attname,sa.attname),' AND ' order by k.ord),
        string_agg(format('(r->>%L) IS NOT NULL',sa.attname),' AND ' order by k.ord)
      into v_match,v_nonnull
      from pg_constraint c cross join lateral unnest(c.conkey,c.confkey) with ordinality k(src_att,dst_att,ord)
      join pg_attribute sa on sa.attrelid=c.conrelid and sa.attnum=k.src_att
      join pg_attribute ta on ta.attrelid=c.confrelid and ta.attnum=k.dst_att
      where c.oid=v_fk.oid;
      v_scope:='';
      if v_fk.has_org_id then
        v_scope:=' AND t.organization_id=$2';
      elsif v_fk.is_auth_user then
        v_scope:=' AND EXISTS (SELECT 1 FROM public.organization_members m WHERE m.organization_id=$2
          AND m.user_id=t.id AND m.is_active=true AND m.membership_status=''active'')';
      end if;
      execute format('SELECT EXISTS(SELECT 1 FROM jsonb_array_elements($1) r WHERE %s
        AND NOT EXISTS(SELECT 1 FROM %I.%I t WHERE %s %s))',
        v_nonnull,v_fk.target_schema,v_fk.target_table,v_match,v_scope)
        into v_invalid using v_rows,p_organization_id;
      if v_invalid then
        raise exception using errcode='23503',
          message='ข้อมูลสำรองมีการอ้างอิงข้ามร้านหรือข้อมูลอ้างอิงไม่ถูกต้อง: '||v_table||'.'||v_fk.conname;
      end if;
    end loop;

    execute format('insert into public.%I select * from jsonb_populate_recordset(null::public.%I,$1) on conflict do nothing',v_table,v_table)
      using v_rows;
    get diagnostics v_count=row_count;
    v_result:=v_result||jsonb_build_object(v_table,v_count);
  end loop;
  return jsonb_build_object('restored',v_result,'mode','merge_no_overwrite');
end;
$$;
revoke all on function public.storeflow_import_json(uuid,jsonb) from public,anon;
grant execute on function public.storeflow_import_json(uuid,jsonb) to authenticated;

-- Account deletion: never delete a co-owned store; require ownership transfer
-- when employees/members remain and no second owner exists.
create or replace function public.storeflow_prepare_account_deletion(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_owned_org_ids uuid[] := array[]::uuid[];
  v_delete_org_ids uuid[] := array[]::uuid[];
  v_retained_org_ids uuid[] := array[]::uuid[];
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception using errcode='42501',message='Service role required';
  end if;
  if p_user_id is null then raise exception using errcode='22023',message='User ID required'; end if;
  select coalesce(array_agg(m.organization_id),array[]::uuid[]) into v_owned_org_ids
  from public.organization_members m where m.user_id=p_user_id and m.role='owner'
    and m.is_active and m.membership_status='active';
  select coalesce(array_agg(x.organization_id),array[]::uuid[]) into v_retained_org_ids
  from unnest(v_owned_org_ids) as x(organization_id)
  where exists(select 1 from public.organization_members m where m.organization_id=x.organization_id
    and m.user_id<>p_user_id and m.role='owner' and m.is_active and m.membership_status='active');
  if exists(select 1 from unnest(v_owned_org_ids) as x(organization_id)
    where not(x.organization_id=any(v_retained_org_ids))
    and exists(select 1 from public.organization_members m where m.organization_id=x.organization_id
      and m.user_id<>p_user_id and m.is_active and m.membership_status='active')) then
    raise exception using errcode='55000',
      message='กรุณาโอนสิทธิ์เจ้าของร้านให้เจ้าของคนอื่นก่อนลบบัญชี เพื่อป้องกันข้อมูลร้านสูญหาย';
  end if;
  select coalesce(array_agg(x.organization_id),array[]::uuid[]) into v_delete_org_ids
  from unnest(v_owned_org_ids) as x(organization_id)
  where not(x.organization_id=any(v_retained_org_ids));
  if exists(select 1 from public.organization_subscriptions s where s.organization_id=any(v_delete_org_ids)
    and s.status in ('active','trialing','past_due','incomplete')
    and (s.stripe_subscription_id is not null or s.stripe_customer_id is not null)) then
    raise exception using errcode='55000',
      message='กรุณายกเลิกการเรียกเก็บเงินภายนอกก่อนลบบัญชีและร้านค้า';
  end if;
  delete from private.customer_credit_payment_requests where created_by=p_user_id;
  delete from private.pos_order_idempotency where created_by=p_user_id;
  update public.audit_logs set actor_id=null where actor_id=p_user_id;
  update public.business_document_attachments set created_by=null where created_by=p_user_id;
  update public.business_documents set created_by=null where created_by=p_user_id;
  update public.customer_credit_ledger set created_by=null where created_by=p_user_id;
  update public.expenses set created_by=null where created_by=p_user_id;
  update public.leave_requests set approved_by=null where approved_by=p_user_id;
  update public.payment_slips set uploaded_by=null where uploaded_by=p_user_id;
  update public.payroll_periods set approved_by=null where approved_by=p_user_id;
  update public.sales set cashier_id=null where cashier_id=p_user_id;
  update public.stock_movements set created_by=null where created_by=p_user_id;
  update public.store_payment_settings set updated_by=null where updated_by=p_user_id;
  update public.store_slip_provider_credentials set configured_by=null where configured_by=p_user_id;
  update public.employees set user_id=null,full_name='อดีตพนักงาน',phone=null,
    emergency_contact='{}'::jsonb,payment_channel='{}'::jsonb,
    bank_account_name=null,bank_account_number=null,bank_name=null where user_id=p_user_id;
  if cardinality(v_delete_org_ids)>0 then
    delete from public.organizations where id=any(v_delete_org_ids);
  end if;
  return jsonb_build_object('deleted_owned_stores',cardinality(v_delete_org_ids),
    'deleted_org_ids',to_jsonb(v_delete_org_ids),'retained_shared_org_ids',to_jsonb(v_retained_org_ids),
    'preserved_shared_store_data',true,'anonymized_employee_profiles',true);
end;
$$;
revoke all on function public.storeflow_prepare_account_deletion(uuid) from public,anon,authenticated;
grant execute on function public.storeflow_prepare_account_deletion(uuid) to service_role;

-- Cover foreign keys flagged by the performance advisor.
create index if not exists customer_credit_payment_requests_created_by_idx on private.customer_credit_payment_requests(created_by);
create index if not exists customer_credit_payment_requests_customer_id_idx on private.customer_credit_payment_requests(customer_id);
create index if not exists customer_credit_ledger_created_by_idx on public.customer_credit_ledger(created_by);
create index if not exists customer_credit_ledger_customer_id_idx on public.customer_credit_ledger(customer_id);
create index if not exists customer_credit_ledger_sale_id_idx on public.customer_credit_ledger(sale_id);
create index if not exists payment_slips_sale_id_idx on public.payment_slips(sale_id);
create index if not exists payment_slips_uploaded_by_idx on public.payment_slips(uploaded_by);
create index if not exists pos_payment_events_organization_id_idx on public.pos_payment_events(organization_id);
create index if not exists pos_payment_events_sale_id_idx on public.pos_payment_events(sale_id);
create index if not exists store_payment_settings_updated_by_idx on public.store_payment_settings(updated_by);
create index if not exists store_slip_provider_credentials_configured_by_idx on public.store_slip_provider_credentials(configured_by);
