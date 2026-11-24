create or replace function public.bootstrap_store_owner(p_org_slug text default 'storeflow')
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_template_org uuid;
  v_store_name text;
  v_slug text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select organization_id into v_org
  from public.organization_members
  where user_id = v_user and is_active = true
  order by created_at
  limit 1;
  if v_org is not null then return v_org; end if;

  select id into v_template_org from public.organizations where slug = p_org_slug limit 1;
  if v_template_org is null then raise exception 'Store template not found'; end if;

  select coalesce(
    nullif(trim(raw_user_meta_data->>'store_name'), ''),
    nullif(trim(raw_user_meta_data->>'full_name'), '') || ' Shop',
    'ร้านค้าใหม่'
  ) into v_store_name from auth.users where id = v_user;

  v_slug := coalesce(nullif(regexp_replace(lower(trim(p_org_slug)), '[^a-z0-9-]+', '-', 'g'), ''), 'store')
    || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);

  insert into public.organizations(name, slug) values (v_store_name, v_slug) returning id into v_org;
  insert into public.profiles (id, display_name)
  select v_user, coalesce(nullif(trim(raw_user_meta_data->>'full_name'), ''), split_part(email, '@', 1))
  from auth.users where id = v_user on conflict (id) do nothing;

  insert into public.organization_members (organization_id, user_id, role, is_active)
  values (v_org, v_user, 'owner', true)
  on conflict (organization_id, user_id) do update set role = 'owner', is_active = true;

  insert into public.organization_subscriptions(organization_id, plan_id, billing_interval, status)
  values (v_org, 'free', 'month', 'free') on conflict (organization_id) do nothing;

  insert into public.role_permissions(organization_id, role, module, action, allowed)
  select v_org, role, module, action, allowed
  from public.role_permissions where organization_id = v_template_org
  on conflict do nothing;

  return v_org;
end;
$$;
revoke all on function public.bootstrap_store_owner(text) from public, anon;
grant execute on function public.bootstrap_store_owner(text) to authenticated;
