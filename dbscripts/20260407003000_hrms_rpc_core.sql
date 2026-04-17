-- Core HRMS RPC functions (Postgres). Call via Supabase `rpc`.
-- NOTE: These functions assume your DB is not protected by RLS (as in hrms_schema.sql).
-- You should add RLS/policies before using anon key in production.

create extension if not exists pgcrypto;

-- bcrypt verify using pgcrypto's crypt()
create or replace function hrms_verify_password(p_password text, p_hash text)
returns boolean
language sql
stable
as $$
  select (crypt(p_password, p_hash) = p_hash);
$$;

-- HOLIDAYS
create or replace function hrms_holidays_list(p_company_id uuid)
returns table (
  id uuid,
  name text,
  holiday_date date,
  holiday_end_date date,
  is_optional boolean,
  location text
)
language sql
stable
security definer
as $$
  select h.id, h.name, h.holiday_date, h.holiday_end_date, h.is_optional, h.location
  from "HRMS_holidays" h
  where h.company_id = p_company_id
  order by h.holiday_date asc, h.name asc;
$$;

create or replace function hrms_holidays_create(
  p_company_id uuid,
  p_name text,
  p_holiday_date date,
  p_holiday_end_date date default null,
  p_is_optional boolean default false,
  p_location text default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  new_id uuid;
begin
  if p_company_id is null then raise exception 'company_id is required' using errcode = '22023'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name is required' using errcode = '22023'; end if;
  if p_holiday_date is null then raise exception 'holiday_date is required' using errcode = '22023'; end if;

  insert into "HRMS_holidays"(company_id, name, holiday_date, holiday_end_date, is_optional, location, created_at)
  values (p_company_id, trim(p_name), p_holiday_date, p_holiday_end_date, coalesce(p_is_optional,false), nullif(trim(p_location),''), now())
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function hrms_holidays_update(
  p_company_id uuid,
  p_id uuid,
  p_name text,
  p_holiday_date date,
  p_holiday_end_date date,
  p_is_optional boolean,
  p_location text
)
returns boolean
language plpgsql
security definer
as $$
begin
  update "HRMS_holidays" h
  set name = coalesce(nullif(trim(p_name), ''), h.name),
      holiday_date = coalesce(p_holiday_date, h.holiday_date),
      holiday_end_date = p_holiday_end_date,
      is_optional = coalesce(p_is_optional, h.is_optional),
      location = nullif(trim(p_location), ''),
      updated_at = now()
  where h.company_id = p_company_id and h.id = p_id;
  return found;
end;
$$;

create or replace function hrms_holidays_delete(p_company_id uuid, p_id uuid)
returns boolean
language plpgsql
security definer
as $$
begin
  delete from "HRMS_holidays" h where h.company_id = p_company_id and h.id = p_id;
  return found;
end;
$$;

-- EMPLOYEES DIRECTORY (managerial)
create or replace function hrms_employees_list(p_company_id uuid, p_tab text)
returns table (
  id uuid,
  email text,
  name text,
  role text,
  employment_status text,
  employee_code text,
  phone text,
  date_of_joining date,
  date_of_leaving date,
  ctc numeric,
  designation text,
  department_id uuid,
  division_id uuid,
  shift_id uuid
)
language sql
stable
security definer
as $$
  select u.id,
         u.email,
         u.name,
         u.role,
         u.employment_status,
         u.employee_code,
         u.phone,
         u.date_of_joining,
         u.date_of_leaving,
         u.ctc,
         u.designation,
         u.department_id,
         u.division_id,
         u.shift_id
  from "HRMS_users" u
  where u.company_id = p_company_id
    and u.role <> 'super_admin'
    and (
      case
        when p_tab = 'preboarding' then u.employment_status = 'preboarding'
        when p_tab = 'current' then u.employment_status = 'current' and u.date_of_leaving is null
        when p_tab = 'past' then u.employment_status = 'past'
        when p_tab = 'notice' then u.employment_status = 'current' and u.date_of_leaving is not null and u.date_of_leaving > current_date
        else true
      end
    )
  order by u.created_at desc;
$$;

-- PROFILE (self)
create or replace function hrms_profile_get(p_user_id uuid)
returns table (
  id uuid,
  email text,
  name text,
  phone text,
  gender text,
  date_of_birth date,
  employee_code text,
  auth_provider text
)
language sql
stable
security definer
as $$
  select u.id, u.email, u.name, u.phone, u.gender, u.date_of_birth, u.employee_code, coalesce(u.auth_provider,'password')
  from "HRMS_users" u
  where u.id = p_user_id;
$$;

create or replace function hrms_profile_update(
  p_user_id uuid,
  p_name text default null,
  p_phone text default null,
  p_gender text default null,
  p_date_of_birth date default null
)
returns boolean
language plpgsql
security definer
as $$
begin
  update "HRMS_users" u
  set name = coalesce(nullif(trim(p_name),''), u.name),
      phone = coalesce(nullif(trim(p_phone),''), u.phone),
      gender = case when p_gender in ('male','female','other') then p_gender else u.gender end,
      date_of_birth = coalesce(p_date_of_birth, u.date_of_birth),
      updated_at = now()
  where u.id = p_user_id;
  return found;
end;
$$;

-- SETTINGS LOOKUPS
create or replace function hrms_settings_designations(p_company_id uuid)
returns table (id uuid, title text, is_active boolean)
language sql
stable
security definer
as $$
  select d.id, d.title, d.is_active
  from "HRMS_designations" d
  where d.company_id = p_company_id and d.is_active = true
  order by d.title asc;
$$;

create or replace function hrms_settings_departments(p_company_id uuid)
returns table (id uuid, name text, division_id uuid, is_active boolean)
language sql
stable
security definer
as $$
  select d.id, d.name, d.division_id, d.is_active
  from "HRMS_departments" d
  where d.company_id = p_company_id and d.is_active = true
  order by d.name asc;
$$;

create or replace function hrms_settings_divisions(p_company_id uuid)
returns table (id uuid, name text, is_active boolean)
language sql
stable
security definer
as $$
  select d.id, d.name, d.is_active
  from "HRMS_divisions" d
  where d.company_id = p_company_id and d.is_active = true
  order by d.name asc;
$$;

create or replace function hrms_settings_shifts(p_company_id uuid)
returns table (id uuid, name text, is_active boolean)
language sql
stable
security definer
as $$
  select s.id, s.name, s.is_active
  from "HRMS_shifts" s
  where s.company_id = p_company_id and s.is_active = true
  order by s.name asc;
$$;

-- PAYROLL / PAYSLIPS (read-only)
create or replace function hrms_payroll_periods(p_company_id uuid)
returns table (id uuid, period_name text, period_start date, period_end date, is_locked boolean)
language sql
stable
security definer
as $$
  select p.id, p.period_name, p.period_start, p.period_end, p.is_locked
  from "HRMS_payroll_periods" p
  where p.company_id = p_company_id
  order by p.period_start desc;
$$;

create or replace function hrms_payslips_list(p_company_id uuid, p_employee_user_id uuid)
returns table (
  id uuid,
  payroll_period_id uuid,
  generated_at timestamptz,
  net_pay numeric,
  gross_pay numeric
)
language sql
stable
security definer
as $$
  select ps.id, ps.payroll_period_id, ps.generated_at, ps.net_pay, ps.gross_pay
  from "HRMS_payslips" ps
  where ps.company_id = p_company_id and ps.employee_user_id = p_employee_user_id
  order by ps.generated_at desc;
$$;

