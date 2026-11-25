begin;
alter table public.sales add column if not exists stripe_checkout_session_id text, add column if not exists payment_attempt integer not null default 0, add column if not exists payment_attempt_started_at timestamptz;
alter table public.sales drop constraint if exists sales_payment_attempt_nonnegative;
alter table public.sales add constraint sales_payment_attempt_nonnegative check(payment_attempt>=0);
create or replace function public.claim_storeflow_pos_stripe_checkout(p_organization_id uuid,p_sale_id uuid,p_user_id uuid,p_expected_session_id text default null)
returns integer language plpgsql security definer set search_path=''
as $function$
declare v_attempt integer;
begin
 if p_user_id is null then raise exception using errcode='28000',message='Authentication required';end if;
 if not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=p_user_id and m.is_active and m.membership_status='active' and m.role in ('owner','admin','manager','cashier')) then raise exception using errcode='42501',message='Not authorized';end if;
 if not exists(select 1 from public.store_payment_settings s where s.organization_id=p_organization_id and s.stripe_enabled and s.stripe_charges_enabled and s.stripe_webhook_verified and s.stripe_connect_account_id is not null) then raise exception using errcode='55000',message='Stripe is not enabled for this store';end if;
 update public.sales set payment_attempt=payment_attempt+1,payment_attempt_started_at=now(),stripe_checkout_session_id=null,payment_status='pending',status='pending_payment'
 where id=p_sale_id and organization_id=p_organization_id and payment_method='Stripe Online' and payment_status in ('pending','failed')
 and stripe_checkout_session_id is not distinct from p_expected_session_id
 and (payment_attempt_started_at is null or payment_attempt_started_at<now()-interval '2 minutes')
 returning payment_attempt into v_attempt;
 if v_attempt is null then raise exception using errcode='55000',message='A Stripe checkout attempt is already being created or the sale has changed. Refresh and retry.';end if;
 return v_attempt;
end;$function$;
revoke all on function public.claim_storeflow_pos_stripe_checkout(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.claim_storeflow_pos_stripe_checkout(uuid,uuid,uuid,text) to service_role;
commit;
