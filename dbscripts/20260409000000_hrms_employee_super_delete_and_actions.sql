-- Super admin: delete employee user (cascades). Managerial: convert / revoke notice (mobile + RPC parity with web).

-- Past tab: same as web — includes notice (current + date_of_leaving set)
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
        when p_tab = 'past' then
          u.employment_status = 'past'
          or (u.employment_status = 'current' and u.date_of_leaving is not null)
        when p_tab = 'notice' then u.employment_status = 'current' and u.date_of_leaving is not null and u.date_of_leaving > (current_timestamp at time zone 'UTC')::date
        else true
      end
    )
  order by u.created_at desc;
$$;

create or replace function hrms_employee_delete_super(
  p_actor_user_id uuid,
  p_target_user_id uuid
)
returns void
language plpgsql
security definer
as $$
declare
  actor_role text;
  actor_company uuid;
  targ_role text;
  targ_company uuid;
begin
  if p_actor_user_id = p_target_user_id then
    raise exception 'Cannot delete your own account' using errcode = 'P0001';
  end if;

  select role, company_id into actor_role, actor_company from "HRMS_users" where id = p_actor_user_id;
  if actor_role is null then
    raise exception 'Actor not found' using errcode = 'P0001';
  end if;
  if actor_role <> 'super_admin' then
    raise exception 'Only super admins can delete employees' using errcode = 'P0001';
  end if;
  if actor_company is null then
    raise exception 'Actor not linked to a company' using errcode = 'P0001';
  end if;

  select role, company_id into targ_role, targ_company from "HRMS_users" where id = p_target_user_id;
  if targ_company is null then
    raise exception 'Employee not found' using errcode = 'P0001';
  end if;
  if targ_company <> actor_company then
    raise exception 'Employee is not in your company' using errcode = 'P0001';
  end if;
  if targ_role = 'super_admin' then
    raise exception 'Cannot delete a super admin' using errcode = 'P0001';
  end if;

  delete from "HRMS_users" where id = p_target_user_id;
end;
$$;

-- Managerial: convert to current / past (with optional last working date) / revoke notice. No invite required (web PATCH is stricter).
create or replace function hrms_employee_management_action(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_action text,
  p_date_yyyy_mm_dd text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  actor_role text;
  actor_company uuid;
  targ_company uuid;
  targ_role text;
  d date;
  today date := (current_timestamp at time zone 'UTC')::date;
  next_status text;
  inv_completed boolean;
begin
  if p_target_user_id = p_actor_user_id then
    raise exception 'Invalid target' using errcode = 'P0001';
  end if;

  select role, company_id into actor_role, actor_company from "HRMS_users" where id = p_actor_user_id;
  if actor_role is null or actor_company is null then
    raise exception 'Actor not found' using errcode = 'P0001';
  end if;
  if actor_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;

  select company_id, role into targ_company, targ_role from "HRMS_users" where id = p_target_user_id;
  if targ_company is null then
    raise exception 'Employee not found' using errcode = 'P0001';
  end if;
  if targ_company <> actor_company then
    raise exception 'Forbidden' using errcode = 'P0001';
  end if;
  if targ_role = 'super_admin' then
    raise exception 'Cannot modify super admin' using errcode = 'P0001';
  end if;

  if p_action = 'convert_current' then
    if actor_role <> 'super_admin' then
      select exists (
        select 1
        from (
          select i.status
          from "HRMS_employee_invites" i
          where i.company_id = actor_company
            and i.user_id = p_target_user_id
          order by i.created_at desc
          limit 1
        ) x
        where x.status = 'completed'
      ) into inv_completed;
      if not coalesce(inv_completed, false) then
        raise exception 'Invite not completed yet' using errcode = 'P0001';
      end if;
    end if;

    d := case
      when p_date_yyyy_mm_dd is not null and length(trim(p_date_yyyy_mm_dd)) >= 10
      then trim(p_date_yyyy_mm_dd)::date
      else null
    end;

    update "HRMS_users" u
    set
      employment_status = 'current',
      date_of_joining = coalesce(d, u.date_of_joining, today),
      date_of_leaving = null,
      updated_at = now()
    where u.id = p_target_user_id and u.company_id = actor_company;

    update "HRMS_employees" e
    set
      is_active = true,
      date_of_joining = coalesce(
        d,
        e.date_of_joining,
        (select u2.date_of_joining from "HRMS_users" u2 where u2.id = p_target_user_id limit 1)
      ),
      date_of_leaving = null,
      updated_at = now()
    where e.user_id = p_target_user_id and e.company_id = actor_company;

    return jsonb_build_object('ok', true, 'action', 'convert_current');

  elsif p_action = 'revoke_notice' then
    update "HRMS_users" u
    set employment_status = 'current', date_of_leaving = null, updated_at = now()
    where u.id = p_target_user_id and u.company_id = actor_company;

    update "HRMS_employees" e
    set is_active = true, date_of_leaving = null, updated_at = now()
    where e.user_id = p_target_user_id and e.company_id = actor_company;

    return jsonb_build_object('ok', true, 'action', 'revoke_notice');

  elsif p_action = 'convert_past' then
    d := case
      when p_date_yyyy_mm_dd is not null and length(trim(p_date_yyyy_mm_dd)) >= 10
      then trim(p_date_yyyy_mm_dd)::date
      else today
    end;
    next_status := case when d <= today then 'past' else 'current' end;

    update "HRMS_users" u
    set
      employment_status = next_status,
      date_of_leaving = d,
      updated_at = now()
    where u.id = p_target_user_id and u.company_id = actor_company;

    update "HRMS_employees" e
    set
      is_active = (next_status <> 'past'),
      date_of_leaving = d,
      updated_at = now()
    where e.user_id = p_target_user_id and e.company_id = actor_company;

    return jsonb_build_object('ok', true, 'action', 'convert_past', 'status', next_status);
  else
    raise exception 'Invalid action' using errcode = 'P0001';
  end if;
end;
$$;
