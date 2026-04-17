-- Align hrms_leave_balances with web /api/leave/balance (HRMS_leave_policies + leave year + accrual)

create or replace function hrms_leave_year_start(p_as_of date, p_reset_month int, p_reset_day int)
returns date
language plpgsql
immutable
as $$
declare
  rm int := least(greatest(coalesce(p_reset_month, 1), 1), 12);
  rd int := least(greatest(coalesce(p_reset_day, 1), 1), 31);
  y int := extract(year from p_as_of)::int;
  last_d int;
  dd int;
  cand date;
begin
  last_d := extract(day from (date_trunc('month', make_date(y, rm, 1)) + interval '1 month - 1 day'))::int;
  dd := least(rd, last_d);
  cand := make_date(y, rm, dd);
  if p_as_of >= cand then
    return cand;
  end if;
  last_d := extract(day from (date_trunc('month', make_date(y - 1, rm, 1)) + interval '1 month - 1 day'))::int;
  dd := least(rd, last_d);
  return make_date(y - 1, rm, dd);
end;
$$;

create or replace function hrms_leave_balances(
  p_company_id uuid,
  p_user_id uuid,
  p_year int default null
)
returns table (
  leave_type_id uuid,
  name text,
  code text,
  is_paid boolean,
  annual_quota numeric,
  used_days numeric,
  remaining_days numeric
)
language plpgsql
stable
security definer
as $$
declare
  v_as_of date;
  v_join date;
  pol record;
  v_year_start date;
  v_year_end_exc date;
  v_last_inc date;
  v_eligible_start date;
  v_entitled numeric;
  v_used numeric;
  v_remaining numeric;
  m int;
  rate numeric;
begin
  if p_year is not null then
    v_as_of := make_date(p_year, 12, 31);
  else
    v_as_of := (current_timestamp at time zone 'UTC')::date;
  end if;

  select u.date_of_joining::date into v_join
  from "HRMS_users" u
  where u.id = p_user_id;

  for pol in
    select
      p.accrual_method,
      p.monthly_accrual_rate,
      p.annual_quota as pol_annual_quota,
      p.reset_month,
      p.reset_day,
      t.id as lt_id,
      t.name as lt_name,
      t.code as lt_code,
      t.is_paid as lt_is_paid
    from "HRMS_leave_policies" p
    inner join "HRMS_leave_types" t on t.id = p.leave_type_id
    where p.company_id = p_company_id
    order by t.is_paid desc, t.name asc
  loop
    v_year_start := hrms_leave_year_start(v_as_of, pol.reset_month, pol.reset_day);
    v_year_end_exc := (v_year_start + interval '1 year')::date;
    v_last_inc := v_year_end_exc - 1;

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
      if m < 0 then
        m := 0;
      end if;
      v_entitled := m * rate;
      if pol.pol_annual_quota is not null then
        v_entitled := least(v_entitled, pol.pol_annual_quota);
      end if;
      if v_entitled < 0 then
        v_entitled := 0;
      end if;
    else
      -- annual (and any other enum value treated as annual grant)
      if pol.pol_annual_quota is null then
        v_entitled := 0;
      else
        v_entitled := greatest(0, pol.pol_annual_quota);
      end if;
    end if;

    select coalesce(sum(
      case
        when least(r.end_date, v_last_inc) < greatest(r.start_date, v_year_start) then 0
        else (least(r.end_date, v_last_inc) - greatest(r.start_date, v_year_start)) + 1
      end
    ), 0)::numeric into v_used
    from "HRMS_leave_requests" r
    where r.company_id = p_company_id
      and r.employee_user_id = p_user_id
      and r.status = 'approved'
      and r.leave_type_id = pol.lt_id;

    if v_entitled is null then
      v_remaining := null;
    else
      v_remaining := greatest(0, v_entitled - v_used);
    end if;

    leave_type_id := pol.lt_id;
    name := pol.lt_name;
    code := pol.lt_code;
    is_paid := pol.lt_is_paid;
    annual_quota := v_entitled;
    used_days := v_used;
    remaining_days := v_remaining;
    return next;
  end loop;

  return;
end;
$$;
