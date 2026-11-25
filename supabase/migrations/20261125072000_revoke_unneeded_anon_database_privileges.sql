begin;
-- The only intentionally public data endpoint is the active subscription plan catalogue.
revoke all privileges on all tables in schema public from anon;
grant select on table public.subscription_plans to anon;

-- Anonymous clients must not invoke database RPCs; signup trigger functions execute internally.
revoke execute on all functions in schema public from anon;
revoke execute on all functions in schema private from anon;
commit;
