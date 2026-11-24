-- Correct organization visibility policy for authenticated organization members.
drop policy if exists "organization members read org" on public.organizations;

create policy "organization members read org"
on public.organizations
for select
to authenticated
using (
  exists (
    select 1
    from public.organization_members m
    where m.organization_id = organizations.id
      and m.user_id = (select auth.uid())
      and m.is_active = true
  )
);
