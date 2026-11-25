-- Per-user/per-store rate limiting for sensitive Edge Function actions.
begin;
create table if not exists private.storeflow_edge_rate_limits(
 rate_key text primary key,
 window_started_at timestamptz not null,
 attempts integer not null check(attempts>=0),
 updated_at timestamptz not null default now()
);
alter table private.storeflow_edge_rate_limits enable row level security;
revoke all on private.storeflow_edge_rate_limits from public,anon,authenticated;
grant all on private.storeflow_edge_rate_limits to service_role;

create or replace function public.consume_storeflow_rate_limit(p_key text,p_window_seconds integer,p_limit integer)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare v_attempts integer;v_now timestamptz:=clock_timestamp();
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='Only trusted edge services may consume rate limits';end if;
 if p_key is null or length(p_key)<8 or length(p_key)>180 or p_window_seconds<1 or p_window_seconds>3600 or p_limit<1 or p_limit>100 then
  raise exception using errcode='22023',message='Invalid rate-limit parameters';
 end if;
 insert into private.storeflow_edge_rate_limits(rate_key,window_started_at,attempts,updated_at) values(p_key,v_now,1,v_now)
 on conflict(rate_key) do update set
  attempts=case when private.storeflow_edge_rate_limits.window_started_at<=v_now-make_interval(secs=>p_window_seconds) then 1 else private.storeflow_edge_rate_limits.attempts+1 end,
  window_started_at=case when private.storeflow_edge_rate_limits.window_started_at<=v_now-make_interval(secs=>p_window_seconds) then v_now else private.storeflow_edge_rate_limits.window_started_at end,
  updated_at=v_now
 returning attempts into v_attempts;
 return v_attempts<=p_limit;
end;$function$;
revoke all on function public.consume_storeflow_rate_limit(text,integer,integer) from public,anon,authenticated;
grant execute on function public.consume_storeflow_rate_limit(text,integer,integer) to service_role;
commit;