-- Control Horarios — Fase 1 Fundacion
-- Esta migracion es append-only una vez aplicada en cualquier entorno compartido.

begin;

create extension if not exists pgcrypto;
create extension if not exists citext;
create extension if not exists btree_gist;

create type public.supported_language as enum ('es', 'pl', 'en');
create type public.organization_status as enum ('active', 'suspended', 'archived');
create type public.membership_status as enum ('invited', 'active', 'suspended', 'revoked');
create type public.employee_status as enum ('pending', 'active', 'suspended', 'terminated', 'archived');
create type public.contract_status as enum ('draft', 'active', 'ended', 'cancelled');
create type public.compensation_type as enum ('hourly', 'monthly');
create type public.policy_scope as enum ('organization', 'location');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug citext not null unique,
  name text not null check (length(btrim(name)) between 2 and 160),
  legal_name text,
  country_code varchar(2) not null check (country_code ~ '^[A-Z]{2}$'),
  default_currency varchar(3) not null check (default_currency ~ '^[A-Z]{3}$'),
  default_timezone text not null,
  default_language public.supported_language not null default 'es',
  status public.organization_status not null default 'active',
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint organizations_archive_consistency check (
    (status = 'archived' and archived_at is not null) or
    (status <> 'archived' and archived_at is null)
  ),
  unique (id, slug)
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code citext not null,
  name text not null check (length(btrim(name)) between 2 and 160),
  address_line_1 text not null,
  address_line_2 text,
  city text not null,
  region text,
  postal_code text,
  country_code varchar(2) not null check (country_code ~ '^[A-Z]{2}$'),
  currency varchar(3) not null check (currency ~ '^[A-Z]{3}$'),
  timezone text not null,
  settings jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object'),
  active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (organization_id, code),
  unique (organization_id, id),
  constraint locations_archive_consistency check (active or archived_at is not null)
);

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  preferred_language public.supported_language not null default 'es',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code citext not null unique check (code ~ '^[a-z]+([._][a-z]+)*$'),
  description_key text not null unique check (description_key ~ '^permissions\.'),
  sensitive boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code citext not null check (code ~ '^[a-z][a-z0-9_]*$'),
  name_key text not null check (name_key ~ '^roles\.'),
  is_base boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (organization_id, code),
  unique (organization_id, id)
);

create table public.role_permissions (
  organization_id uuid not null,
  role_id uuid not null,
  permission_id uuid not null references public.permissions(id),
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id),
  primary key (role_id, permission_id),
  foreign key (organization_id, role_id)
    references public.roles(organization_id, id) on delete cascade
);

create table public.organization_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null references auth.users(id),
  status public.membership_status not null default 'invited',
  all_locations boolean not null default false,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  invited_at timestamptz not null default now(),
  activated_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (organization_id, user_id),
  unique (organization_id, id),
  constraint memberships_valid_range check (valid_until is null or valid_until > valid_from),
  constraint memberships_revoked_consistency check (status <> 'revoked' or revoked_at is not null)
);

create table public.membership_roles (
  organization_id uuid not null,
  membership_id uuid not null,
  role_id uuid not null,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id),
  primary key (membership_id, role_id, valid_from),
  foreign key (organization_id, membership_id)
    references public.organization_memberships(organization_id, id) on delete cascade,
  foreign key (organization_id, role_id)
    references public.roles(organization_id, id) on delete cascade,
  constraint membership_roles_valid_range check (valid_until is null or valid_until > valid_from)
);

create table public.membership_location_access (
  organization_id uuid not null,
  membership_id uuid not null,
  location_id uuid not null,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id),
  primary key (membership_id, location_id, valid_from),
  foreign key (organization_id, membership_id)
    references public.organization_memberships(organization_id, id) on delete cascade,
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete cascade,
  constraint membership_locations_valid_range check (valid_until is null or valid_until > valid_from)
);

create table public.positions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code citext not null,
  name text not null,
  active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code),
  unique (organization_id, id)
);

