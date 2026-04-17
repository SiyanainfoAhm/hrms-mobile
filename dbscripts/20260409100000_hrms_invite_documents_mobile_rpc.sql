-- Parity with web /api/company/documents and /api/invites for mobile (RPC + Edge Function for email).

create or replace function hrms_company_documents_list(p_actor_user_id uuid)
returns table (
  id uuid,
  company_id uuid,
  name text,
  kind HRMS_company_document_kind,
  is_mandatory boolean,
  content_text text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
as $$
declare
  actor_role text;
  cid uuid;
begin
  select u.role, u.company_id into actor_role, cid
  from "HRMS_users" u
  where u.id = p_actor_user_id;
  if cid is null then
    raise exception 'Actor not found' using errcode = 'P0001';
  end if;
  if actor_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;

  return query
  select d.id, d.company_id, d.name, d.kind, d.is_mandatory, d.content_text, d.created_at, d.updated_at
  from "HRMS_company_documents" d
  where d.company_id = cid
  order by d.created_at asc;
end;
$$;

create or replace function hrms_company_document_create(
  p_actor_user_id uuid,
  p_name text,
  p_kind text,
  p_is_mandatory boolean,
  p_content_text text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  actor_role text;
  cid uuid;
  nm text := trim(coalesce(p_name, ''));
  k HRMS_company_document_kind;
  ins "HRMS_company_documents"%rowtype;
begin
  if length(nm) < 1 then
    raise exception 'Name is required' using errcode = 'P0001';
  end if;
  if p_kind not in ('upload', 'digital_signature') then
    raise exception 'Invalid kind' using errcode = 'P0001';
  end if;
  k := p_kind::HRMS_company_document_kind;

  select u.role, u.company_id into actor_role, cid
  from "HRMS_users" u
  where u.id = p_actor_user_id;
  if cid is null then
    raise exception 'Actor not found' using errcode = 'P0001';
  end if;
  if actor_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;

  insert into "HRMS_company_documents" (company_id, name, kind, is_mandatory, content_text)
  values (
    cid,
    nm,
    k,
    coalesce(p_is_mandatory, true),
    case when k = 'digital_signature' then nullif(trim(coalesce(p_content_text, '')), '') else null end
  )
  returning * into ins;

  return to_jsonb(ins);
end;
$$;

-- Same DB rules as POST /api/invites: revoke pending for email, new token, 48h expiry.
create or replace function hrms_employee_invite_issue(
  p_actor_user_id uuid,
  p_email text,
  p_target_user_id uuid,
  p_requested_document_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  actor_role text;
  actor_company uuid;
  em text := lower(trim(coalesce(p_email, '')));
  targ_company uuid;
  targ_email text;
  tok text;
  exp_at timestamptz := now() + interval '48 hours';
  new_inv "HRMS_employee_invites"%rowtype;
  doc_count int;
begin
  if em = '' then
    raise exception 'Email is required' using errcode = 'P0001';
  end if;

  select u.role, u.company_id into actor_role, actor_company
  from "HRMS_users" u
  where u.id = p_actor_user_id;
  if actor_company is null then
    raise exception 'Actor not found' using errcode = 'P0001';
  end if;
  if actor_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;

  select u.company_id, lower(trim(u.email)) into targ_company, targ_email
  from "HRMS_users" u
  where u.id = p_target_user_id;
  if targ_company is null then
    raise exception 'Employee not found' using errcode = 'P0001';
  end if;
  if targ_company <> actor_company then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;
  if targ_email <> em then
    raise exception 'Email does not match employee' using errcode = 'P0001';
  end if;

  if p_requested_document_ids is not null and array_length(p_requested_document_ids, 1) is not null then
    select count(*) into doc_count
    from "HRMS_company_documents" d
    where d.company_id = actor_company
      and d.id = any (p_requested_document_ids);
    if doc_count <> array_length(p_requested_document_ids, 1) then
      raise exception 'Invalid document selection' using errcode = 'P0001';
    end if;
  end if;

  update "HRMS_employee_invites" i
  set status = 'revoked'
  where i.company_id = actor_company
    and lower(trim(i.email)) = em
    and i.status = 'pending';

  tok := replace(gen_random_uuid()::text, '-', '');

  insert into "HRMS_employee_invites" (
    company_id,
    user_id,
    email,
    token,
    requested_document_ids,
    status,
    expires_at,
    created_by
  )
  values (
    actor_company,
    p_target_user_id,
    em,
    tok,
    case
      when p_requested_document_ids is not null and array_length(p_requested_document_ids, 1) is not null
      then to_jsonb(p_requested_document_ids)
      else null
    end,
    'pending',
    exp_at,
    p_actor_user_id
  )
  returning * into new_inv;

  return jsonb_build_object(
    'invite', to_jsonb(new_inv)
  );
end;
$$;

create or replace function hrms_employee_onboarding_for_manager(
  p_actor_user_id uuid,
  p_target_user_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  actor_role text;
  actor_company uuid;
  emp jsonb;
  inv jsonb;
  inv_id uuid;
  req_ids uuid[];
  docs jsonb;
  subs jsonb;
begin
  select u.role, u.company_id into actor_role, actor_company
  from "HRMS_users" u
  where u.id = p_actor_user_id;
  if actor_company is null then
    raise exception 'Actor not found' using errcode = 'P0001';
  end if;
  if actor_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;

  select to_jsonb(u.*) into emp
  from "HRMS_users" u
  where u.id = p_target_user_id
    and u.company_id = actor_company;
  if emp is null then
    raise exception 'Employee not found' using errcode = 'P0001';
  end if;

  select to_jsonb(i.*) into inv
  from "HRMS_employee_invites" i
  where i.company_id = actor_company
    and i.user_id = p_target_user_id
  order by i.created_at desc
  limit 1;

  if inv is null then
    docs := '[]'::jsonb;
    subs := '[]'::jsonb;
  else
    inv_id := (inv->>'id')::uuid;
    if inv ? 'requested_document_ids' and jsonb_typeof(inv->'requested_document_ids') = 'array' then
      select array_agg(x::uuid)
      into req_ids
      from jsonb_array_elements_text(inv->'requested_document_ids') as t(x);
    end if;

    select coalesce(jsonb_agg(to_jsonb(d.*) order by d.created_at), '[]'::jsonb)
    into docs
    from "HRMS_company_documents" d
    where d.company_id = actor_company
      and (
        req_ids is null
        or array_length(req_ids, 1) is null
        or d.id = any (req_ids)
      );

    select coalesce(jsonb_agg(to_jsonb(s.*)), '[]'::jsonb)
    into subs
    from "HRMS_employee_document_submissions" s
    where s.invite_id = inv_id;
  end if;

  return jsonb_build_object(
    'employee', emp,
    'invite', inv,
    'documents', docs,
    'submissions', subs
  );
end;
$$;

grant execute on function hrms_company_documents_list(uuid) to anon, authenticated;
grant execute on function hrms_company_document_create(uuid, text, text, boolean, text) to anon, authenticated;
grant execute on function hrms_employee_invite_issue(uuid, text, uuid, uuid[]) to anon, authenticated;
grant execute on function hrms_employee_onboarding_for_manager(uuid, uuid) to anon, authenticated;
