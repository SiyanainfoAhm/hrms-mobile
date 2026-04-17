-- HRMS Postgres RPC functions (callable via Supabase `rpc`)
-- These are database functions (NOT edge functions).

create extension if not exists pgcrypto;

-- Verify bcrypt password_hash using pgcrypto's crypt().
create or replace function hrms_verify_password(p_password text, p_hash text)
returns boolean
language sql
stable
as $$
  select (crypt(p_password, p_hash) = p_hash);
$$;

-- Login: returns a single row with minimal session fields.
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
  from "HRMS_users"
  where lower(email) = lower(trim(p_email))
  limit 1;

  if u is null then
    raise exception 'Invalid email or password' using errcode = '28000';
  end if;

  if coalesce(u.auth_provider, 'password') <> 'password' then
    raise exception 'This account uses Google sign-in' using errcode = '28000';
  end if;

  if u.password_hash is null or not hrms_verify_password(p_password, u.password_hash) then
    raise exception 'Invalid email or password' using errcode = '28000';
  end if;

  id := u.id;
  email := u.email;
  name := u.name;
  role := u.role;
  company_id := u.company_id;
  auth_provider := coalesce(u.auth_provider, 'password');
  return next;
end;
$$;

-- Signup (password): creates user row.
create or replace function hrms_signup(p_email text, p_password text, p_name text default null)
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
  existing uuid;
  hashed text;
begin
  if normalized = '' or p_password is null or length(trim(p_password)) < 6 then
    raise exception 'Invalid email or password' using errcode = '22023';
  end if;

  select id into existing from "HRMS_users" where email = normalized limit 1;
  if existing is not null then
    raise exception 'Email already registered' using errcode = '23505';
  end if;

  hashed := crypt(p_password, gen_salt('bf'));

  insert into "HRMS_users"(email, password_hash, auth_provider, name, role, employment_status, created_at, updated_at)
  values (normalized, hashed, 'password', nullif(trim(p_name), ''), 'super_admin', 'current', now(), now())
  returning "HRMS_users".id, "HRMS_users".email, "HRMS_users".name, "HRMS_users".role, "HRMS_users".company_id, "HRMS_users".auth_provider
  into id, email, name, role, company_id, auth_provider;

  return next;
end;
$$;

-- "Me" lookup (for a given user id)
create or replace function hrms_me(p_user_id uuid)
returns table (
  id uuid,
  email text,
  name text,
  role text,
  company_id uuid,
  auth_provider text
)
language sql
stable
security definer
as $$
  select id, email, name, role, company_id, coalesce(auth_provider, 'password') as auth_provider
  from "HRMS_users"
  where id = p_user_id;
$$;

