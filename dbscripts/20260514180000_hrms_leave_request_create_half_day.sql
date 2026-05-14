-- Optional half-day (0.5) for a single calendar day on non-HL types — matches web POST /api/leave/requests.
--
-- Depends on hrms_leave_working_days_count (same definition as 20260515120000...). It is included below so
-- this script is safe if you applied half-day SQL before the working-days migration.

-- ---------------------------------------------------------------------------
-- Mon–Fri in [p_start, p_end], excluding company holidays (division-aware)
-- ---------------------------------------------------------------------------
create or replace function hrms_leave_working_days_count(
  p_company_id uuid,
  p_user_id uuid,
  p_start date,
  p_end date
) returns integer
language plpgsql
stable
security definer
as $$
declare
  v_div uuid;
  d date;
  n int := 0;
  dow double precision;
  on_hol boolean;
begin
  if p_start is null or p_end is null or p_end < p_start then
    return 0;
  end if;

  select e.division_id into v_div
  from "HRMS_employees" e
  where e.company_id = p_company_id and e.user_id = p_user_id
  limit 1;

  d := p_start;
  while d <= p_end loop
    dow := extract(dow from d);
    if dow in (0::double precision, 6::double precision) then
      null;
    else
      select exists(
        select 1
        from "HRMS_holidays" h
        where h.company_id = p_company_id
          and d between h.holiday_date and coalesce(h.holiday_end_date, h.holiday_date)
          and (
            v_div is null
            or h.division_id is null
            or h.division_id = v_div
          )
      ) into on_hol;
      if not coalesce(on_hol, false) then
        n := n + 1;
      end if;
    end if;
    d := (d + interval '1 day')::date;
  end loop;
  return n;
end;
$$;

drop function if exists hrms_leave_request_create(uuid, uuid, uuid, date, date, numeric, text, uuid, boolean);
drop function if exists hrms_leave_request_create(uuid, uuid, uuid, date, date, numeric, text, uuid);

create or replace function hrms_leave_request_create(
  p_company_id uuid,
  p_user_id uuid,
  p_leave_type_id uuid,
  p_start_date date,
  p_end_date date,
  p_total_days numeric,
  p_reason text default null,
  p_actor_user_id uuid default null,
  p_is_half_day boolean default false
) returns uuid
language plpgsql
security definer
as $$
declare
  new_id uuid;
  emp_id uuid;
  v_actor uuid := coalesce(p_actor_user_id, p_user_id);
  v_actor_role text;
  v_actor_company uuid;
  v_target_company uuid;
  v_target_status text;
  v_is_approver boolean;
  v_auto boolean;
  lt record;
  pol record;
  v_working int;
  v_total numeric;
  v_ist_today date;
  v_as_of date;
  v_year_start date;
  v_year_end_exc date;
  v_last_inc date;
  v_join date;
  v_eligible_start date;
  v_entitled numeric;
  v_used numeric;
  v_rem numeric;
  v_paid numeric;
  v_unpaid numeric;
  v_has_policy boolean;
  m int;
  rate numeric;
