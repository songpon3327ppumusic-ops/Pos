create or replace function private.is_org_member(p_organization_id uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id=p_organization_id
      and m.user_id=(select auth.uid())
      and m.is_active=true
      and m.membership_status='active'
      and (m.role='owner' or private.storeflow_effective_plan(p_organization_id)<>'free')
  );
$function$;

create or replace function private.has_module_access(p_organization_id uuid,p_module text,p_action text)
returns boolean language plpgsql stable security definer set search_path=''
as $function$
declare v_role text; v_allowed boolean; v_plan text;
begin
  if auth.uid() is null then return false; end if;
  select m.role into v_role from public.organization_members m
  where m.organization_id=p_organization_id and m.user_id=(select auth.uid())
    and m.is_active=true and m.membership_status='active' limit 1;
  if v_role is null then return false; end if;
  v_plan:=private.storeflow_effective_plan(p_organization_id);
  if v_plan='expired' and p_action not in ('read','select') then return false; end if;
  if v_plan='free' and v_role<>'owner' then return false; end if;
  if v_plan<>'expired' and p_module in ('attendance','shifts')
     and v_plan not in ('standard','premium','lifetime') then return false; end if;
  if v_plan<>'expired' and p_module='payroll'
     and v_plan not in ('premium','lifetime') then return false; end if;
  if v_plan='free' and p_module in ('employees','staff','workforce')
     and p_action not in ('read','select') then return false; end if;
  if v_plan<>'expired' and p_module in ('documents','business_documents')
     and not private.storeflow_has_feature(p_organization_id,'business_documents') then return false; end if;
  if v_role in ('owner','admin') then return true; end if;
  if v_role='cashier' then
    return case when p_module='pos' then p_action in ('read','create')
      when p_module='orders' then p_action in ('read','create')
      when p_module='inventory' then p_action='read' else false end;
  end if;
  select rp.allowed into v_allowed from public.role_permissions rp
  where rp.organization_id=p_organization_id and rp.role=v_role
    and rp.module=p_module and rp.action=p_action limit 1;
  if v_allowed is not null then return v_allowed; end if;
  return case
    when v_role='manager' then p_action in ('read','create','update') and p_module not in ('payroll','permissions','audit')
    when v_role='hr' then p_module in ('employees','attendance','leave','payroll') and p_action in ('read','create','update')
    when v_role='accountant' then p_module in ('reports','expenses','payroll','orders') and p_action in ('read','create','update','approve')
    when v_role='employee' then p_module in ('dashboard','attendance','leave') and p_action in ('read','create')
    else false
  end;
end;
$function$;
