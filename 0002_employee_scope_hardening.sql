-- Control Horarios
-- Migration 0002
-- Hardening de alcance y autorizacion de empleados.
--
-- Objetivos:
-- 1. Ningun usuario conserva acceso laboral despues de perder
--    su membresia activa en la organizacion.
-- 2. El acceso propio del empleado sigue existiendo solamente
--    mientras exista una membresia activa y vigente.
-- 3. Managers/admins solo operan sobre empleados dentro de su alcance.
-- 4. La ubicacion primaria de un empleado no puede apuntar a un local
--    fuera del alcance del actor que lo crea o modifica.
--
-- No modifica historia laboral ni datos existentes.

begin;

-- ---------------------------------------------------------------------------
-- 1. Endurecer el calculo central de alcance de empleado
-- ---------------------------------------------------------------------------

create or replace function public.employee_is_in_scope(
  p_organization_id uuid,
  p_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.employees e
    join public.organization_memberships m
      on m.organization_id = e.organization_id
     and m.user_id = auth.uid()
     and m.status = 'active'
     and m.valid_from <= clock_timestamp()
     and (
       m.valid_until is null
       or m.valid_until > clock_timestamp()
     )
    where e.organization_id = p_organization_id
      and e.id = p_employee_id
      and (
        -- El empleado puede acceder a su propia ficha,
        -- pero solamente con membresia activa y vigente.
        e.user_id = auth.uid()

        -- Miembros con acceso global a locales.
        or m.all_locations

        -- Miembros limitados a locales:
        -- el empleado debe tener una asignacion laboral vigente
        -- en uno de los locales autorizados.
        or exists (
          select 1
          from public.employee_location_assignments ela
          join public.membership_location_access mla
            on mla.organization_id = ela.organization_id
           and mla.membership_id = m.id
           and mla.location_id = ela.location_id
          where ela.organization_id = e.organization_id
            and ela.employee_id = e.id
            and ela.active
            and current_date >= ela.valid_from
            and (
              ela.valid_to is null
              or current_date <= ela.valid_to
            )
            and mla.valid_from <= clock_timestamp()
            and (
              mla.valid_until is null
              or mla.valid_until > clock_timestamp()
            )
        )
      )
  );
$$;

-- Nunca permitir ejecucion publica/anonima accidental.
revoke all
on function public.employee_is_in_scope(uuid, uuid)
from public;

grant execute
on function public.employee_is_in_scope(uuid, uuid)
to authenticated;

comment on function public.employee_is_in_scope(uuid, uuid) is
'Returns true only when the authenticated user has an active organization membership and the employee is self or inside the caller location scope.';


-- ---------------------------------------------------------------------------
-- 2. SELECT de empleados
-- ---------------------------------------------------------------------------
-- La politica anterior permitia:
--
--   user_id = auth.uid()
--
-- sin comprobar que la membresia siguiera activa.
--
-- Desde ahora incluso el acceso propio pasa por employee_is_in_scope().

drop policy if exists employees_select
on public.employees;

create policy employees_select
on public.employees
for select
to authenticated
using (
  public.employee_is_in_scope(organization_id, id)
  and (
    user_id = auth.uid()
    or public.has_permission(
      organization_id,
      'employees.view'
    )
  )
);


-- ---------------------------------------------------------------------------
-- 3. INSERT de empleados
-- ---------------------------------------------------------------------------
-- Un actor con employees.create no debe poder crear un empleado cuya
-- primary_location_id apunte a un local fuera de su alcance.

drop policy if exists employees_insert
on public.employees;

create policy employees_insert
on public.employees
for insert
to authenticated
with check (
  public.has_permission(
    organization_id,
    'employees.create'
  )
  and (
    primary_location_id is null
    or public.can_access_location(
      organization_id,
      primary_location_id
    )
  )
);


-- ---------------------------------------------------------------------------
-- 4. UPDATE de empleados
-- ---------------------------------------------------------------------------
-- La fila existente debe estar dentro del alcance del actor.
-- La ubicacion primaria resultante tambien debe pertenecer a su alcance.

drop policy if exists employees_update
on public.employees;

create policy employees_update
on public.employees
for update
to authenticated
using (
  public.has_permission(
    organization_id,
    'employees.edit'
  )
  and public.employee_is_in_scope(
    organization_id,
    id
  )
)
with check (
  public.has_permission(
    organization_id,
    'employees.edit'
  )
  and (
    primary_location_id is null
    or public.can_access_location(
      organization_id,
      primary_location_id
    )
  )
);


-- ---------------------------------------------------------------------------
-- 5. Proteccion defensiva de permisos
-- ---------------------------------------------------------------------------

revoke all
on function public.employee_is_in_scope(uuid, uuid)
from anon;

commit;
