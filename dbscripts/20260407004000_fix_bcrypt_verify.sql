-- Improve bcrypt verification compatibility for hashes created by bcryptjs.
-- Some environments generate $2b$ hashes; pgcrypto's crypt() may expect $2a$.

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
begin
  if h = '' then
    return false;
  end if;

  -- Normalize $2b$ -> $2a$ for pgcrypto compatibility
  normalized := regexp_replace(h, '^\$2b\$', '\$2a\$');

  computed := crypt(p_password, normalized);

  -- Compare against either original hash or normalized form.
  return computed = h or computed = normalized;
end;
$$;

