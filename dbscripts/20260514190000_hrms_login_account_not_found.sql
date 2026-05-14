-- Distinct message when email is not registered (mobile/web parity for clearer UX).
-- Wrong password still returns "Invalid email or password".

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
    raise exception 'Account does not exist' using errcode = '28000';
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
