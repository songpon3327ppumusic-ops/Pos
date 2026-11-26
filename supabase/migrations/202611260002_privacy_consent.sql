create table if not exists public.privacy_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  consent_version text not null,
  terms_version text not null,
  privacy_policy_url text not null,
  accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table public.privacy_consents enable row level security;
drop policy if exists privacy_consents_select_own on public.privacy_consents;
create policy privacy_consents_select_own on public.privacy_consents
for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists privacy_consents_insert_own on public.privacy_consents;
create policy privacy_consents_insert_own on public.privacy_consents
for insert to authenticated with check ((select auth.uid()) = user_id);
grant select, insert on public.privacy_consents to authenticated;
create index if not exists privacy_consents_user_accepted_idx
on public.privacy_consents(user_id, accepted_at desc);
