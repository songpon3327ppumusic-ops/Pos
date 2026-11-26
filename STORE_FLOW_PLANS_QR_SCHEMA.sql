-- StoreFlow: four subscription tiers, merchant QR and platform billing QR.
-- Applied to Supabase project tjunaxajcxwxirneopar on 2026-11-26.
-- Prices are THB: Basic 199/mo, Standard 399/mo, Premium 799/mo,
-- Lifetime 2,590 one-time (regular 3,990).

ALTER TABLE public.organization_subscriptions
  ADD COLUMN IF NOT EXISTS plan_tier text;
UPDATE public.organization_subscriptions
SET plan_tier = CASE
  WHEN plan_type='lifetime' OR plan_id='lifetime' THEN 'lifetime'
  WHEN plan_id IN ('pro','standard') THEN 'standard'
  WHEN plan_id IN ('business','premium') THEN 'premium'
  ELSE 'basic' END
WHERE plan_tier IS NULL;
ALTER TABLE public.organization_subscriptions
  ALTER COLUMN plan_tier SET DEFAULT 'basic',
  ALTER COLUMN plan_tier SET NOT NULL;
ALTER TABLE public.organization_subscriptions
  DROP CONSTRAINT IF EXISTS organization_subscriptions_plan_tier_check,
  ADD CONSTRAINT organization_subscriptions_plan_tier_check
    CHECK (plan_tier IN ('basic','standard','premium','lifetime'));
ALTER TABLE public.organization_subscriptions
  DROP CONSTRAINT IF EXISTS organization_subscriptions_status_check,
  ADD CONSTRAINT organization_subscriptions_status_check
    CHECK (status IN ('trial','trialing','free','pending_payment','active','past_due','canceled','incomplete','unpaid','paused','expired'));
UPDATE public.organization_subscriptions SET status='trial' WHERE status IN ('trialing','free');
UPDATE public.organization_subscriptions
SET plan_id=CASE WHEN plan_id IN ('starter','free') THEN 'basic'
                 WHEN plan_id='pro' THEN 'standard'
                 WHEN plan_id='business' THEN 'premium' ELSE plan_id END,
    plan_tier=CASE WHEN plan_type='lifetime' OR plan_id='lifetime' THEN 'lifetime'
                   WHEN plan_id IN ('pro','standard') THEN 'standard'
                   WHEN plan_id IN ('business','premium') THEN 'premium' ELSE 'basic' END;

INSERT INTO public.subscription_plans
(id,name,description,monthly_price_thb,yearly_price_thb,limits,features,is_active,sort_order)
VALUES
('basic','Basic','แพ็กเกจเริ่มต้นสำหรับร้านค้าขนาดเล็ก',199,1990,
 '{"branches":1,"products":1000,"employees":5,"storage_mb":2048}'::jsonb,
 '{"pos":true,"inventory":true,"customers":true,"receipts":true,"reports_basic":true,"documents":false,"payroll":false,"advanced_reports":false}'::jsonb,true,1),
('standard','Standard','แพ็กเกจมาตรฐานสำหรับร้านค้าที่กำลังเติบโต',399,3990,
 '{"branches":3,"products":10000,"employees":20,"storage_mb":10240}'::jsonb,
 '{"pos":true,"inventory":true,"purchasing":true,"customers":true,"receipts":true,"documents":true,"reports_basic":true,"advanced_reports":true,"payroll":false}'::jsonb,true,2),
('premium','Premium','แพ็กเกจเต็มรูปแบบสำหรับธุรกิจที่ต้องการทุกเครื่องมือ',799,7990,
 '{"branches":10,"products":50000,"employees":100,"storage_mb":51200}'::jsonb,
 '{"pos":true,"inventory":true,"purchasing":true,"customers":true,"receipts":true,"documents":true,"tax_documents":true,"reports_basic":true,"advanced_reports":true,"payroll":true,"shifts":true,"priority_support":true}'::jsonb,true,3)
ON CONFLICT(id) DO UPDATE SET
 name=excluded.name,description=excluded.description,
 monthly_price_thb=excluded.monthly_price_thb,yearly_price_thb=excluded.yearly_price_thb,
 limits=excluded.limits,features=excluded.features,is_active=true,sort_order=excluded.sort_order,updated_at=now();

