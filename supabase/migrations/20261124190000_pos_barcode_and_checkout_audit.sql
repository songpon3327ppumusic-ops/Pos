begin;
alter table public.products add column if not exists barcode text;
create unique index if not exists products_org_barcode_uidx
  on public.products(organization_id, barcode)
  where barcode is not null and length(trim(barcode)) > 0;
create unique index if not exists products_org_sku_uidx
  on public.products(organization_id, sku)
  where sku is not null and length(trim(sku)) > 0;
comment on column public.products.barcode is 'Barcode / EAN / UPC value used by POS search and scanner input';
commit;