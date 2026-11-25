begin;
create table if not exists public.organization_business_settings(
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 legal_name text, display_name text, address text, tax_id text,
 phone text, email text, logo_path text, vat_registered boolean not null default false,
 vat_rate numeric(5,2) not null default 7.00 check(vat_rate between 0 and 100),
 document_prefixes jsonb not null default '{"invoice":"INV","receipt":"RCT","quotation":"QUO","delivery":"DN","goods_receipt":"GRN","withholding":"WHT","payment_voucher":"PV","cash_voucher":"CV","credit_note":"CN"}'::jsonb,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint organization_business_settings_tax_id_chk check(tax_id is null or tax_id ~ '^[0-9]{13}$')
);
create table if not exists public.organization_hardware_settings(
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 receipt_width integer not null default 80 check(receipt_width in (58,80)),
 auto_print boolean not null default false,
 barcode_camera_enabled boolean not null default true,
 cash_drawer_enabled boolean not null default false,
 customer_display_enabled boolean not null default false,
 printer_connection text not null default 'system' check(printer_connection in ('system','serial','bluetooth')),
 printer_name text, receipt_header text, receipt_footer text,
 updated_at timestamptz not null default now()
);
create table if not exists public.business_document_sequences(
 organization_id uuid not null references public.organizations(id) on delete cascade,
 document_month text not null check(document_month ~ '^[0-9]{6}$'),
 document_type text not null,
 last_number bigint not null default 0 check(last_number>=0),
 primary key(organization_id,document_month,document_type)
);
alter table public.organization_business_settings enable row level security;
alter table public.organization_hardware_settings enable row level security;
alter table public.business_document_sequences enable row level security;
drop policy if exists business_settings_member_read on public.organization_business_settings;
create policy business_settings_member_read on public.organization_business_settings for select to authenticated using(private.is_org_member(organization_id));
drop policy if exists business_settings_owner_write on public.organization_business_settings;
create policy business_settings_owner_write on public.organization_business_settings for all to authenticated using(exists(select 1 from public.organization_members m where m.organization_id=organization_business_settings.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin'))) with check(exists(select 1 from public.organization_members m where m.organization_id=organization_business_settings.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin')));
drop policy if exists hardware_settings_member_read on public.organization_hardware_settings;
create policy hardware_settings_member_read on public.organization_hardware_settings for select to authenticated using(private.is_org_member(organization_id));
drop policy if exists hardware_settings_owner_write on public.organization_hardware_settings;
create policy hardware_settings_owner_write on public.organization_hardware_settings for all to authenticated using(exists(select 1 from public.organization_members m where m.organization_id=organization_hardware_settings.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin'))) with check(exists(select 1 from public.organization_members m where m.organization_id=organization_hardware_settings.organization_id and m.user_id=(select auth.uid()) and m.is_active and m.role in ('owner','admin')));
drop policy if exists document_sequence_member_read on public.business_document_sequences;
create policy document_sequence_member_read on public.business_document_sequences for select to authenticated using(private.is_org_member(organization_id));
create or replace function public.next_business_document_number(p_organization_id uuid,p_document_type text,p_prefix text default null)
returns text language plpgsql security definer set search_path='' as $$
declare v_user uuid:=(select auth.uid()); v_month text:=to_char(now() at time zone 'Asia/Bangkok','YYYYMM'); v_prefix text; v_seq bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='Authentication required'; end if;
 if not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=v_user and m.is_active and m.membership_status='active' and m.role in ('owner','admin','accountant','hr')) then raise exception using errcode='42501',message='ไม่มีสิทธิ์ออกเอกสาร'; end if;
 if p_document_type not in ('invoice','receipt','quotation','delivery','goods_receipt','withholding','payment_voucher','cash_voucher','credit_note') then raise exception using errcode='22023',message='ประเภทเอกสารไม่ถูกต้อง'; end if;
 select coalesce(p_prefix,document_prefixes->>p_document_type,upper(left(p_document_type,3))) into v_prefix from public.organization_business_settings where organization_id=p_organization_id;
 v_prefix:=coalesce(v_prefix,upper(left(p_document_type,3)));
 insert into public.business_document_sequences(organization_id,document_month,document_type,last_number) values(p_organization_id,v_month,p_document_type,1)
 on conflict(organization_id,document_month,document_type) do update set last_number=public.business_document_sequences.last_number+1 returning last_number into v_seq;
 return v_prefix||'-'||v_month||'-'||lpad(v_seq::text,4,'0');
end; $$;
revoke all on function public.next_business_document_number(uuid,text,text) from public,anon;
grant execute on function public.next_business_document_number(uuid,text,text) to authenticated;
commit;