create table public.cost_centers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code citext not null,
  name text not null,
  active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code),
  unique (organization_id, id)
);

create table public.work_areas (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  location_id uuid,
  code citext not null,
  name text not null,
  active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code),
  unique (organization_id, id),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id)
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  employee_code citext not null,
  user_id uuid references auth.users(id),
  first_name text not null check (length(btrim(first_name)) > 0),
  last_name text not null check (length(btrim(last_name)) > 0),
  display_name text,
  profile_photo_path text,
  phone text,
  email citext,
  country_code varchar(2) check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  preferred_language public.supported_language not null default 'es',
  birth_date date,
  address_line_1 text,
  address_line_2 text,
  city text,
  region text,
  postal_code text,
  identification_type text,
  identification_number text,
  hire_date date not null,
  termination_date date,
  status public.employee_status not null default 'pending',
  primary_location_id uuid,
  notes text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (organization_id, employee_code),
  unique (organization_id, id),
  unique (organization_id, user_id),
  foreign key (organization_id, primary_location_id)
    references public.locations(organization_id, id),
  constraint employees_dates check (termination_date is null or termination_date >= hire_date),
  constraint employees_termination_consistency check (
    (status in ('terminated', 'archived') and termination_date is not null) or
    status not in ('terminated', 'archived')
  ),
  constraint employees_archive_consistency check (status <> 'archived' or archived_at is not null)
);

create unique index employees_identification_unique
  on public.employees (organization_id, identification_type, identification_number)
  where identification_type is not null and identification_number is not null and status <> 'archived';

create table public.employee_location_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  employee_id uuid not null,
  location_id uuid not null,
  position_id uuid,
  work_area_id uuid,
  cost_center_id uuid,
  valid_from date not null,
  valid_to date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  foreign key (organization_id, employee_id)
    references public.employees(organization_id, id),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id),
  foreign key (organization_id, position_id)
    references public.positions(organization_id, id),
  foreign key (organization_id, work_area_id)
    references public.work_areas(organization_id, id),
  foreign key (organization_id, cost_center_id)
    references public.cost_centers(organization_id, id),
  constraint employee_assignments_dates check (valid_to is null or valid_to >= valid_from),
  constraint employee_assignments_active_consistency check (active or valid_to is not null),
  exclude using gist (
    employee_id with =,
    location_id with =,
    daterange(valid_from, coalesce(valid_to + 1, 'infinity'::date), '[)') with &&
  ) where (active)
);

create table public.contract_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code citext not null,
  name_key text,
  custom_name text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code),
  unique (organization_id, id),
  constraint contract_type_name check (name_key is not null or custom_name is not null)
);

create table public.employee_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  employee_id uuid not null,
  contract_type_id uuid not null,
  start_date date not null,
  end_date date,
  expected_weekly_minutes integer check (expected_weekly_minutes is null or expected_weekly_minutes between 0 and 10080),
  expected_monthly_minutes integer check (expected_monthly_minutes is null or expected_monthly_minutes between 0 and 44640),
  status public.contract_status not null default 'draft',
  notes text,
  supersedes_contract_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  foreign key (organization_id, employee_id)
    references public.employees(organization_id, id),
  foreign key (organization_id, contract_type_id)
    references public.contract_types(organization_id, id),
  unique (organization_id, employee_id, id),
  foreign key (organization_id, employee_id, supersedes_contract_id)
    references public.employee_contracts(organization_id, employee_id, id),
  constraint employee_contract_dates check (end_date is null or end_date >= start_date),
  constraint employee_contract_not_self check (supersedes_contract_id is null or supersedes_contract_id <> id)
);

