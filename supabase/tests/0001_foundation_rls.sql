-- Ejecutar con `supabase test db` despues de aplicar 0001_foundation.sql.
begin;

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('20000000-0000-0000-0000-000000000002', 'owner-b@example.test'),
  ('30000000-0000-0000-0000-000000000003', 'manager-a@example.test');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select public.create_organization_with_owner('Tenant A', 'tenant-a', 'PL', 'PLN', 'Europe/Warsaw', 'es');
select set_config('request.jwt.claims', '{"sub":"20000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select public.create_organization_with_owner('Tenant B', 'tenant-b', 'CO', 'COP', 'America/Bogota', 'es');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

insert into public.locations (organization_id, code, name, address_line_1, city, country_code, currency, timezone)
select id, 'A-01', 'Local A', 'Test 1', 'Warsaw', 'PL', 'PLN', 'Europe/Warsaw'
from public.organizations where slug = 'tenant-a';

insert into public.employees (organization_id, employee_code, first_name, last_name, hire_date, status, created_by)
select id, 'A-0001', 'Ada', 'Test', current_date, 'active', auth.uid()
from public.organizations where slug = 'tenant-a';

insert into public.employee_compensation_rates (
  organization_id, employee_id, compensation_type, currency, amount,
  effective_from, created_by
)
select e.organization_id, e.id, 'hourly', 'PLN', 30, current_date, auth.uid()
from public.employees e where e.employee_code = 'A-0001';

insert into public.organization_memberships (
  organization_id, user_id, status, all_locations, activated_at, created_by, updated_by
)
select id, '30000000-0000-0000-0000-000000000003', 'active', true, now(), auth.uid(), auth.uid()
from public.organizations where slug = 'tenant-a';

insert into public.membership_roles (organization_id, membership_id, role_id, granted_by)
select m.organization_id, m.id, r.id, auth.uid()
from public.organization_memberships m
join public.roles r on r.organization_id = m.organization_id and r.code = 'manager'
where m.user_id = '30000000-0000-0000-0000-000000000003';

set local role authenticated;

-- El owner A no puede ver Tenant B.
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.organizations) <> 1 then
    raise exception 'RLS failure: cross-tenant organization visible';
  end if;
end;
$$;

-- El manager ve el empleado en alcance pero no su salario.
select set_config('request.jwt.claims', '{"sub":"30000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.employees where employee_code = 'A-0001') <> 1 then
    raise exception 'RLS failure: scoped employee not visible';
  end if;
  if (select count(*) from public.employee_compensation_rates) <> 0 then
    raise exception 'RLS failure: manager can see salary without permission';
  end if;
end;
$$;

-- Ni manager ni employee pueden mutar auditoria o tarifas historicas.
do $$
begin
  begin
    update public.employee_compensation_rates set amount = amount + 1;
    raise exception 'RLS failure: historical compensation update succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    delete from public.audit_log;
    raise exception 'RLS failure: audit delete succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

reset role;
rollback;
