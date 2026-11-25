begin;
alter table public.products add column if not exists image_path text;
comment on column public.products.image_path is 'Private Supabase Storage object path for the product image in store-assets';
commit;
