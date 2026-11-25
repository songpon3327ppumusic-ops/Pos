-- SECURITY DEFINER routines use an empty search_path and schema-qualified objects.
alter function public.adjust_stock(uuid,uuid,numeric,text) set search_path='';
alter function public.approve_store_member(uuid,boolean) set search_path='';
alter function public.bootstrap_store_owner(text) set search_path='';
alter function public.checkout_sale_idempotent(uuid,jsonb,text,numeric,numeric,uuid,uuid,numeric) set search_path='';
alter function public.get_my_store_membership_state() set search_path='';
alter function public.get_store_invite_code() set search_path='';
alter function public.list_pending_store_members() set search_path='';
alter function public.create_storeflow_payroll(uuid,date,date,date) set search_path='';
alter function public.storeflow_clock_in(uuid,uuid) set search_path='';
alter function public.storeflow_clock_out(uuid) set search_path='';
