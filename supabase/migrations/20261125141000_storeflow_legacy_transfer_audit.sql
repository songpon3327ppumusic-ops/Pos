-- Flag historical paid bank transfers that do not have verifiable slip evidence.
-- Add an explicit state instead of silently treating old sales as verified.

begin;
alter table public.sales drop constraint if exists sales_verification_status_check;
alter table public.sales add constraint sales_verification_status_check
 check (verification_status in ('not_required','pending_review','verified','manual_verified','rejected','legacy_unverified'));

update public.sales
set verification_status='legacy_unverified',
    verification_provider='legacy_import',
    verification_response=jsonb_build_object('reason','legacy_paid_transfer_without_verified_slip','flagged_at',now())
where payment_status='paid'
 and payment_method in ('QR PromptPay','โอนเงิน','bank_transfer','transfer')
 and (nullif(trim(slip_url),'') is null or nullif(trim(transaction_ref),'') is null
      or verification_status not in ('verified','manual_verified'));

drop policy if exists store_slip_provider_credentials_service_access on public.store_slip_provider_credentials;
create policy store_slip_provider_credentials_service_access
on public.store_slip_provider_credentials for all to service_role
using (true) with check (true);

drop policy if exists pos_payment_events_service_access on public.pos_payment_events;
create policy pos_payment_events_service_access
on public.pos_payment_events for all to service_role
using (true) with check (true);
commit;