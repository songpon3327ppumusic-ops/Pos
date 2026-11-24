begin;
drop policy if exists organization_invites_deny_all on private.organization_invites;
create policy organization_invites_deny_all on private.organization_invites
for all to public using(false) with check(false);
commit;