UPDATE public.subscription_plans
SET name='Lifetime',description='ซื้อขาด จ่ายครั้งเดียว ใช้งานได้ตลอดชีพ พร้อมสิทธิ์เทียบเท่า Premium',
 monthly_price_thb=2590,yearly_price_thb=2590,
 limits=(SELECT limits FROM public.subscription_plans WHERE id='premium'),
 features=(SELECT features || '{"lifetime_updates":true,"promo_price_thb":2590,"regular_price_thb":3990}'::jsonb FROM public.subscription_plans WHERE id='premium'),
 is_active=true,sort_order=4,updated_at=now()
WHERE id='lifetime';

ALTER TABLE public.store_payment_settings
  ADD COLUMN IF NOT EXISTS custom_qr_url text;
UPDATE public.store_payment_settings
SET custom_qr_url=qr_image_path
WHERE custom_qr_url IS NULL AND qr_image_path IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.storeflow_platform_settings (
 id boolean PRIMARY KEY DEFAULT true CHECK(id=true),
 custom_qr_url text, account_name text, account_number text, bank_name text,
 promptpay_name text, promptpay_id text,
 updated_at timestamptz NOT NULL DEFAULT now(),
 updated_by uuid REFERENCES auth.users(id)
);

ALTER TABLE public.storeflow_platform_settings
  ADD COLUMN IF NOT EXISTS is_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS instructions text;

UPDATE public.storeflow_platform_settings
SET instructions = coalesce(
  instructions,
  'โอนเงินตามยอดที่แสดง แล้วแนบสลิปพร้อมเลขอ้างอิงเพื่อรอผู้ดูแลตรวจสอบ'
)
WHERE id = true;

GRANT SELECT ON public.storeflow_platform_settings TO authenticated;
GRANT SELECT ON public.subscription_plans TO authenticated;

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
-- Existing subscription_plans_public_read policy already exposes active plans.

ALTER TABLE public.storeflow_platform_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS storeflow_platform_settings_authenticated_read ON public.storeflow_platform_settings;
CREATE POLICY storeflow_platform_settings_authenticated_read
 ON public.storeflow_platform_settings FOR SELECT TO authenticated USING(true);
DROP POLICY IF EXISTS storeflow_platform_settings_admin_write ON public.storeflow_platform_settings;
DROP POLICY IF EXISTS storeflow_platform_settings_admin_insert ON public.storeflow_platform_settings;
DROP POLICY IF EXISTS storeflow_platform_settings_admin_update ON public.storeflow_platform_settings;
DROP POLICY IF EXISTS storeflow_platform_settings_admin_delete ON public.storeflow_platform_settings;
CREATE POLICY storeflow_platform_settings_admin_insert
 ON public.storeflow_platform_settings FOR INSERT TO authenticated
 WITH CHECK(coalesce((select auth.jwt())->'app_metadata'->>'role','')='platform_admin');
CREATE POLICY storeflow_platform_settings_admin_update
 ON public.storeflow_platform_settings FOR UPDATE TO authenticated
 USING(coalesce((select auth.jwt())->'app_metadata'->>'role','')='platform_admin')
 WITH CHECK(coalesce((select auth.jwt())->'app_metadata'->>'role','')='platform_admin');
CREATE POLICY storeflow_platform_settings_admin_delete
 ON public.storeflow_platform_settings FOR DELETE TO authenticated
 USING(coalesce((select auth.jwt())->'app_metadata'->>'role','')='platform_admin');

CREATE INDEX IF NOT EXISTS storeflow_platform_settings_updated_by_idx
 ON public.storeflow_platform_settings(updated_by);

CREATE TABLE IF NOT EXISTS public.storeflow_plan_payment_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 requested_by uuid NOT NULL REFERENCES auth.users(id),
 plan_tier text NOT NULL CHECK(plan_tier IN ('basic','standard','premium','lifetime')),
 billing_interval text NOT NULL DEFAULT 'month' CHECK(billing_interval IN ('month','year','lifetime')),
 amount_thb numeric(12,2) NOT NULL CHECK(amount_thb>0),
 status text NOT NULL DEFAULT 'pending_payment' CHECK(status IN ('pending_payment','pending_review','approved','rejected','cancelled')),
 slip_path text, transaction_ref text, customer_note text, admin_note text,
 previous_plan_tier text, previous_subscription_status text,
 reviewed_by uuid REFERENCES auth.users(id), reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.storeflow_plan_payment_requests
 ADD COLUMN IF NOT EXISTS previous_plan_tier text,
 ADD COLUMN IF NOT EXISTS previous_subscription_status text;
