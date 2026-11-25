-- Restrict all remaining SECURITY DEFINER helper search paths.
-- Every relation and auth helper in these functions is schema-qualified;
-- built-ins resolve from pg_catalog, so an empty path is safe.
begin;
alter function private.handle_storeflow_signup() set search_path = '';
alter function private.has_active_store_license(uuid) set search_path = '';
alter function private.is_org_manager(uuid) set search_path = '';
alter function private.is_org_owner(uuid) set search_path = '';
commit;
