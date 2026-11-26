-- StoreFlow Basic / Standard / Premium / Lifetime catalog and quota matrix.
insert into public.subscription_plans
(id,name,description,monthly_price_thb,yearly_price_thb,limits,features,is_active,sort_order)
values
('basic','Basic','สำหรับร้านค้าขนาดเล็ก',199,1990,
 '{"employees":1,"products":50,"branches":1,"storage_mb":250}'::jsonb,
 '{"pos":true,"inventory":true,"reports_basic":true,"staff":true,"shifts":false,"attendance":false,"store_payment_qr":false,"payroll":false,"tax_documents":false,"barcode_scanner":false,"receipt_printer":false}'::jsonb,true,1),
('standard','Standard','สำหรับร้านค้าที่ต้องการจัดการทีมงานและรับชำระเงิน QR',399,3990,
 '{"employees":5,"products":-1,"branches":1,"storage_mb":2048}'::jsonb,
 '{"pos":true,"inventory":true,"reports_basic":true,"staff":true,"shifts":true,"attendance":true,"store_payment_qr":true,"payroll":false,"tax_documents":false,"barcode_scanner":false,"receipt_printer":false}'::jsonb,true,2),
('premium','Premium','ปลดล็อกทุกฟีเจอร์สำหรับธุรกิจเต็มรูปแบบ',799,7990,
 '{"employees":-1,"products":-1,"branches":-1,"storage_mb":-1}'::jsonb,
 '{"pos":true,"inventory":true,"reports_basic":true,"staff":true,"shifts":true,"attendance":true,"store_payment_qr":true,"payroll":true,"tax_documents":true,"barcode_scanner":true,"receipt_printer":true}'::jsonb,true,3)
on conflict(id) do update set name=excluded.name,description=excluded.description,
 monthly_price_thb=excluded.monthly_price_thb,yearly_price_thb=excluded.yearly_price_thb,
 limits=excluded.limits,features=excluded.features,is_active=true,sort_order=excluded.sort_order,updated_at=now();
update public.subscription_plans
set monthly_price_thb=2590,yearly_price_thb=2590,
 description='ซื้อขาดครั้งเดียว ฿2,590 • ปลดล็อกทุกฟีเจอร์ตลอดชีพ',
 limits='{"employees":-1,"products":-1,"branches":-1,"storage_mb":-1}'::jsonb,
 features='{"pos":true,"inventory":true,"reports_basic":true,"staff":true,"shifts":true,"attendance":true,"store_payment_qr":true,"payroll":true,"tax_documents":true,"barcode_scanner":true,"receipt_printer":true,"lifetime_updates":true}'::jsonb,
 is_active=true,sort_order=4,updated_at=now()
where id='lifetime';