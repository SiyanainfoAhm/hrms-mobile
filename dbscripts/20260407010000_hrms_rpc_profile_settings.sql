-- Full profile (read/write) + company settings + settings lists for mobile parity with web

-- PROFILE: full row as JSON (no password hash)
create or replace function hrms_profile_full_get(p_user_id uuid)
returns jsonb
language sql
stable
security definer
as $$
  select to_jsonb(u) - 'password_hash'
  from "HRMS_users" u
  where u.id = p_user_id;
$$;

-- PROFILE: patch JSON (snake_case keys). Enforces role rules similar to web /api/me PUT.
create or replace function hrms_profile_full_save(p_user_id uuid, p_actor_role text, p_patch jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  patch jsonb := coalesce(p_patch, '{}'::jsonb);
  r text := coalesce(p_actor_role, '');
begin
  if not exists (select 1 from "HRMS_users" u where u.id = p_user_id) then
    raise exception 'User not found' using errcode = 'P0001';
  end if;

  -- Super admin: only basic account fields (matches web profile for super_admin)
  if r = 'super_admin' then
    patch := jsonb_strip_nulls(jsonb_build_object(
      'name', patch->'name',
      'phone', patch->'phone',
      'gender', patch->'gender'
    ));
  else
    -- Employees / managers: cannot set employment or UAN (managerial-only on web)
    if r not in ('admin', 'hr') then
      patch := patch - 'employment_status' - 'ctc' - 'uan_number';
    end if;
  end if;

  update "HRMS_users" u
  set
    name = case when patch ? 'name' then nullif(trim(patch->>'name'), '') else u.name end,
    phone = case when patch ? 'phone' then nullif(trim(patch->>'phone'), '') else u.phone end,
    gender = case
      when patch ? 'gender' and trim(coalesce(patch->>'gender', '')) in ('male', 'female', 'other') then trim(patch->>'gender')
      when patch ? 'gender' and trim(coalesce(patch->>'gender', '')) = '' then u.gender
      else u.gender
    end,
    employee_code = case when patch ? 'employee_code' and r <> 'super_admin' then nullif(trim(patch->>'employee_code'), '') else u.employee_code end,
    date_of_birth = case when patch ? 'date_of_birth' and r <> 'super_admin' then nullif(trim(patch->>'date_of_birth'), '')::date else u.date_of_birth end,
    date_of_joining = case when patch ? 'date_of_joining' and r <> 'super_admin' then nullif(trim(patch->>'date_of_joining'), '')::date else u.date_of_joining end,
    current_address_line1 = case when patch ? 'current_address_line1' and r <> 'super_admin' then nullif(trim(patch->>'current_address_line1'), '') else u.current_address_line1 end,
    current_address_line2 = case when patch ? 'current_address_line2' and r <> 'super_admin' then nullif(trim(patch->>'current_address_line2'), '') else u.current_address_line2 end,
    current_city = case when patch ? 'current_city' and r <> 'super_admin' then nullif(trim(patch->>'current_city'), '') else u.current_city end,
    current_state = case when patch ? 'current_state' and r <> 'super_admin' then nullif(trim(patch->>'current_state'), '') else u.current_state end,
    current_country = case when patch ? 'current_country' and r <> 'super_admin' then nullif(trim(patch->>'current_country'), '') else u.current_country end,
    current_postal_code = case when patch ? 'current_postal_code' and r <> 'super_admin' then nullif(trim(patch->>'current_postal_code'), '') else u.current_postal_code end,
    permanent_address_line1 = case when patch ? 'permanent_address_line1' and r <> 'super_admin' then nullif(trim(patch->>'permanent_address_line1'), '') else u.permanent_address_line1 end,
    permanent_address_line2 = case when patch ? 'permanent_address_line2' and r <> 'super_admin' then nullif(trim(patch->>'permanent_address_line2'), '') else u.permanent_address_line2 end,
    permanent_city = case when patch ? 'permanent_city' and r <> 'super_admin' then nullif(trim(patch->>'permanent_city'), '') else u.permanent_city end,
    permanent_state = case when patch ? 'permanent_state' and r <> 'super_admin' then nullif(trim(patch->>'permanent_state'), '') else u.permanent_state end,
    permanent_country = case when patch ? 'permanent_country' and r <> 'super_admin' then nullif(trim(patch->>'permanent_country'), '') else u.permanent_country end,
    permanent_postal_code = case when patch ? 'permanent_postal_code' and r <> 'super_admin' then nullif(trim(patch->>'permanent_postal_code'), '') else u.permanent_postal_code end,
    emergency_contact_name = case when patch ? 'emergency_contact_name' and r <> 'super_admin' then nullif(trim(patch->>'emergency_contact_name'), '') else u.emergency_contact_name end,
    emergency_contact_phone = case when patch ? 'emergency_contact_phone' and r <> 'super_admin' then nullif(trim(patch->>'emergency_contact_phone'), '') else u.emergency_contact_phone end,
    bank_name = case when patch ? 'bank_name' and r <> 'super_admin' then nullif(trim(patch->>'bank_name'), '') else u.bank_name end,
    bank_account_number = case when patch ? 'bank_account_number' and r <> 'super_admin' then nullif(trim(patch->>'bank_account_number'), '') else u.bank_account_number end,
    bank_ifsc = case when patch ? 'bank_ifsc' and r <> 'super_admin' then nullif(trim(patch->>'bank_ifsc'), '') else u.bank_ifsc end,
    employment_status = case
      when patch ? 'employment_status' and r in ('admin', 'hr') and trim(coalesce(patch->>'employment_status', '')) in ('preboarding', 'current', 'past')
      then trim(patch->>'employment_status')
      else u.employment_status
    end,
    ctc = case
      when patch ? 'ctc' and r in ('admin', 'hr') and trim(coalesce(patch->>'ctc', '')) <> '' then (patch->>'ctc')::numeric
      when patch ? 'ctc' and r in ('admin', 'hr') and trim(coalesce(patch->>'ctc', '')) = '' then null
      else u.ctc
    end,
    designation = case when patch ? 'designation' and r <> 'super_admin' then nullif(trim(patch->>'designation'), '') else u.designation end,
    designation_id = case
      when patch ? 'designation_id' and r <> 'super_admin' then
        case when nullif(trim(patch->>'designation_id'), '') is null then null else trim(patch->>'designation_id')::uuid end
      else u.designation_id
    end,
    department_id = case
      when patch ? 'department_id' and r <> 'super_admin' then
        case when nullif(trim(patch->>'department_id'), '') is null then null else trim(patch->>'department_id')::uuid end
      else u.department_id
    end,
    division_id = case
      when patch ? 'division_id' and r <> 'super_admin' then
        case when nullif(trim(patch->>'division_id'), '') is null then null else trim(patch->>'division_id')::uuid end
      else u.division_id
    end,
    shift_id = case
      when patch ? 'shift_id' and r <> 'super_admin' then
        case when nullif(trim(patch->>'shift_id'), '') is null then null else trim(patch->>'shift_id')::uuid end
      else u.shift_id
    end,
    aadhaar = case when patch ? 'aadhaar' and r <> 'super_admin' then nullif(trim(patch->>'aadhaar'), '') else u.aadhaar end,
    pan = case when patch ? 'pan' and r <> 'super_admin' then nullif(trim(patch->>'pan'), '') else u.pan end,
    uan_number = case when patch ? 'uan_number' and r in ('super_admin', 'admin', 'hr') then nullif(trim(patch->>'uan_number'), '') else u.uan_number end,
    pf_number = case when patch ? 'pf_number' and r <> 'super_admin' then nullif(trim(patch->>'pf_number'), '') else u.pf_number end,
    esic_number = case when patch ? 'esic_number' and r <> 'super_admin' then nullif(trim(patch->>'esic_number'), '') else u.esic_number end,
    updated_at = now()
  where u.id = p_user_id;

  return (select to_jsonb(u) - 'password_hash' from "HRMS_users" u where u.id = p_user_id);
end;
$$;

-- Company for logged-in user's company_id (read)
create or replace function hrms_company_get_for_user(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
  cid uuid;
begin
  select u.company_id into cid from "HRMS_users" u where u.id = p_user_id;
  if cid is null then
    return null;
  end if;
  return (select to_jsonb(c) from "HRMS_companies" c where c.id = cid);
end;
$$;

-- Company update: super_admin only, same company as user
create or replace function hrms_company_save(p_user_id uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  cid uuid;
  r text;
  patch jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  select u.company_id, u.role into cid, r from "HRMS_users" u where u.id = p_user_id;
  if cid is null then
    raise exception 'User not linked to company' using errcode = 'P0001';
  end if;
  if r <> 'super_admin' then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;

  if patch ? 'name' and nullif(trim(patch->>'name'), '') is null then
    raise exception 'Company name is required' using errcode = 'P0001';
  end if;

  update "HRMS_companies" c
  set
    name = case when patch ? 'name' then nullif(trim(patch->>'name'), '') else c.name end,
    code = case when patch ? 'code' then nullif(trim(patch->>'code'), '') else c.code end,
    industry = case when patch ? 'industry' then nullif(trim(patch->>'industry'), '') else c.industry end,
    address_line1 = case when patch ? 'address_line1' then nullif(trim(patch->>'address_line1'), '') else c.address_line1 end,
    address_line2 = case when patch ? 'address_line2' then nullif(trim(patch->>'address_line2'), '') else c.address_line2 end,
    city = case when patch ? 'city' then nullif(trim(patch->>'city'), '') else c.city end,
    state = case when patch ? 'state' then nullif(trim(patch->>'state'), '') else c.state end,
    country = case when patch ? 'country' then nullif(trim(patch->>'country'), '') else c.country end,
    postal_code = case when patch ? 'postal_code' then nullif(trim(patch->>'postal_code'), '') else c.postal_code end,
    phone = case when patch ? 'phone' then nullif(trim(patch->>'phone'), '') else c.phone end,
    professional_tax_annual = case when patch ? 'professional_tax_annual' then greatest(0, (patch->>'professional_tax_annual')::numeric) else c.professional_tax_annual end,
    professional_tax_monthly = case when patch ? 'professional_tax_monthly' then greatest(0, (patch->>'professional_tax_monthly')::numeric) else c.professional_tax_monthly end,
    updated_at = now()
  where c.id = cid;

  return (select to_jsonb(c) from "HRMS_companies" c where c.id = cid);
end;
$$;

-- Settings: full lists (including inactive) for admin/hr/super_admin screens
create or replace function hrms_settings_shifts_all(p_company_id uuid)
returns jsonb
language sql
stable
security definer
as $$
  select coalesce(
    (select jsonb_agg(to_jsonb(s) order by s.created_at desc)
     from "HRMS_shifts" s where s.company_id = p_company_id),
    '[]'::jsonb
  );
$$;

create or replace function hrms_settings_divisions_all(p_company_id uuid)
returns jsonb
language sql
stable
security definer
as $$
  select coalesce(
    (select jsonb_agg(to_jsonb(d) order by d.name)
     from "HRMS_divisions" d where d.company_id = p_company_id),
    '[]'::jsonb
  );
$$;

create or replace function hrms_settings_departments_all(p_company_id uuid)
returns jsonb
language sql
stable
security definer
as $$
  select coalesce(
    (select jsonb_agg(to_jsonb(d) order by d.name)
     from "HRMS_departments" d where d.company_id = p_company_id),
    '[]'::jsonb
  );
$$;

create or replace function hrms_settings_designations_all(p_company_id uuid)
returns jsonb
language sql
stable
security definer
as $$
  select coalesce(
    (select jsonb_agg(to_jsonb(d) order by d.title)
     from "HRMS_designations" d where d.company_id = p_company_id),
    '[]'::jsonb
  );
$$;

create or replace function hrms_settings_roles_all(p_company_id uuid)
returns jsonb
language sql
stable
security definer
as $$
  select coalesce(
    (select jsonb_agg(to_jsonb(r) order by r.name)
     from "HRMS_roles" r where r.company_id = p_company_id),
    '[]'::jsonb
  );
$$;