CREATE INDEX IF NOT EXISTS storeflow_plan_payment_requests_org_created_idx
 ON public.storeflow_plan_payment_requests(organization_id,created_at DESC);
CREATE INDEX IF NOT EXISTS storeflow_plan_payment_requests_requested_by_idx
 ON public.storeflow_plan_payment_requests(requested_by);
CREATE INDEX IF NOT EXISTS storeflow_plan_payment_requests_reviewed_by_idx
 ON public.storeflow_plan_payment_requests(reviewed_by);
CREATE UNIQUE INDEX IF NOT EXISTS storeflow_plan_payment_requests_transaction_ref_uidx
 ON public.storeflow_plan_payment_requests(transaction_ref)
 WHERE transaction_ref IS NOT NULL AND btrim(transaction_ref)<>'';
ALTER TABLE public.storeflow_plan_payment_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS storeflow_plan_payment_requests_member_read ON public.storeflow_plan_payment_requests;
DROP POLICY IF EXISTS storeflow_plan_payment_requests_owner_insert ON public.storeflow_plan_payment_requests;
DROP POLICY IF EXISTS storeflow_plan_payment_requests_platform_admin_read ON public.storeflow_plan_payment_requests;
CREATE POLICY storeflow_plan_payment_requests_member_read ON public.storeflow_plan_payment_requests
 FOR SELECT TO authenticated USING(
  EXISTS(SELECT 1 FROM public.organization_members m
   WHERE m.organization_id=storeflow_plan_payment_requests.organization_id
    AND m.user_id=(select auth.uid()) AND m.is_active AND m.membership_status='active')
  OR coalesce((select auth.jwt())->'app_metadata'->>'role','')='platform_admin');
CREATE POLICY storeflow_plan_payment_requests_owner_insert ON public.storeflow_plan_payment_requests
 FOR INSERT TO authenticated WITH CHECK(
  requested_by=(select auth.uid()) AND status='pending_payment' AND EXISTS(
   SELECT 1 FROM public.organization_members m
   WHERE m.organization_id=storeflow_plan_payment_requests.organization_id
    AND m.user_id=(select auth.uid()) AND m.is_active AND m.membership_status='active'
    AND m.role IN ('owner','admin')));
CREATE OR REPLACE FUNCTION public.storeflow_is_platform_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $ SELECT coalesce(auth.jwt()->'app_metadata'->>'role','')='platform_admin'; $;
REVOKE ALL ON FUNCTION public.storeflow_is_platform_admin() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storeflow_is_platform_admin() TO authenticated;




