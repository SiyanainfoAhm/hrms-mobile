-- Leave balances for dashboard (quota/used/remaining)

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
language sql
stable
security definer
as $$
  with y as (
    select coalesce(p_year, extract(year from now())::int) as yr
  ),
  rng as (
    select make_date(y.yr, 1, 1) as d1, make_date(y.yr, 12, 31) as d2 from y
  ),
  used as (
    select r.leave_type_id,
           coalesce(sum(r.total_days), 0)::numeric as used_days
    from "HRMS_leave_requests" r
    cross join rng
    where r.company_id = p_company_id
      and r.employee_user_id = p_user_id
      and r.status = 'approved'
      and r.start_date >= rng.d1
      and r.start_date <= rng.d2
    group by r.leave_type_id
  )
  select t.id as leave_type_id,
         t.name,
         t.code,
         t.is_paid,
         t.annual_quota,
         coalesce(u.used_days, 0)::numeric as used_days,
         case
           when t.annual_quota is null then null
           else greatest(t.annual_quota - coalesce(u.used_days, 0), 0)
         end as remaining_days
  from "HRMS_leave_types" t
  left join used u on u.leave_type_id = t.id
  where t.company_id = p_company_id
  order by t.is_paid desc, t.name asc;
$$;

