begin;
revoke all privileges on all tables in schema public from anon;
grant select on public.subscription_plans to anon;
revoke truncate, references, trigger on all tables in schema public from public, anon, authenticated;
revoke all privileges on all sequences in schema public from public, anon;
alter default privileges for role postgres in schema public revoke all privileges on tables from anon;
alter default privileges for role postgres in schema public revoke truncate, references, trigger on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public revoke all privileges on sequences from public, anon;
commit;
