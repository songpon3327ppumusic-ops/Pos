create or replace function private.has_module_access(p_organization_id uuid,p_module text,p_action text)
returns boolean language plpgsql stable security definer set search_path=''
as $$
declare v_role text; v_allowed boolean;
begin
 if auth.uid() is null then return false; end if;
 select m.role into v_role from public.organization_members m
 where m.organization_id=p_organization_id and m.user_id=(select auth.uid())
 and m.is_active=true and m.membership_status='active' limit 1;
 if v_role is null then return false; end if;
 if v_role in ('owner','admin') then return true; end if;
 -- Cashier is a hard-capped role; tenant-configurable permission rows cannot expand it.
 if v_role='cashier' then
  return case
   when p_module='pos' then p_action in ('read','create')
   when p_module='orders' then p_action in ('read','create')
   when p_module='inventory' then p_action='read'
   else false
  end;
 end if;
 select rp.allowed into v_allowed from public.role_permissions rp
 where rp.organization_id=p_organization_id and rp.role=v_role
 and rp.module=p_module and rp.action=p_action limit 1;
 if v_allowed is not null then return v_allowed; end if;
 return case v_role
  when 'manager' then p_action in ('read','create','update') and p_module not in ('payroll','permissions','audit')
  when 'hr' then p_module in ('employees','attendance','leave','payroll') and p_action in ('read','create','update')
  when 'accountant' then p_module in ('reports','expenses','payroll','orders') and p_action in ('read','create','update','approve')
  when 'employee' then p_module in ('dashboard','attendance','leave') and p_action in ('read','create')
  else false
 end;
end;
$$;