create table public.employee_compensation_rates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  employee_id uuid not null,
  compensation_type public.compensation_type not null,
  currency varchar(3) not null check (currency ~ '^[A-Z]{3}$'),
  amount numeric(14, 4) not null check (amount > 0),
  effective_from date not null,
  effective_to date,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  foreign key (organization_id, employee_id)
    references public.employees(organization_id, id),
  constraint compensation_dates check (effective_to is null or effective_to >= effective_from),
  exclude using gist (
    employee_id with =,
    compensation_type with =,
    daterange(effective_from, coalesce(effective_to + 1, 'infinity'::date), '[)') with &&
  )
);

create table public.organization_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  location_id uuid,
  scope public.policy_scope not null,
  policy_key citext not null,
  policy_value jsonb not null,
  version integer not null default 1 check (version > 0),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id),
  constraint policies_scope_location check (
    (scope = 'organization' and location_id is null) or
    (scope = 'location' and location_id is not null)
  ),
  constraint policies_dates check (effective_to is null or effective_to > effective_from),
  unique nulls not distinct (organization_id, location_id, policy_key, version)
);

create table public.feature_flags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  location_id uuid,
  flag_key citext not null,
  enabled boolean not null default false,
  configuration jsonb not null default '{}'::jsonb check (jsonb_typeof(configuration) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id),
  unique nulls not distinct (organization_id, location_id, flag_key)
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  actor_user_id uuid references auth.users(id),
  actor_roles text[] not null default '{}',
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_value jsonb,
  new_value jsonb,
  reason text,
  request_id uuid,
  device_id uuid,
  created_at timestamptz not null default clock_timestamp()
);

create index idx_locations_organization_active on public.locations (organization_id, active);
create index idx_memberships_user_status on public.organization_memberships (user_id, status);
create index idx_membership_roles_active on public.membership_roles (membership_id, valid_from, valid_until);
create index idx_location_access_active on public.membership_location_access (membership_id, location_id, valid_from, valid_until);
create index idx_employees_org_status on public.employees (organization_id, status);
create index idx_employees_org_primary_location on public.employees (organization_id, primary_location_id);
create index idx_assignments_employee_dates on public.employee_location_assignments (employee_id, valid_from, valid_to);
create index idx_assignments_location_dates on public.employee_location_assignments (location_id, valid_from, valid_to);
create index idx_contracts_employee_dates on public.employee_contracts (employee_id, start_date, end_date);
create index idx_compensation_employee_dates on public.employee_compensation_rates (employee_id, effective_from, effective_to);
create index idx_audit_org_created on public.audit_log (organization_id, created_at desc);
create index idx_audit_entity on public.audit_log (entity_type, entity_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := clock_timestamp();
  if to_jsonb(new) ? 'updated_by' then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

create trigger organizations_set_updated_at before update on public.organizations
for each row execute function public.set_updated_at();
create trigger locations_set_updated_at before update on public.locations
for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at before update on public.user_profiles
for each row execute function public.set_updated_at();
create trigger roles_set_updated_at before update on public.roles
for each row execute function public.set_updated_at();
create trigger memberships_set_updated_at before update on public.organization_memberships
for each row execute function public.set_updated_at();
create trigger positions_set_updated_at before update on public.positions
for each row execute function public.set_updated_at();
create trigger cost_centers_set_updated_at before update on public.cost_centers
for each row execute function public.set_updated_at();
create trigger work_areas_set_updated_at before update on public.work_areas
for each row execute function public.set_updated_at();
create trigger employees_set_updated_at before update on public.employees
for each row execute function public.set_updated_at();
create trigger assignments_set_updated_at before update on public.employee_location_assignments
for each row execute function public.set_updated_at();
create trigger contract_types_set_updated_at before update on public.contract_types
for each row execute function public.set_updated_at();
create trigger feature_flags_set_updated_at before update on public.feature_flags
for each row execute function public.set_updated_at();

create or replace function public.is_active_org_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.valid_from <= clock_timestamp()
      and (m.valid_until is null or m.valid_until > clock_timestamp())
  );
$$;

