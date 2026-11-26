create or replace function private.storeflow_effective_plan(p_organization_id uuid)
returns text
language plpgsql stable security definer
set search_path=''
as $function$
declare v_tier text; v_status text; v_plan_type text; v_trial_end timestamptz; v_period_end timestamptz;
begin
  if auth.uid() is not null and exists (
    select 1 from public.platform_admins a where a.user_id=(select auth.uid())
  ) then return 'lifetime'; end if;
  select lower(coalesce(s.plan_tier,s.plan_id,'basic')),
         lower(coalesce(s.status,'expired')),
         lower(coalesce(s.plan_type,'subscription')),
         s.trial_ends_at,s.current_period_end
    into v_tier,v_status,v_plan_type,v_trial_end,v_period_end
  from public.organization_subscriptions s
  where s.organization_id=p_organization_id;
  if not found then return 'expired'; end if;
  if v_plan_type='lifetime' or v_tier='lifetime' then
    return case when v_status='active' then 'lifetime' else 'expired' end;
  end if;
  if v_status='free' then
    return case when v_tier='free' then 'free' else 'basic' end;
  end if;
  if v_status in ('trial','trialing') then
    return case when v_trial_end is not null and v_trial_end>now() then 'standard' else 'expired' end;
  end if;
  if v_status<>'active' then return 'expired'; end if;
  if v_period_end is not null and v_period_end<=now() then return 'expired'; end if;
  return case
    when v_tier in ('premium','business') then 'premium'
    when v_tier in ('standard','pro') then 'standard'
    when v_tier='free' then 'free'
    else 'basic'
  end;
end;
$function$;
