-- Password signup: require organization name, create HRMS_companies then link super_admin user.
-- (Google self-provisioning is disabled in hrms-web `/api/auth/google`; Super Admin adds Google users in-app.)

create or replace function hrms_signup(
  p_email text,
  p_password text,
  p_name text default null,
  p_company_name text default null
)
returns table (
  id uuid,
  email text,
  name text,
  role text,
  company_id uuid,
  auth_provider text
)
language plpgsql
security definer
as $$
declare
  normalized text := lower(trim(p_email));
  existing_id uuid;
  hashed text;
  inserted record;
  v_company_id uuid;
  v_company_name text := nullif(trim(p_company_name), '');
  v_org_code text;
  v_emp_code text;
begin
  if normalized = '' or p_password is null or length(trim(p_password)) < 6 then
    raise exception 'Invalid email or password' using errcode = '22023';
  end if;

  if v_company_name is null then
    raise exception 'Company name is required' using errcode = '22023';
  end if;

  select hu.id
    into existing_id
  from "HRMS_users" hu
  where hu.email = normalized
  limit 1;

  if existing_id is not null then
    raise exception 'User already exists' using errcode = '23505';
  end if;

  v_org_code := 'ORG-' || upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10));

  insert into "HRMS_companies" (name, code)
  values (v_company_name, v_org_code)
  returning id into v_company_id;

  hashed := crypt(p_password, gen_salt('bf'));

  v_emp_code := 'EMP-' || upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 8));

  insert into "HRMS_users"(
    email,
    password_hash,
    auth_provider,
    name,
    role,
    employment_status,
    company_id,
    employee_code,
    created_at,
    updated_at
  )
  values (
    normalized,
    hashed,
    'password',
    nullif(trim(p_name), ''),
    'super_admin',
    'current',
    v_company_id,
    v_emp_code,
    now(),
    now()
  )
  returning "HRMS_users".id,
          "HRMS_users".email,
          "HRMS_users".name,
          "HRMS_users".role,
          "HRMS_users".company_id,
          "HRMS_users".auth_provider
  into inserted;

  return query
  select inserted.id, inserted.email, inserted.name, inserted.role, inserted.company_id, inserted.auth_provider;
end;
$$;

-- Align password login “unknown email” message with mobile/web copy.
create or replace function hrms_login(p_email text, p_password text)
returns table (
  id uuid,
  email text,
  name text,
  role text,
  company_id uuid,
  auth_provider text
)
language plpgsql
security definer
as $$
declare
  u record;
begin
  select *
    into u
  from "HRMS_users" hu
  where lower(hu.email) = lower(trim(p_email))
  limit 1;

  if u is null then
    raise exception 'User does not exist' using errcode = '28000';
  end if;

  if coalesce(u.auth_provider, 'password') <> 'password' then
    raise exception 'This account uses Google sign-in' using errcode = '28000';
  end if;

  if u.password_hash is null or not hrms_verify_password(p_password, u.password_hash) then
    raise exception 'Invalid email or password' using errcode = '28000';
  end if;

  return query
  select u.id, u.email, u.name, u.role, u.company_id, coalesce(u.auth_provider, 'password');
end;
$$;
