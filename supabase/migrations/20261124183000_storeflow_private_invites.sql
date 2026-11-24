-- Keep invitation secrets out of the member-readable organizations table.
begin;
create table if not exists private.organization_invites(
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 invite_code text not null unique,
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);
alter table private.organization_invites enable row level security;
revoke all on private.organization_invites from public,anon,authenticated;
insert into private.organization_invites(organization_id,invite_code)
select id,invite_code from public.organizations where invite_code is not null
on conflict(organization_id) do update set invite_code=excluded.invite_code;

create or replace function private.handle_storeflow_signup()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,auth,private
as $$
declare
 v_role text:=coalesce(new.raw_user_meta_data->>'onboarding_role','owner');
 v_store_name text:=nullif(trim(new.raw_user_meta_data->>'store_name'),'');
 v_invite text:=upper(regexp_replace(coalesce(new.raw_user_meta_data->>'invite_code',''),'\s','','g'));
 v_org uuid; v_template uuid; v_slug text; v_code text;
begin
 if v_role not in ('owner','cashier') then raise exception 'Invalid onboarding role'; end if;
 insert into public.profiles(id,display_name)
 values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1)))
 on conflict(id) do nothing;
 if v_role='owner' then
  if v_store_name is null or length(v_store_name)<2 or length(v_store_name)>120 then raise exception 'Store name must be between 2 and 120 characters'; end if;
  v_slug:='store-'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,16));
  insert into public.organizations(name,slug,plan_type) values(v_store_name,v_slug,'subscription') returning id into v_org;
  insert into private.organization_invites(organization_id,invite_code) values(v_org,v_code);
  insert into public.organization_members(organization_id,user_id,role,is_active,membership_status) values(v_org,new.id,'owner',true,'active')
  on conflict(organization_id,user_id) do update set role='owner',is_active=true,membership_status='active';
  insert into public.organization_subscriptions(organization_id,plan_id,billing_interval,status,trial_started_at,trial_ends_at,plan_type)
  values(v_org,'free','month','trialing',now(),now()+interval '7 days','subscription')
  on conflict(organization_id) do update set status='trialing',trial_started_at=now(),trial_ends_at=now()+interval '7 days',plan_id='free',plan_type='subscription',updated_at=now();
  select id into v_template from public.organizations where slug='storeflow' limit 1;
  if v_template is not null then
   insert into public.role_permissions(organization_id,role,module,action,allowed)
   select v_org,role,module,action,allowed from public.role_permissions where organization_id=v_template on conflict do nothing;
  end if;
 else
  if v_invite='' then raise exception 'Invite code is required for staff signup'; end if;
  select organization_id into v_org from private.organization_invites where upper(invite_code)=v_invite and is_active limit 1;
  if v_org is null then raise exception 'Invite code is invalid'; end if;
  insert into public.organization_members(organization_id,user_id,role,is_active,membership_status)
  values(v_org,new.id,'cashier',false,'pending')
  on conflict(organization_id,user_id) do update set role='cashier',is_active=false,membership_status='pending';
 end if;
 return new;
end;
$$;

create or replace function public.get_store_invite_code()
returns text language plpgsql stable security definer
set search_path=pg_catalog,public,auth,private
as $$
declare v_code text;
begin
 select i.invite_code into v_code
 from private.organization_invites i
 join public.organization_members m on m.organization_id=i.organization_id
 where m.user_id=(select auth.uid()) and m.role='owner' and m.is_active and m.membership_status='active' and i.is_active
 order by m.created_at limit 1;
 if v_code is null then raise exception 'Only active store owners can view invite code'; end if;
 return v_code;
end;
$$;
revoke all on function public.get_store_invite_code() from public,anon;
grant execute on function public.get_store_invite_code() to authenticated;

alter table public.organizations drop column if exists invite_code;

drop policy if exists sale_items_cashier_today_guard on public.sale_items;
create policy sale_items_cashier_today_guard on public.sale_items as restrictive for select to authenticated
using (not exists(select 1 from public.organization_members m where m.organization_id=sale_items.organization_id and m.user_id=(select auth.uid()) and m.role='cashier' and m.is_active and m.membership_status='active'));

create policy pos_idempotency_deny_all on private.pos_order_idempotency
for all to public using(false) with check(false);
create index if not exists pos_order_idempotency_created_by_idx on private.pos_order_idempotency(created_by);
commit;