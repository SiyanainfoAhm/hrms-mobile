-- Web parity for mobile Supabase RPCs: leave (actor, auto-approve, paid/unpaid),
-- reimbursements (actor, auto-approve when filing for another employee, required
-- attachment/description, payroll month/year), reimbursement decisions (status guards),
-- leave list columns, payslips_me (latest-period selection + allowances + gov row).
--
-- PostgreSQL cannot CREATE OR REPLACE when the OUT row type of RETURNS TABLE changes
-- (or overloads would collide). Drop affected signatures first. The hrms-web app does
-- not call these RPCs (it uses /api/* + direct table access); only mobile / agents rely
-- on them.

drop function if exists hrms_leave_requests_list(uuid, uuid, text);
drop function if exists hrms_reimbursements_list(uuid, uuid, text);
-- Safer if a DB still has the pre–web-parity 7-arg create; 8-arg version replaces in one step.
drop function if exists hrms_leave_request_create(uuid, uuid, uuid, date, date, numeric, text);
drop function if exists hrms_reimbursement_create(uuid, uuid, text, numeric, date, text, text);

-- ---------------------------------------------------------------------------
-- LEAVE REQUESTS (list): paid / unpaid days for UI
-- ---------------------------------------------------------------------------
create or replace function hrms_leave_requests_list(
  p_company_id uuid,
  p_user_id uuid,
  p_scope text -- 'me' | 'all'
)
returns table (
  id uuid,
  employee_user_id uuid,
  employee_name text,
  leave_type_id uuid,
  leave_type_name text,
  start_date date,
  end_date date,
  total_days numeric,
  paid_days numeric,
  unpaid_days numeric,
  reason text,
  status text,
  approved_at timestamptz,
  rejected_at timestamptz,
  rejection_reason text,
  created_at timestamptz
)
language sql
stable
security definer
as $$
  select r.id,
         r.employee_user_id,
         u.name as employee_name,
         r.leave_type_id,
         t.name as leave_type_name,
         r.start_date,
         r.end_date,
         r.total_days,
         coalesce(r.paid_days, r.total_days, 0)::numeric as paid_days,
         coalesce(r.unpaid_days, 0)::numeric as unpaid_days,
         r.reason,
         r.status::text,
         r.approved_at,
         r.rejected_at,
         r.rejection_reason,
         r.created_at
  from "HRMS_leave_requests" r
  join "HRMS_users" u on u.id = r.employee_user_id
  join "HRMS_leave_types" t on t.id = r.leave_type_id
  where r.company_id = p_company_id
    and (
      case when p_scope = 'all' then true else r.employee_user_id = p_user_id end
    )
  order by r.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- LEAVE REQUESTS (create): actor vs target, approver auto-approve, paid/unpaid
-- ---------------------------------------------------------------------------
create or replace function hrms_leave_request_create(
  p_company_id uuid,
  p_user_id uuid,
  p_leave_type_id uuid,
  p_start_date date,
  p_end_date date,
  p_total_days numeric,
  p_reason text default null,
  p_actor_user_id uuid default null
)
returns uuid
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
  v_span numeric;
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
  if p_total_days is null or p_total_days <= 0 then raise exception 'total_days must be > 0' using errcode='22023'; end if;

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

  v_span := (p_end_date - p_start_date + 1)::numeric;
  if lt.code_u = 'HL' then
    v_total := v_span * 0.5;
  else
    v_total := p_total_days::numeric;
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

-- ---------------------------------------------------------------------------
-- REIMBURSEMENTS (list): payroll period columns (coalesce from claim_date)
-- ---------------------------------------------------------------------------
create or replace function hrms_reimbursements_list(
  p_company_id uuid,
  p_user_id uuid,
  p_scope text -- 'me' | 'all'
)
returns table (
  id uuid,
  employee_user_id uuid,
  employee_name text,
  category text,
  amount numeric,
  currency text,
  claim_date date,
  description text,
  attachment_url text,
  status text,
  rejection_reason text,
  payroll_year int,
  payroll_month int,
  created_at timestamptz
)
language sql
stable
security definer
as $$
  select r.id,
         r.employee_user_id,
         u.name as employee_name,
         r.category,
         r.amount,
         r.currency::text,
         r.claim_date,
         r.description,
         r.attachment_url,
         r.status::text,
         r.rejection_reason,
         coalesce(r.payroll_year, extract(year from r.claim_date)::int) as payroll_year,
         coalesce(r.payroll_month, extract(month from r.claim_date)::int) as payroll_month,
         r.created_at
  from "HRMS_reimbursements" r
  join "HRMS_users" u on u.id = r.employee_user_id
  where r.company_id = p_company_id
    and (
      case when p_scope = 'all' then true else r.employee_user_id = p_user_id end
    )
  order by r.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- REIMBURSEMENTS (create): actor, validation, auto-approve when filing for other
-- ---------------------------------------------------------------------------
create or replace function hrms_reimbursement_create(
  p_company_id uuid,
  p_user_id uuid,
  p_category text,
  p_amount numeric,
  p_claim_date date,
  p_description text default null,
  p_attachment_url text default null,
  p_actor_user_id uuid default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  new_id uuid;
  emp_id uuid;
  v_actor uuid := coalesce(p_actor_user_id, p_user_id);
  v_role text;
  v_actor_company uuid;
  v_target_company uuid;
  v_is_approver boolean;
  v_auto boolean;
  v_amt numeric;
  v_py int;
  v_pm int;
  now_ts timestamptz := now();
begin
  if p_company_id is null then raise exception 'company_id is required' using errcode='22023'; end if;
  if p_user_id is null then raise exception 'user_id is required' using errcode='22023'; end if;
  if coalesce(trim(p_category),'') = '' then raise exception 'category is required' using errcode='22023'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'amount must be > 0' using errcode='22023'; end if;
  if p_claim_date is null then raise exception 'claim_date is required' using errcode='22023'; end if;
  if coalesce(trim(p_description),'') = '' then raise exception 'description is required' using errcode='22023'; end if;
  if coalesce(trim(p_attachment_url),'') = '' then raise exception 'attachment is required' using errcode='22023'; end if;

  select u.role, u.company_id into v_role, v_actor_company
  from "HRMS_users" u where u.id = v_actor limit 1;
  if v_actor_company is null or v_actor_company <> p_company_id then
    raise exception 'Actor not in company' using errcode='22023';
  end if;

  select u.company_id into v_target_company from "HRMS_users" u where u.id = p_user_id limit 1;
  if v_target_company is null or v_target_company <> p_company_id then
    raise exception 'Employee not in company' using errcode='22023';
  end if;

  v_is_approver := coalesce(v_role,'') in ('super_admin','admin','hr');
  if not v_is_approver and p_user_id <> v_actor then
    raise exception 'You can only submit reimbursements for yourself' using errcode='22023';
  end if;

  v_auto := v_is_approver and p_user_id <> v_actor;

  select e.id into emp_id
  from "HRMS_employees" e
  where e.user_id = p_user_id and e.company_id = p_company_id
  limit 1;
  if emp_id is null then
    raise exception 'No employee profile for selected user' using errcode='22023';
  end if;

  v_amt := round(p_amount::numeric, 2);
  v_py := extract(year from p_claim_date)::int;
  v_pm := extract(month from p_claim_date)::int;

  insert into "HRMS_reimbursements"(
    company_id, employee_id, employee_user_id,
    category, amount, currency, claim_date, description, attachment_url,
    status, approver_user_id, approved_at, rejected_at, rejection_reason,
    payroll_year, payroll_month, created_at, updated_at
  )
  values (
    p_company_id, emp_id, p_user_id,
    trim(p_category), v_amt, 'INR', p_claim_date,
    trim(p_description), trim(p_attachment_url),
    case when v_auto then 'approved'::HRMS_reimbursement_status else 'pending'::HRMS_reimbursement_status end,
    case when v_auto then v_actor else null end,
    case when v_auto then now_ts else null end,
    null, null,
    v_py, v_pm, now_ts, case when v_auto then now_ts else now_ts end
  )
  returning id into new_id;

  return new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- REIMBURSEMENTS (decide): only from valid prior statuses (web parity)
-- ---------------------------------------------------------------------------
create or replace function hrms_reimbursement_decide(
  p_company_id uuid,
  p_approver_user_id uuid,
  p_reimbursement_id uuid,
  p_status text, -- 'approved'|'rejected'|'paid'
  p_rejection_reason text default null
)
returns boolean
language plpgsql
security definer
as $$
declare
  cur text;
begin
  if p_status not in ('approved','rejected','paid') then
    raise exception 'invalid status' using errcode='22023';
  end if;

  select r.status::text into cur
  from "HRMS_reimbursements" r
  where r.company_id = p_company_id and r.id = p_reimbursement_id
  limit 1;
  if cur is null then
    return false;
  end if;

  if p_status in ('approved','rejected') and cur <> 'pending' then
    return false;
  end if;
  if p_status = 'paid' and cur <> 'approved' then
    return false;
  end if;

  update "HRMS_reimbursements" r
  set status = p_status::HRMS_reimbursement_status,
      approver_user_id = p_approver_user_id,
      approved_at = case when p_status='approved' then now() else r.approved_at end,
      rejected_at = case when p_status='rejected' then now() else null end,
      paid_at = case when p_status='paid' then now() else null end,
      rejection_reason = case when p_status='rejected' then nullif(trim(p_rejection_reason),'') else null end,
      updated_at = now()
  where r.company_id = p_company_id
    and r.id = p_reimbursement_id;
  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- PAYSLIPS (me): optional period filter; allowances; gov row; latest ordering;
-- private payroll config blob; user department name
-- ---------------------------------------------------------------------------
create or replace function hrms_payslips_me(
  p_user_id uuid,
  p_company_id uuid default null,
  p_year int default null,
  p_month int default null
)
returns jsonb
language sql
stable
security definer
as $$
  with me as (
    select u.id,
           u.company_id as user_company_id,
           coalesce(p_company_id, u.company_id) as company_id,
           u.department_id
    from "HRMS_users" u
    where u.id = p_user_id
    limit 1
  ),
  ok as (
    select 1 as ok
    from me
    where p_company_id is null or me.user_company_id = p_company_id
  ),
  company as (
    select c.name,
           c.logo_url,
           trim(concat_ws(', ',
             nullif(trim(c.address_line1),''),
             nullif(trim(c.address_line2),''),
             nullif(trim(concat_ws(', ', nullif(trim(c.city),''), nullif(trim(c.state),''), nullif(trim(c.postal_code),''))), ''),
             nullif(trim(c.country),'')
           )) as address
    from "HRMS_companies" c
    join me on me.company_id = c.id
    join ok on true
  ),
  dept as (
    select d.name as department_name
    from "HRMS_departments" d
    join me on me.department_id = d.id
    limit 1
  ),
  userx as (
    select u.name,
           u.employee_code,
           u.designation,
           u.date_of_joining,
           u.aadhaar,
           u.pan,
           u.uan_number,
           u.pf_number,
           u.esic_number,
           u.government_pay_level,
           coalesce((select department_name from dept), '') as department_name
    from "HRMS_users" u
    where u.id = p_user_id
    limit 1
  ),
  cfg as (
    select c.private_config
    from "HRMS_company_payroll_config" c
    join me on me.company_id = c.company_id
    limit 1
  ),
  ym as (
    select p_year as yr, p_month as mo
  ),
  slips as (
    select ps.id,
           ps.payroll_period_id,
           ps.generated_at,
           ps.net_pay,
           ps.gross_pay,
           ps.pay_days,
           ps.basic,
           ps.hra,
           ps.allowances,
           ps.medical,
           ps.trans,
           ps.lta,
           ps.personal,
           ps.deductions,
           ps.currency,
           ps.payslip_number,
           ps.bank_name,
           ps.bank_account_number,
           ps.bank_ifsc,
           ps.pf_employee,
           ps.esic_employee,
           ps.professional_tax,
           ps.incentive,
           ps.pr_bonus,
           ps.reimbursement,
           ps.tds,
           coalesce(ps.payroll_mode::text, 'private') as payroll_mode,
           pp.period_start,
           pp.period_end,
           pp.period_name,
           (select to_jsonb(g) from "HRMS_government_monthly_payroll" g where g.payslip_id = ps.id limit 1) as government_monthly
    from me
    join "HRMS_payslips" ps on ps.employee_user_id = me.id and ps.company_id = me.company_id
    left join "HRMS_payroll_periods" pp on pp.id = ps.payroll_period_id
    cross join ym
    where (
      (ym.yr is null or ym.mo is null)
      or (pp.period_start is not null and extract(year from pp.period_start)::int = ym.yr and extract(month from pp.period_start)::int = ym.mo)
      or (pp.period_start is null and extract(year from ps.generated_at)::int = ym.yr and extract(month from ps.generated_at)::int = ym.mo)
    )
    order by ps.generated_at desc
  )
  select jsonb_build_object(
    'company', (select to_jsonb(company) from company),
    'user', (select to_jsonb(userx) from userx),
    'privatePayrollConfig', (select cfg.private_config from cfg),
    'payslips', coalesce((select jsonb_agg(to_jsonb(slips)) from slips), '[]'::jsonb)
  );
$$;
