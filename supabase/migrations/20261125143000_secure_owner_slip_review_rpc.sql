-- Expose only the authenticated owner-review wrapper. Keep the privileged
-- implementation non-executable by client roles even if private becomes exposed.
begin;
revoke all on function private.owner_review_pos_slip_impl(uuid,uuid,boolean,text,text) from public,anon,authenticated;
create or replace function public.owner_review_pos_slip(
 p_organization_id uuid,p_sale_id uuid,p_approve boolean,p_transaction_ref text,p_note text default null
) returns void
language plpgsql security definer set search_path to ''
as $function$
begin
 if (select auth.uid()) is null then
  raise exception using errcode='28000',message='Authentication required';
 end if;
 perform private.owner_review_pos_slip_impl(p_organization_id,p_sale_id,p_approve,p_transaction_ref,p_note);
end;
$function$;
revoke all on function public.owner_review_pos_slip(uuid,uuid,boolean,text,text) from public,anon;
grant execute on function public.owner_review_pos_slip(uuid,uuid,boolean,text,text) to authenticated;
commit;