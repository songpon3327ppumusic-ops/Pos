create table if not exists public.store_profiles (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  legal_name text, display_name text, branch_name text default 'สำนักงานใหญ่', branch_code text default '00000',
  tax_id text, vat_registered boolean not null default false, phone text, email text, address text, logo_url text,
  updated_at timestamptz not null default now()
);
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  supplier_code text not null, name text not null, tax_id text, phone text, email text, address text, contact_name text,
  is_active boolean not null default true, created_at timestamptz not null default now(), unique (organization_id, supplier_code)
);
create table if not exists public.document_sequences (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  document_type text not null, prefix text not null, sequence_year integer not null,
  next_number bigint not null default 1 check (next_number > 0), updated_at timestamptz not null default now(),
  unique (organization_id, document_type, sequence_year)
);
create table if not exists public.business_documents (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  document_type text not null check (document_type in ('quotation','invoice','receipt','tax_invoice','abbreviated_tax_invoice','credit_note','debit_note','purchase_order','goods_receipt','delivery_note','sales_return','purchase_return','stock_transfer','stock_count','receipt_voucher','payment_voucher','petty_cash_voucher','payroll_slip')),
  document_no text not null, status text not null default 'draft' check (status in ('draft','issued','paid','partially_paid','void','cancelled')),
  related_document_id uuid references public.business_documents(id), customer_id uuid references public.customers(id), supplier_id uuid references public.suppliers(id),
  source_sale_id uuid references public.sales(id), issue_date date not null default current_date, due_date date,
  party_name text, party_tax_id text, party_branch_code text, party_address text,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0), discount numeric(14,2) not null default 0 check (discount >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0), tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total numeric(14,2) not null default 0 check (total >= 0), notes text, metadata jsonb not null default '{}'::jsonb,
  issued_at timestamptz, created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), unique (organization_id, document_no)
);
create table if not exists public.business_document_items (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.business_documents(id) on delete cascade, product_id uuid references public.products(id),
  description text not null, quantity numeric(14,3) not null default 1 check (quantity > 0), unit text not null default 'รายการ',
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0), discount numeric(14,2) not null default 0 check (discount >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0), line_total numeric(14,2) not null default 0 check (line_total >= 0),
  sort_order integer not null default 0, created_at timestamptz not null default now()
);
create index if not exists business_documents_org_date_idx on public.business_documents(organization_id, issue_date desc);
create index if not exists business_documents_org_type_idx on public.business_documents(organization_id, document_type, status);
create index if not exists business_document_items_doc_idx on public.business_document_items(organization_id, document_id);
alter table public.store_profiles enable row level security;
alter table public.suppliers enable row level security;
alter table public.document_sequences enable row level security;
alter table public.business_documents enable row level security;
alter table public.business_document_items enable row level security;
drop policy if exists store_profiles_read on public.store_profiles;
create policy store_profiles_read on public.store_profiles for select to authenticated using (private.has_module_access(organization_id,'documents','read'));
drop policy if exists store_profiles_write on public.store_profiles;
create policy store_profiles_write on public.store_profiles for all to authenticated using (private.has_module_access(organization_id,'documents','update')) with check (private.has_module_access(organization_id,'documents','update'));
drop policy if exists suppliers_select on public.suppliers;
create policy suppliers_select on public.suppliers for select to authenticated using (private.has_module_access(organization_id,'purchasing','read'));
drop policy if exists suppliers_insert on public.suppliers;
create policy suppliers_insert on public.suppliers for insert to authenticated with check (private.has_module_access(organization_id,'purchasing','create'));
drop policy if exists suppliers_update on public.suppliers;
create policy suppliers_update on public.suppliers for update to authenticated using (private.has_module_access(organization_id,'purchasing','update')) with check (private.has_module_access(organization_id,'purchasing','update'));
drop policy if exists suppliers_delete on public.suppliers;
create policy suppliers_delete on public.suppliers for delete to authenticated using (private.has_module_access(organization_id,'purchasing','delete'));
drop policy if exists document_sequences_read on public.document_sequences;
create policy document_sequences_read on public.document_sequences for select to authenticated using (private.has_module_access(organization_id,'documents','read'));
drop policy if exists document_sequences_write on public.document_sequences;
create policy document_sequences_write on public.document_sequences for all to authenticated using (private.has_module_access(organization_id,'documents','update')) with check (private.has_module_access(organization_id,'documents','update'));
drop policy if exists business_documents_select on public.business_documents;
create policy business_documents_select on public.business_documents for select to authenticated using (private.has_module_access(organization_id,'documents','read'));
drop policy if exists business_documents_insert on public.business_documents;
create policy business_documents_insert on public.business_documents for insert to authenticated with check (private.has_module_access(organization_id,'documents','create'));
drop policy if exists business_documents_update on public.business_documents;
create policy business_documents_update on public.business_documents for update to authenticated using (private.has_module_access(organization_id,'documents','update')) with check (private.has_module_access(organization_id,'documents','update'));
drop policy if exists business_documents_delete on public.business_documents;
create policy business_documents_delete on public.business_documents for delete to authenticated using (private.has_module_access(organization_id,'documents','delete'));
drop policy if exists business_document_items_select on public.business_document_items;
create policy business_document_items_select on public.business_document_items for select to authenticated using (private.has_module_access(organization_id,'documents','read'));
drop policy if exists business_document_items_insert on public.business_document_items;
create policy business_document_items_insert on public.business_document_items for insert to authenticated with check (private.has_module_access(organization_id,'documents','create'));
drop policy if exists business_document_items_update on public.business_document_items;
create policy business_document_items_update on public.business_document_items for update to authenticated using (private.has_module_access(organization_id,'documents','update')) with check (private.has_module_access(organization_id,'documents','update'));
drop policy if exists business_document_items_delete on public.business_document_items;
create policy business_document_items_delete on public.business_document_items for delete to authenticated using (private.has_module_access(organization_id,'documents','delete'));
insert into public.role_permissions(organization_id,role,module,action,allowed)
select o.id,r.role,m.module,a.action,
case when r.role in ('manager','accountant') and a.action in ('read','create','update') then true
when r.role='cashier' and m.module='documents' and a.action in ('read','create') then true else false end
from public.organizations o cross join (values ('manager'),('accountant'),('cashier')) r(role)
cross join (values ('documents'),('purchasing')) m(module)
cross join (values ('read'),('create'),('update'),('delete'),('approve')) a(action)
on conflict (organization_id,role,module,action) do update set allowed=excluded.allowed;
update public.subscription_plans set features=features||'{"documents":true,"basic_documents":true,"quotes":true,"receipts":true}'::jsonb,updated_at=now() where id='starter';
update public.subscription_plans set features=features||'{"documents":true,"basic_documents":true,"quotes":true,"receipts":true,"tax_documents":true,"purchasing":true,"delivery":true}'::jsonb,updated_at=now() where id in ('pro','business','lifetime');
update public.subscription_plans set features=features||'{"documents":false,"basic_documents":false,"quotes":false,"receipts":true}'::jsonb,updated_at=now() where id='free';