create or replace function public.has_permission(p_organization_id uuid, p_permission_code text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.organization_memberships m
    join public.membership_roles mr
      on mr.organization_id = m.organization_id and mr.membership_id = m.id
    join public.role_permissions rp
      on rp.organization_id = mr.organization_id and rp.role_id = mr.role_id
    join public.permissions p on p.id = rp.permission_id
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.valid_from <= clock_timestamp()
      and (m.valid_until is null or m.valid_until > clock_timestamp())
      and mr.valid_from <= clock_timestamp()
      and (mr.valid_until is null or mr.valid_until > clock_timestamp())
      and p.code = p_permission_code
  );
$$;

create or replace function public.can_access_location(p_organization_id uuid, p_location_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.valid_from <= clock_timestamp()
      and (m.valid_until is null or m.valid_until > clock_timestamp())
      and (
        m.all_locations
        or exists (
          select 1 from public.membership_location_access mla
          where mla.organization_id = m.organization_id
            and mla.membership_id = m.id
            and mla.location_id = p_location_id
            and mla.valid_from <= clock_timestamp()
            and (mla.valid_until is null or mla.valid_until > clock_timestamp())
        )
      )
  );
$$;

create or replace function public.employee_is_in_scope(p_organization_id uuid, p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.employees e
    where e.organization_id = p_organization_id
      and e.id = p_employee_id
      and (
        e.user_id = auth.uid()
        or exists (
          select 1 from public.organization_memberships m
          where m.organization_id = e.organization_id
            and m.user_id = auth.uid()
            and m.status = 'active'
            and m.valid_from <= clock_timestamp()
            and (m.valid_until is null or m.valid_until > clock_timestamp())
            and (
              m.all_locations
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
                  and current_date between ela.valid_from and coalesce(ela.valid_to, 'infinity'::date)
                  and mla.valid_from <= clock_timestamp()
                  and (mla.valid_until is null or mla.valid_until > clock_timestamp())
              )
            )
        )
      )
  );
$$;

create or replace function public.current_actor_roles(p_organization_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(distinct r.code::text order by r.code::text), '{}')
  from public.organization_memberships m
  join public.membership_roles mr on mr.organization_id = m.organization_id and mr.membership_id = m.id
  join public.roles r on r.organization_id = mr.organization_id and r.id = mr.role_id
  where m.organization_id = p_organization_id
    and m.user_id = auth.uid()
    and m.status = 'active'
    and mr.valid_from <= clock_timestamp()
    and (mr.valid_until is null or mr.valid_until > clock_timestamp());
$$;

create or replace function public.write_audit_entry()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  payload_new jsonb;
  payload_old jsonb;
  org_id uuid;
  entity_uuid uuid;
begin
  payload_new := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  payload_old := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  org_id := coalesce((payload_new->>'organization_id')::uuid, (payload_old->>'organization_id')::uuid);
  entity_uuid := coalesce((payload_new->>'id')::uuid, (payload_old->>'id')::uuid);

  insert into public.audit_log (
    organization_id, actor_user_id, actor_roles, action,
    entity_type, entity_id, old_value, new_value
  ) values (
    org_id, auth.uid(), public.current_actor_roles(org_id),
    lower(tg_op), tg_table_name, entity_uuid, payload_old, payload_new
  );
  return null;
end;
$$;

create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'audit_log is immutable' using errcode = '42501';
end;
$$;

create trigger audit_log_immutable before update or delete on public.audit_log
for each row execute function public.prevent_audit_mutation();

