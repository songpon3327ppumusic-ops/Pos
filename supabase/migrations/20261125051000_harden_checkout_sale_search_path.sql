-- checkout_sale is a SECURITY DEFINER RPC and uses schema-qualified objects.
alter function public.checkout_sale(uuid,jsonb,text,numeric,numeric,uuid) set search_path='';
