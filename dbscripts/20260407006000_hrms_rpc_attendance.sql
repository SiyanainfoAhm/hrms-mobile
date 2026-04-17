-- Attendance RPC functions (web-like punch + breaks)

create extension if not exists pgcrypto;

create or replace function hrms_attendance_get(p_user_id uuid)
returns table (
  has_employee boolean,
  work_date date,
  log jsonb
)
language plpgsql
stable
security definer
as $$
declare
  emp_id uuid;
  row_log record;
begin
  work_date := current_date;

  select e.id into emp_id
  from "HRMS_employees" e
  where e.user_id = p_user_id
  limit 1;

  if emp_id is null then
    has_employee := false;
    log := null;
    return next;
    return;
  end if;

  has_employee := true;

  select *
    into row_log
  from "HRMS_attendance_logs" a
  where a.employee_id = emp_id
    and a.work_date = current_date
  limit 1;

  if row_log is null then
    log := null;
    return next;
    return;
  end if;

  log := to_jsonb(row_log);
  return next;
end;
$$;

create or replace function hrms_attendance_punch(
  p_user_id uuid,
  p_action text,
  p_allow_repunch_out boolean default false,
  p_allow_repunch_in boolean default false
)
returns jsonb
language plpgsql
security definer
as $$
declare
  emp record;
  existing record;
  now_ts timestamptz := now();
  total_hours numeric(6,2);
  lunch_min int;
  tea_min int;
begin
  select e.id as employee_id, e.company_id as company_id
    into emp
  from "HRMS_employees" e
  where e.user_id = p_user_id
  limit 1;

  if emp is null then
    raise exception 'Employee record not found' using errcode = '22023';
  end if;

  select * into existing
  from "HRMS_attendance_logs" a
  where a.employee_id = emp.employee_id and a.work_date = current_date
  limit 1;

  if p_action = 'in' then
    if existing is null then
      insert into "HRMS_attendance_logs"(company_id, employee_id, work_date, check_in_at, status, created_at, updated_at)
      values (emp.company_id, emp.employee_id, current_date, now_ts, 'present', now_ts, now_ts)
      returning * into existing;
    else
      if existing.check_in_at is null then
        update "HRMS_attendance_logs"
        set check_in_at = now_ts,
            check_out_at = null,
            total_hours = null,
            status = 'present',
            updated_at = now_ts
        where id = existing.id
        returning * into existing;
      elsif existing.check_out_at is not null and p_allow_repunch_in then
        update "HRMS_attendance_logs"
        set check_in_at = now_ts,
            check_out_at = null,
            total_hours = null,
            status = 'present',
            updated_at = now_ts
        where id = existing.id
        returning * into existing;
      end if;
    end if;

    return to_jsonb(existing);
  end if;

  if p_action = 'out' then
    if existing is null or existing.check_in_at is null then
      raise exception 'Not punched in' using errcode = '22023';
    end if;
    if existing.check_out_at is not null and not p_allow_repunch_out then
      return to_jsonb(existing);
    end if;

    lunch_min := coalesce(existing.lunch_break_minutes, 0);
    tea_min := coalesce(existing.tea_break_minutes, 0);

    total_hours :=
      round(
        greatest(0, extract(epoch from (now_ts - existing.check_in_at)) - ((lunch_min + tea_min) * 60)) / 3600.0
      , 2);

    update "HRMS_attendance_logs"
    set check_out_at = now_ts,
        total_hours = total_hours,
        updated_at = now_ts
    where id = existing.id
    returning * into existing;

    return to_jsonb(existing);
  end if;

  raise exception 'Invalid action' using errcode = '22023';
end;
$$;

create or replace function hrms_attendance_break_toggle(
  p_user_id uuid,
  p_kind text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  emp_id uuid;
  a record;
  now_ts timestamptz := now();
  started timestamptz;
  minutes_add int;
begin
  select e.id into emp_id
  from "HRMS_employees" e
  where e.user_id = p_user_id
  limit 1;

  if emp_id is null then
    raise exception 'Employee record not found' using errcode = '22023';
  end if;

  select * into a
  from "HRMS_attendance_logs" x
  where x.employee_id = emp_id and x.work_date = current_date
  limit 1;

  if a is null or a.check_in_at is null then
    raise exception 'Not punched in' using errcode = '22023';
  end if;
  if a.check_out_at is not null then
    raise exception 'Already punched out' using errcode = '22023';
  end if;

  if p_kind = 'lunch' then
    started := a.lunch_break_started_at;
    if started is null then
      update "HRMS_attendance_logs"
      set lunch_break_started_at = now_ts,
          lunch_check_out_at = coalesce(lunch_check_out_at, now_ts),
          updated_at = now_ts
      where id = a.id
      returning * into a;
      return to_jsonb(a);
    end if;

    minutes_add := greatest(0, floor(extract(epoch from (now_ts - started)) / 60.0))::int;
    update "HRMS_attendance_logs"
    set lunch_break_minutes = coalesce(lunch_break_minutes,0) + minutes_add,
        lunch_break_started_at = null,
        lunch_check_in_at = coalesce(lunch_check_in_at, now_ts),
        updated_at = now_ts
    where id = a.id
    returning * into a;
    return to_jsonb(a);
  end if;

  if p_kind = 'tea' then
    started := a.tea_break_started_at;
    if started is null then
      update "HRMS_attendance_logs"
      set tea_break_started_at = now_ts,
          updated_at = now_ts
      where id = a.id
      returning * into a;
      return to_jsonb(a);
    end if;

    minutes_add := greatest(0, floor(extract(epoch from (now_ts - started)) / 60.0))::int;
    update "HRMS_attendance_logs"
    set tea_break_minutes = coalesce(tea_break_minutes,0) + minutes_add,
        tea_break_started_at = null,
        updated_at = now_ts
    where id = a.id
    returning * into a;
    return to_jsonb(a);
  end if;

  raise exception 'Invalid kind' using errcode = '22023';
end;
$$;

