-- StoreFlow Android: Play billing metadata and document compatibility view.
-- Canonical tenant key is organizations.id / organization_id.
-- Existing business_documents + business_document_items already implement documents,
-- document numbering, VAT modes, delivery/receiving and withholding certificates.
alter table public.organization_subscriptions
  add column if not exists google_play_product_id text,
  add column if not exists google_play_purchase_token_hash text,
  add column if not exists google_play_order_id text,
  add column if not exists google_play_purchase_state text,
  add column if not exists google_play_acknowledged boolean not null default false,
  add column if not exists google_play_verified_at timestamptz,
  add column if not exists google_play_expiry_at timestamptz,
  add column if not exists google_play_latest_order_id text;

create unique index if not exists organization_subscriptions_google_play_token_hash_uidx
  on public.organization_subscriptions (google_play_purchase_token_hash)
  where google_play_purchase_token_hash is not null;

-- Trial is derived from organizations.created_at, not client-controlled.
create or replace view public.store_documents
with (security_invoker = true)
as
select id, organization_id as store_id, organization_id, document_type, document_no,
       status, related_document_id, customer_id, supplier_id, source_sale_id,
       issue_date, due_date, party_name, party_tax_id, party_branch_code, party_address,
       subtotal, discount, tax_rate, tax_amount, total, notes, metadata, issued_at,
       created_by, created_at, updated_at, tax_mode, withholding_condition,
       payment_terms_days, valid_until, transport_reference, stock_posted_at
from public.business_documents;

grant select on public.store_documents to authenticated;
comment on view public.store_documents is
'Compatibility view; store_id aliases organization_id and underlying business_documents RLS applies.';
