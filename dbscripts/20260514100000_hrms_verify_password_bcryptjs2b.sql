`-- bcryptjs v3 (hrms-web) hashes passwords with a $2b$ prefix. PostgreSQL pgcrypto's
-- crypt() cannot verify those hashes against the raw stored string; normalizing the
-- bcrypt version prefix to $2a$ keeps verification aligned with Node bcryptjs/bcrypt.
-- Apply in Supabase SQL editor if mobile login fails with "Invalid email or password"
-- while web login succeeds for the same account.

create extension if not exists pgcrypto;

create or replace function hrms_verify_password(p_password text, p_hash text)
returns boolean
language plpgsql
stable
as $$
declare
  h text := coalesce(p_hash, '');
  normalized text;
  computed text;
  prefix text;
begin
  if h = '' or p_password is null then
    return false;
  end if;

  prefix := left(h, 4);
  normalized := case
    when prefix in ('$2b$', '$2y$', '$2x$') then '$2a$' || substr(h, 5)
    else h
  end;

  computed := crypt(p_password, normalized);
  return computed = h or computed = normalized;
end;
$$;
`