create trigger audit_locations after insert or update or delete on public.locations
for each row execute function public.write_audit_entry();
create trigger audit_memberships after insert or update or delete on public.organization_memberships
for each row execute function public.write_audit_entry();
create trigger audit_roles after insert or update or delete on public.roles
for each row execute function public.write_audit_entry();
create trigger audit_role_permissions after insert or update or delete on public.role_permissions
for each row execute function public.write_audit_entry();
create trigger audit_membership_roles after insert or update or delete on public.membership_roles
for each row execute function public.write_audit_entry();
create trigger audit_membership_locations after insert or update or delete on public.membership_location_access
for each row execute function public.write_audit_entry();
create trigger audit_employees after insert or update or delete on public.employees
for each row execute function public.write_audit_entry();
create trigger audit_employee_contracts after insert or update or delete on public.employee_contracts
for each row execute function public.write_audit_entry();
create trigger audit_compensation after insert or update or delete on public.employee_compensation_rates
for each row execute function public.write_audit_entry();
create trigger audit_policies after insert or update or delete on public.organization_policies
for each row execute function public.write_audit_entry();
create trigger audit_feature_flags after insert or update or delete on public.feature_flags
for each row execute function public.write_audit_entry();

insert into public.permissions (code, description_key, sensitive) values
  ('organizations.view', 'permissions.organizations.view', false),
  ('organizations.manage', 'permissions.organizations.manage', true),
  ('locations.view', 'permissions.locations.view', false),
  ('locations.manage', 'permissions.locations.manage', true),
  ('memberships.view', 'permissions.memberships.view', true),
  ('memberships.manage', 'permissions.memberships.manage', true),
  ('roles.view', 'permissions.roles.view', true),
  ('roles.manage', 'permissions.roles.manage', true),
  ('employees.view', 'permissions.employees.view', false),
  ('employees.create', 'permissions.employees.create', true),
  ('employees.edit', 'permissions.employees.edit', true),
  ('employees.archive', 'permissions.employees.archive', true),
  ('employees.salary.view', 'permissions.employees.salary.view', true),
  ('employees.salary.manage', 'permissions.employees.salary.manage', true),
  ('employees.documents.view', 'permissions.employees.documents.view', true),
  ('employees.documents.manage', 'permissions.employees.documents.manage', true),
  ('attendance.view', 'permissions.attendance.view', false),
  ('attendance.edit', 'permissions.attendance.edit', true),
  ('attendance.approve', 'permissions.attendance.approve', true),
  ('overtime.approve', 'permissions.overtime.approve', true),
  ('schedules.view', 'permissions.schedules.view', false),
  ('schedules.create', 'permissions.schedules.create', true),
  ('schedules.publish', 'permissions.schedules.publish', true),
  ('reports.view', 'permissions.reports.view', false),
  ('reports.export', 'permissions.reports.export', true),
  ('payroll.view', 'permissions.payroll.view', true),
  ('payroll.close_period', 'permissions.payroll.close_period', true),
  ('payroll.reopen_period', 'permissions.payroll.reopen_period', true),
  ('settings.manage', 'permissions.settings.manage', true),
  ('devices.manage', 'permissions.devices.manage', true),
  ('audit.view', 'permissions.audit.view', true);

