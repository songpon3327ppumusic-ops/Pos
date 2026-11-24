-- Grandfather existing Free stores with a fresh 7-day transition trial; do not unexpectedly lock legacy tenants.
update public.organization_subscriptions
set status='trialing',trial_started_at=now(),trial_ends_at=now()+interval '7 days',updated_at=now()
where status='free' and plan_id='free' and trial_ends_at<=now();