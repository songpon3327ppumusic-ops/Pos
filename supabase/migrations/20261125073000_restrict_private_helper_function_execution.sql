begin;
-- Private schema helpers are callable only by authenticated policy/RPC execution.
-- Trigger functions are invoked by PostgreSQL internally and need no client EXECUTE grant.
revoke execute on all functions in schema private from public, anon;
grant execute on function private.has_active_store_license(uuid) to authenticated;
grant execute on function private.has_module_access(uuid,text,text) to authenticated;
grant execute on function private.is_org_manager(uuid) to authenticated;
grant execute on function private.is_org_member(uuid) to authenticated;
grant execute on function private.is_org_owner(uuid) to authenticated;
commit;
