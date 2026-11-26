create or replace function private.has_active_store_license(p_org uuid)
returns boolean
language sql stable security definer
set search_path=''
as $function$
  select exists (
    select 1 from public.organization_subscriptions s
    where s.organization_id=p_org and (
      (s.status='free' and s.plan_tier in ('free','basic'))
      or (s.plan_type='lifetime' and s.status='active')
      or (s.status='active' and (s.current_period_end is null or s.current_period_end>now()))
      or (s.status in ('trial','trialing') and s.trial_ends_at>now())
    )
  );
$function$;