CREATE OR REPLACE FUNCTION private.has_active_store_license(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT EXISTS(SELECT 1 FROM public.organization_subscriptions s WHERE s.organization_id=p_org AND (
  (s.plan_type='lifetime' AND s.status='active')
  OR (s.status='active' AND (s.current_period_end IS NULL OR s.current_period_end>now()))
  OR (s.status IN ('trial','trialing') AND s.trial_ends_at>now())
 ));
$$;

CREATE OR REPLACE FUNCTION public.storeflow_create_store(p_store_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_user uuid:=auth.uid(); v_org uuid:=gen_random_uuid();
 v_name text:=trim(coalesce(p_store_name,'')); v_slug text:='store-'||replace(v_org::text,'-','');
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION USING errcode='28000',message='Authentication required'; END IF;
 IF char_length(v_name)<2 OR char_length(v_name)>100 THEN
  RAISE EXCEPTION USING errcode='22023',message='ชื่อร้านค้าต้องมี 2-100 ตัวอักษร'; END IF;
 INSERT INTO public.organizations(id,name,slug,plan_type) VALUES(v_org,v_name,v_slug,'subscription');
 INSERT INTO public.organization_members(organization_id,user_id,role,is_active,membership_status)
 VALUES(v_org,v_user,'owner',true,'active');
 INSERT INTO public.organization_subscriptions(
  organization_id,plan_id,plan_tier,billing_interval,status,trial_started_at,trial_ends_at,
  current_period_start,current_period_end,plan_type,metadata
 ) VALUES(v_org,'basic','basic','month','trial',now(),now()+interval '7 days',
           now(),now()+interval '7 days','subscription',jsonb_build_object('source','android_owner_signup'));
 INSERT INTO public.store_payment_settings(organization_id,cash_enabled)
 VALUES(v_org,true) ON CONFLICT(organization_id) DO NOTHING;
 RETURN v_org;
END; $$;
REVOKE ALL ON FUNCTION public.storeflow_create_store(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storeflow_create_store(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.storeflow_submit_plan_payment(
 p_organization_id uuid,p_plan_tier text,p_billing_interval text,p_amount_thb numeric,
 p_slip_path text,p_transaction_ref text,p_customer_note text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_user uuid:=auth.uid(); v_id uuid; v_previous_tier text; v_previous_status text; v_expected numeric;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF p_plan_tier NOT IN ('basic','standard','premium','lifetime') THEN RAISE EXCEPTION 'Invalid plan tier'; END IF;
 IF p_billing_interval NOT IN ('month','year','lifetime') THEN RAISE EXCEPTION 'Invalid billing interval'; END IF;
 IF (p_plan_tier='lifetime')<>(p_billing_interval='lifetime') THEN RAISE EXCEPTION 'Billing interval does not match plan'; END IF;
 IF p_slip_path IS NULL OR p_slip_path NOT LIKE v_user::text||'/%' THEN RAISE EXCEPTION 'Slip upload is required'; END IF;
 IF p_transaction_ref IS NULL OR length(btrim(p_transaction_ref))<6 THEN RAISE EXCEPTION 'Slip transaction reference is required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organization_members m WHERE m.organization_id=p_organization_id
  AND m.user_id=v_user AND m.is_active AND m.membership_status='active' AND m.role IN ('owner','admin'))
 THEN RAISE EXCEPTION 'Only store owners or admins can request a plan'; END IF;
 SELECT CASE WHEN p_billing_interval='year' THEN yearly_price_thb ELSE monthly_price_thb END
 INTO v_expected FROM public.subscription_plans WHERE id=p_plan_tier AND is_active;
 IF v_expected IS NULL OR round(v_expected,2)<>round(p_amount_thb,2) THEN
  RAISE EXCEPTION 'Plan amount does not match the current price'; END IF;
 IF EXISTS(SELECT 1 FROM public.storeflow_plan_payment_requests WHERE transaction_ref=btrim(p_transaction_ref))
 THEN RAISE EXCEPTION 'This transfer reference has already been submitted'; END IF;
 SELECT plan_tier,status INTO v_previous_tier,v_previous_status
 FROM public.organization_subscriptions WHERE organization_id=p_organization_id FOR UPDATE;
 INSERT INTO public.storeflow_plan_payment_requests(
  organization_id,requested_by,plan_tier,billing_interval,amount_thb,status,slip_path,transaction_ref,
  customer_note,previous_plan_tier,previous_subscription_status
 ) VALUES(p_organization_id,v_user,p_plan_tier,p_billing_interval,p_amount_thb,'pending_review',
          p_slip_path,btrim(p_transaction_ref),p_customer_note,v_previous_tier,v_previous_status)
 RETURNING id INTO v_id;
 UPDATE public.organization_subscriptions SET status='pending_payment',updated_at=now()
 WHERE organization_id=p_organization_id;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.storeflow_submit_plan_payment(uuid,text,text,numeric,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storeflow_submit_plan_payment(uuid,text,text,numeric,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.storeflow_review_plan_payment(
 p_request_id uuid,p_approve boolean,p_admin_note text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_request public.storeflow_plan_payment_requests%rowtype;
BEGIN
 IF coalesce(auth.jwt()->'app_metadata'->>'role','')<>'platform_admin' THEN
  RAISE EXCEPTION 'Only StoreFlow platform admins can review plan payments'; END IF;
 SELECT * INTO v_request FROM public.storeflow_plan_payment_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND OR v_request.status NOT IN ('pending_review','pending_payment') THEN
  RAISE EXCEPTION 'Payment request not found or already reviewed'; END IF;
 UPDATE public.storeflow_plan_payment_requests SET
  status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,admin_note=p_admin_note,
  reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() WHERE id=p_request_id;
 IF p_approve THEN
  INSERT INTO public.organization_subscriptions(
   organization_id,plan_id,plan_tier,plan_type,billing_interval,status,current_period_start,current_period_end,
   trial_started_at,trial_ends_at
  ) VALUES(v_request.organization_id,v_request.plan_tier,v_request.plan_tier,
   CASE WHEN v_request.plan_tier='lifetime' THEN 'lifetime' ELSE 'subscription' END,
   v_request.billing_interval,'active',now(),
   CASE WHEN v_request.billing_interval='lifetime' THEN NULL WHEN v_request.billing_interval='year'
        THEN now()+interval '1 year' ELSE now()+interval '1 month' END,NULL,NULL)
  ON CONFLICT(organization_id) DO UPDATE SET plan_id=excluded.plan_id,plan_tier=excluded.plan_tier,
   plan_type=excluded.plan_type,billing_interval=excluded.billing_interval,status='active',
   current_period_start=excluded.current_period_start,current_period_end=excluded.current_period_end,
   trial_started_at=NULL,trial_ends_at=NULL,updated_at=now();
  UPDATE public.organizations SET plan_type=CASE WHEN v_request.plan_tier='lifetime' THEN 'lifetime'
    ELSE 'subscription' END WHERE id=v_request.organization_id;
 ELSE
  UPDATE public.organization_subscriptions SET status=coalesce(v_request.previous_subscription_status,'expired'),
   plan_tier=coalesce(v_request.previous_plan_tier,plan_tier),updated_at=now()
  WHERE organization_id=v_request.organization_id AND status='pending_payment';
 END IF;
END; $$;
REVOKE ALL ON FUNCTION public.storeflow_review_plan_payment(uuid,boolean,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.storeflow_review_plan_payment(uuid,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.storeflow_get_subscription(p_organization_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $
DECLARE v_row public.organization_subscriptions%rowtype;
BEGIN
 IF auth.uid() IS NULL OR NOT private.is_org_member(p_organization_id) THEN
  RAISE EXCEPTION USING errcode='42501',message='Not an active store member'; END IF;
 UPDATE public.organization_subscriptions SET status='expired',updated_at=now()
 WHERE organization_id=p_organization_id AND (
  (status IN ('trial','trialing') AND trial_ends_at IS NOT NULL AND trial_ends_at<=now())
  OR (status='active' AND plan_type<>'lifetime' AND current_period_end IS NOT NULL AND current_period_end<=now())
 );
 SELECT * INTO v_row FROM public.organization_subscriptions WHERE organization_id=p_organization_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('status',v_row.status,'plan_id',v_row.plan_id,'plan_tier',v_row.plan_tier,
  'plan_type',v_row.plan_type,'trial_ends_at',v_row.trial_ends_at,'current_period_end',v_row.current_period_end);
END; $;
REVOKE ALL ON FUNCTION public.storeflow_get_subscription(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storeflow_get_subscription(uuid) TO authenticated;

INSERT INTO public.storeflow_platform_settings(id) VALUES(true) ON CONFLICT(id) DO NOTHING;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('storeflow-platform-billing','storeflow-platform-billing',false,6291456,ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=6291456,allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp'];

DROP POLICY IF EXISTS storeflow_platform_billing_read ON storage.objects;
CREATE POLICY storeflow_platform_billing_read ON storage.objects FOR SELECT TO authenticated
USING(bucket_id='storeflow-platform-billing' AND (
 (storage.foldername(name))[1]=auth.uid()::text OR (storage.foldername(name))[1]='platform'
 OR coalesce(auth.jwt()->'app_metadata'->>'role','')='platform_admin'));
DROP POLICY IF EXISTS storeflow_platform_billing_upload ON storage.objects;
CREATE POLICY storeflow_platform_billing_upload ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='storeflow-platform-billing' AND (
 (storage.foldername(name))[1]=auth.uid()::text
 OR ((storage.foldername(name))[1]='platform' AND coalesce(auth.jwt()->'app_metadata'->>'role','')='platform_admin')));
DROP POLICY IF EXISTS storeflow_platform_billing_update ON storage.objects;
CREATE POLICY storeflow_platform_billing_update ON storage.objects FOR UPDATE TO authenticated
USING(bucket_id='storeflow-platform-billing' AND coalesce(auth.jwt()->'app_metadata'->>'role','')='platform_admin')
WITH CHECK(bucket_id='storeflow-platform-billing' AND coalesce(auth.jwt()->'app_metadata'->>'role','')='platform_admin');