create or replace function public.create_organization_with_owner(
  p_name text,
  p_slug text,
  p_country_code text,
  p_currency text,
  p_timezone text,
  p_language public.supported_language default 'es'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_org_id uuid;
  membership_id uuid;
  owner_role_id uuid;
  base_role record;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  insert into public.organizations (
    name, slug, country_code, default_currency, default_timezone,
    default_language, created_by, updated_by
  ) values (
    p_name, p_slug, upper(p_country_code), upper(p_currency), p_timezone,
    p_language, auth.uid(), auth.uid()
  ) returning id into new_org_id;

  for base_role in
    select * from (values
      ('owner', 'roles.owner'), ('admin', 'roles.admin'),
      ('manager', 'roles.manager'), ('payroll', 'roles.payroll'),
      ('employee', 'roles.employee')
    ) as v(code, name_key)
  loop
    insert into public.roles (organization_id, code, name_key, is_base, created_by, updated_by)
    values (new_org_id, base_role.code, base_role.name_key, true, auth.uid(), auth.uid())
    returning id into owner_role_id;

    if base_role.code = 'owner' then
      insert into public.role_permissions (organization_id, role_id, permission_id, granted_by)
      select new_org_id, owner_role_id, id, auth.uid() from public.permissions;
    elsif base_role.code = 'employee' then
      insert into public.role_permissions (organization_id, role_id, permission_id, granted_by)
      select new_org_id, owner_role_id, id, auth.uid()
      from public.permissions where code in ('organizations.view', 'locations.view', 'schedules.view', 'attendance.view');
    end if;

    if base_role.code = 'owner' then
      exit;
    end if;
  end loop;

  -- El bucle sale despues de owner para capturar el rol; crear el resto por separado.
  insert into public.roles (organization_id, code, name_key, is_base, created_by, updated_by)
  select new_org_id, v.code, v.name_key, true, auth.uid(), auth.uid()
  from (values
    ('admin', 'roles.admin'), ('manager', 'roles.manager'),
    ('payroll', 'roles.payroll'), ('employee', 'roles.employee')
  ) as v(code, name_key)
  on conflict (organization_id, code) do nothing;

  insert into public.role_permissions (organization_id, role_id, permission_id, granted_by)
  select new_org_id, r.id, p.id, auth.uid()
  from public.roles r
  cross join public.permissions p
  where r.organization_id = new_org_id
    and (
      (r.code = 'admin' and p.code not in ('organizations.manage', 'roles.manage', 'payroll.reopen_period'))
      or (r.code = 'manager' and p.code in (
        'organizations.view', 'locations.view', 'employees.view', 'employees.create',
        'employees.edit', 'attendance.view', 'attendance.edit', 'attendance.approve',
        'overtime.approve', 'schedules.view', 'schedules.create', 'schedules.publish',
        'reports.view'
      ))
      or (r.code = 'payroll' and p.code in (
        'organizations.view', 'locations.view', 'employees.view', 'employees.salary.view',
        'attendance.view', 'reports.view', 'reports.export', 'payroll.view',
        'payroll.close_period'
      ))
      or (r.code = 'employee' and p.code in (
        'organizations.view', 'locations.view', 'schedules.view', 'attendance.view'
      ))
    );

  insert into public.organization_memberships (
    organization_id, user_id, status, all_locations,
    activated_at, created_by, updated_by
  ) values (
    new_org_id, auth.uid(), 'active', true,
    clock_timestamp(), auth.uid(), auth.uid()
  ) returning id into membership_id;

  insert into public.membership_roles (
    organization_id, membership_id, role_id, granted_by
  ) values (new_org_id, membership_id, owner_role_id, auth.uid());

  insert into public.audit_log (
    organization_id, actor_user_id, actor_roles, action,
    entity_type, entity_id, new_value
  ) values (
    new_org_id, auth.uid(), array['owner'], 'organization.created',
    'organizations', new_org_id, jsonb_build_object('name', p_name, 'slug', p_slug)
  );

  return new_org_id;
end;
$$;

-- RLS se habilita en todas las tablas publicas.
alter table public.organizations enable row level security;
alter table public.locations enable row level security;
alter table public.user_profiles enable row level security;
alter table public.permissions enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.membership_roles enable row level security;
alter table public.membership_location_access enable row level security;
alter table public.positions enable row level security;
alter table public.cost_centers enable row level security;
alter table public.work_areas enable row level security;
alter table public.employees enable row level security;
alter table public.employee_location_assignments enable row level security;
alter table public.contract_types enable row level security;
alter table public.employee_contracts enable row level security;
alter table public.employee_compensation_rates enable row level security;
alter table public.organization_policies enable row level security;
alter table public.feature_flags enable row level security;
alter table public.audit_log enable row level security;

create policy organizations_select on public.organizations for select
  using (public.is_active_org_member(id));
create policy organizations_update on public.organizations for update
  using (public.has_permission(id, 'organizations.manage'))
  with check (public.has_permission(id, 'organizations.manage'));

create policy locations_select on public.locations for select
  using (public.is_active_org_member(organization_id) and public.can_access_location(organization_id, id));
create policy locations_insert on public.locations for insert
  with check (public.has_permission(organization_id, 'locations.manage'));
create policy locations_update on public.locations for update
  using (public.has_permission(organization_id, 'locations.manage'))
  with check (public.has_permission(organization_id, 'locations.manage'));

create policy profiles_select on public.user_profiles for select using (user_id = auth.uid());
create policy profiles_insert on public.user_profiles for insert with check (user_id = auth.uid());
create policy profiles_update on public.user_profiles for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy permissions_select on public.permissions for select using (auth.uid() is not null);
create policy roles_select on public.roles for select
  using (
    public.has_permission(organization_id, 'roles.view')
    or exists (
      select 1 from public.organization_memberships m
      join public.membership_roles mr
        on mr.organization_id = m.organization_id and mr.membership_id = m.id
      where m.organization_id = roles.organization_id
        and m.user_id = auth.uid() and mr.role_id = roles.id
    )
  );
create policy roles_write on public.roles for all
  using (public.has_permission(organization_id, 'roles.manage'))
  with check (public.has_permission(organization_id, 'roles.manage'));
create policy role_permissions_select on public.role_permissions for select
  using (
    public.has_permission(organization_id, 'roles.view')
    or exists (
      select 1 from public.organization_memberships m
      join public.membership_roles mr
        on mr.organization_id = m.organization_id and mr.membership_id = m.id
      where m.organization_id = role_permissions.organization_id
        and m.user_id = auth.uid() and mr.role_id = role_permissions.role_id
    )
  );
create policy role_permissions_write on public.role_permissions for all
  using (public.has_permission(organization_id, 'roles.manage'))
  with check (public.has_permission(organization_id, 'roles.manage'));

create policy memberships_select on public.organization_memberships for select
  using (user_id = auth.uid() or public.has_permission(organization_id, 'memberships.view'));
create policy memberships_write on public.organization_memberships for all
  using (public.has_permission(organization_id, 'memberships.manage'))
  with check (public.has_permission(organization_id, 'memberships.manage'));
create policy membership_roles_select on public.membership_roles for select
  using (
    public.has_permission(organization_id, 'memberships.view')
    or exists (
      select 1 from public.organization_memberships m
      where m.organization_id = membership_roles.organization_id
        and m.id = membership_roles.membership_id and m.user_id = auth.uid()
    )
  );
create policy membership_roles_write on public.membership_roles for all
  using (public.has_permission(organization_id, 'memberships.manage'))
  with check (public.has_permission(organization_id, 'memberships.manage'));
create policy membership_locations_select on public.membership_location_access for select
  using (
    public.has_permission(organization_id, 'memberships.view')
    or exists (
      select 1 from public.organization_memberships m
      where m.organization_id = membership_location_access.organization_id
        and m.id = membership_location_access.membership_id and m.user_id = auth.uid()
    )
  );
create policy membership_locations_write on public.membership_location_access for all
  using (public.has_permission(organization_id, 'memberships.manage'))
  with check (public.has_permission(organization_id, 'memberships.manage'));

create policy positions_select on public.positions for select using (public.is_active_org_member(organization_id));
create policy positions_write on public.positions for all
  using (public.has_permission(organization_id, 'employees.edit'))
  with check (public.has_permission(organization_id, 'employees.edit'));
create policy cost_centers_select on public.cost_centers for select using (public.is_active_org_member(organization_id));
create policy cost_centers_write on public.cost_centers for all
  using (public.has_permission(organization_id, 'employees.edit'))
  with check (public.has_permission(organization_id, 'employees.edit'));
create policy work_areas_select on public.work_areas for select using (public.is_active_org_member(organization_id));
create policy work_areas_write on public.work_areas for all
  using (public.has_permission(organization_id, 'employees.edit'))
  with check (public.has_permission(organization_id, 'employees.edit'));

create policy employees_select on public.employees for select
  using (
    user_id = auth.uid()
    or (public.has_permission(organization_id, 'employees.view') and public.employee_is_in_scope(organization_id, id))
  );
create policy employees_insert on public.employees for insert
  with check (public.has_permission(organization_id, 'employees.create'));
create policy employees_update on public.employees for update
  using (public.has_permission(organization_id, 'employees.edit') and public.employee_is_in_scope(organization_id, id))
  with check (public.has_permission(organization_id, 'employees.edit') and public.employee_is_in_scope(organization_id, id));

create policy assignments_select on public.employee_location_assignments for select
  using (public.employee_is_in_scope(organization_id, employee_id));
create policy assignments_write on public.employee_location_assignments for all
  using (public.has_permission(organization_id, 'employees.edit') and public.employee_is_in_scope(organization_id, employee_id))
  with check (public.has_permission(organization_id, 'employees.edit') and public.can_access_location(organization_id, location_id));

create policy contract_types_select on public.contract_types for select using (public.is_active_org_member(organization_id));
create policy contract_types_write on public.contract_types for all
  using (public.has_permission(organization_id, 'employees.edit'))
  with check (public.has_permission(organization_id, 'employees.edit'));
create policy contracts_select on public.employee_contracts for select
  using (public.employee_is_in_scope(organization_id, employee_id));
create policy contracts_insert on public.employee_contracts for insert
  with check (public.has_permission(organization_id, 'employees.edit') and public.employee_is_in_scope(organization_id, employee_id));

create policy compensation_select on public.employee_compensation_rates for select
  using (public.has_permission(organization_id, 'employees.salary.view') and public.employee_is_in_scope(organization_id, employee_id));
create policy compensation_insert on public.employee_compensation_rates for insert
  with check (public.has_permission(organization_id, 'employees.salary.manage') and public.employee_is_in_scope(organization_id, employee_id));

create policy policies_select on public.organization_policies for select using (public.is_active_org_member(organization_id));
create policy policies_insert on public.organization_policies for insert
  with check (public.has_permission(organization_id, 'settings.manage'));
create policy feature_flags_select on public.feature_flags for select using (public.is_active_org_member(organization_id));
create policy feature_flags_write on public.feature_flags for all
  using (public.has_permission(organization_id, 'settings.manage'))
  with check (public.has_permission(organization_id, 'settings.manage'));
create policy audit_select on public.audit_log for select
  using (public.has_permission(organization_id, 'audit.view'));

revoke all on all tables in schema public from anon;
revoke all on public.audit_log, public.employee_compensation_rates from authenticated;
grant select on all tables in schema public to authenticated;
grant insert, update on public.locations, public.user_profiles, public.roles,
  public.role_permissions, public.organization_memberships, public.membership_roles,
  public.membership_location_access, public.positions, public.cost_centers,
  public.work_areas, public.employees, public.employee_location_assignments,
  public.contract_types, public.feature_flags to authenticated;
grant insert on public.employee_contracts, public.employee_compensation_rates,
  public.organization_policies to authenticated;
revoke all on function public.create_organization_with_owner(text, text, text, text, text, public.supported_language) from public;
grant execute on function public.create_organization_with_owner(text, text, text, text, text, public.supported_language) to authenticated;
revoke all on function public.is_active_org_member(uuid) from public;
revoke all on function public.has_permission(uuid, text) from public;
revoke all on function public.can_access_location(uuid, uuid) from public;
revoke all on function public.employee_is_in_scope(uuid, uuid) from public;
revoke all on function public.current_actor_roles(uuid) from public;
grant execute on function public.is_active_org_member(uuid), public.has_permission(uuid, text),
  public.can_access_location(uuid, uuid), public.employee_is_in_scope(uuid, uuid) to authenticated;

comment on table public.employee_compensation_rates is 'Append-only historical rates; close a range and insert a successor through a privileged workflow.';
comment on table public.audit_log is 'Immutable business audit trail. Client roles may only read when authorized.';
comment on function public.create_organization_with_owner is 'Atomic onboarding RPC; creates tenant, base roles, owner role permissions and membership.';

commit;
