alter table public.subscription_plans
  add column if not exists stripe_lifetime_price_id text;

insert into public.subscription_plans
(id,name,description,monthly_price_thb,yearly_price_thb,stripe_product_id,stripe_lifetime_price_id,limits,features,is_active,sort_order)
values
('lifetime','Lifetime','ซื้อขาดต่อร้านค้า ใช้งานทุกฟีเจอร์และได้รับการอัปเดตตลอดอายุการใช้งาน',4990,4990,'prod_VggInrA8dXo7xG','price_1UfIvsEVxL6GMujUWOkp7zTp',
'{"employees":-1,"products":-1,"branches":-1,"storage_mb":-1}'::jsonb,
'{"pos":true,"inventory":true,"customers":true,"reports_basic":true,"payroll":true,"advanced_reports":true,"priority_support":true,"api_access":true,"documents":true,"tax_documents":true,"purchasing":true,"delivery":true,"multi_branch":true,"lifetime_updates":true}'::jsonb,
true,5)
on conflict (id) do update set
 name=excluded.name,description=excluded.description,monthly_price_thb=excluded.monthly_price_thb,
 yearly_price_thb=excluded.yearly_price_thb,stripe_product_id=excluded.stripe_product_id,
 stripe_lifetime_price_id=excluded.stripe_lifetime_price_id,limits=excluded.limits,features=excluded.features,
 is_active=true,sort_order=excluded.sort_order,updated_at=now();

comment on column public.subscription_plans.stripe_lifetime_price_id is 'Stripe one-time price ID for lifetime licenses';