begin
  if p_company_id is null then raise exception 'company_id is required' using errcode='22023'; end if;
  if p_user_id is null then raise exception 'user_id is required' using errcode='22023'; end if;
  if p_leave_type_id is null then raise exception 'leave_type_id is required' using errcode='22023'; end if;
  if p_start_date is null or p_end_date is null then raise exception 'start/end date required' using errcode='22023'; end if;
  if p_end_date < p_start_date then raise exception 'end_date must be >= start_date' using errcode='22023'; end if;

  select u.role, u.company_id into v_actor_role, v_actor_company
  from "HRMS_users" u
  where u.id = v_actor
  limit 1;
  if v_actor_company is null or v_actor_company <> p_company_id then
    raise exception 'Actor not in company' using errcode='22023';
  end if;

  v_is_approver := coalesce(v_actor_role, '') in ('super_admin','admin','hr');

  select u.company_id, coalesce(u.employment_status::text,'') into v_target_company, v_target_status
  from "HRMS_users" u
  where u.id = p_user_id
  limit 1;
  if v_target_company is null or v_target_company <> p_company_id then
    raise exception 'Employee not in company' using errcode='22023';
  end if;

  if not v_is_approver then
    if p_user_id <> v_actor then
      raise exception 'You can only request leave for yourself' using errcode='22023';
    end if;
  else
    if coalesce(v_target_status,'') <> 'current' then
      raise exception 'Only current employees can have leave added' using errcode='22023';
    end if;
  end if;

  select e.id into emp_id
  from "HRMS_employees" e
  where e.user_id = p_user_id and e.company_id = p_company_id
  limit 1;
  if emp_id is null then
    raise exception 'No employee profile for selected user' using errcode='22023';
  end if;

  if exists (
    select 1
    from "HRMS_leave_requests" r
    where r.company_id = p_company_id
      and r.employee_user_id = p_user_id
      and r.status in ('pending', 'approved')
      and not (r.end_date < p_start_date or r.start_date > p_end_date)
  ) then
    raise exception 'Leave already exists for overlapping dates (pending or approved).' using errcode='22023';
  end if;

  select t.id, t.is_paid, upper(trim(coalesce(t.code,''))) as code_u
    into lt
  from "HRMS_leave_types" t
  where t.id = p_leave_type_id and t.company_id = p_company_id
  limit 1;
  if lt.id is null then
    raise exception 'Invalid leave type' using errcode='22023';
  end if;

  if not lt.is_paid and not v_is_approver then
    raise exception 'You are not allowed to request unpaid leave' using errcode='22023';
  end if;

  if coalesce(p_is_half_day, false) and lt.code_u = 'HL' then
    raise exception 'Half-day checkbox does not apply to Half Leave (HL) type' using errcode='22023';
  end if;

  if coalesce(p_is_half_day, false) and p_start_date <> p_end_date then
    raise exception 'Half day is only allowed when start and end date are the same' using errcode='22023';
  end if;

  v_working := hrms_leave_working_days_count(p_company_id, p_user_id, p_start_date, p_end_date);
  if v_working <= 0 then
    raise exception 'No chargeable leave days in this range (weekends and holidays are excluded).' using errcode='22023';
  end if;

  if lt.code_u = 'HL' then
    v_total := v_working * 0.5;
  elsif coalesce(p_is_half_day, false) then
    if v_working <> 1 then
      raise exception 'Half day is only available on a single working day (not on a weekend or holiday).' using errcode='22023';
    end if;
    v_total := 0.5;
  else
    v_total := v_working::numeric;
  end if;

  v_ist_today := (current_timestamp at time zone 'Asia/Kolkata')::date;
  v_as_of := greatest(p_start_date, v_ist_today);

  select p.*
    into pol
  from "HRMS_leave_policies" p
  where p.company_id = p_company_id and p.leave_type_id = p_leave_type_id
  limit 1;
  v_has_policy := FOUND;

  if not lt.is_paid then
    v_paid := 0;
    v_unpaid := v_total;
  elsif not v_has_policy then
    v_paid := v_total;
    v_unpaid := 0;
  else
    v_year_start := hrms_leave_year_start(v_as_of, pol.reset_month, pol.reset_day);
    v_year_end_exc := (v_year_start + interval '1 year')::date;
    v_last_inc := v_year_end_exc - 1;

    select u.date_of_joining::date into v_join
    from "HRMS_users" u where u.id = p_user_id;

    if v_join is not null and v_join > v_year_start then
      v_eligible_start := v_join;
    else
      v_eligible_start := v_year_start;
    end if;

    if v_as_of < v_eligible_start then
      v_entitled := 0;
    elsif pol.accrual_method::text = 'none' then
      v_entitled := null;
    elsif pol.accrual_method::text = 'monthly' then
      rate := coalesce(pol.monthly_accrual_rate, 0);
      m := (12 * (extract(year from v_as_of)::int - extract(year from v_eligible_start)::int)
        + (extract(month from v_as_of)::int - extract(month from v_eligible_start)::int)
        + 1);
      if m < 0 then m := 0; end if;
      v_entitled := m * rate;
      if pol.annual_quota is not null then
        v_entitled := least(v_entitled, pol.annual_quota);
      end if;
      if v_entitled < 0 then v_entitled := 0; end if;
    else
      if pol.annual_quota is null then
        v_entitled := 0;
      else
        v_entitled := greatest(0, pol.annual_quota);
      end if;
    end if;

    select coalesce(sum(
      case
        when least(r.end_date, v_last_inc) < greatest(r.start_date, v_year_start) then 0::numeric
        else
          coalesce(r.total_days, (r.end_date - r.start_date + 1)::numeric)
          * (
            (least(r.end_date, v_last_inc) - greatest(r.start_date, v_year_start) + 1)::numeric
            / nullif(greatest((r.end_date - r.start_date + 1)::numeric, 1), 0)
          )
      end
    ), 0)::numeric into v_used
    from "HRMS_leave_requests" r
    where r.company_id = p_company_id
      and r.employee_user_id = p_user_id
      and r.status = 'approved'
      and r.leave_type_id = p_leave_type_id;

    if v_entitled is null then
      v_paid := v_total;
      v_unpaid := 0;
    else
      v_rem := greatest(0, v_entitled - coalesce(v_used, 0));
      v_paid := least(v_total, v_rem);
      v_unpaid := v_total - v_paid;
    end if;
  end if;

  v_auto := v_is_approver;

  insert into "HRMS_leave_requests"(
    company_id, employee_id, employee_user_id, leave_type_id,
    start_date, end_date, total_days, paid_days, unpaid_days, reason, status,
    approver_user_id, approved_at, rejected_at, rejection_reason,
    created_at, updated_at
  )
  values (
    p_company_id, emp_id, p_user_id, p_leave_type_id,
    p_start_date, p_end_date, v_total, v_paid, v_unpaid, nullif(trim(p_reason), ''),
    case when v_auto then 'approved'::HRMS_leave_status else 'pending'::HRMS_leave_status end,
    case when v_auto then v_actor else null end,
    case when v_auto then now() else null end,
    null, null,
    now(), now()
  )
  returning id into new_id;

  return new_id;
end;
$$;
