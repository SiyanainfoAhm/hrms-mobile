-- Leave + Reimbursements RPC functions

create extension if not exists pgcrypto;

-- LEAVE TYPES (list)
create or replace function hrms_leave_types_list(p_company_id uuid)
returns table (
  id uuid,
  name text,
  code text,
  is_paid boolean,
  annual_quota numeric
)
language sql
stable
security definer
as $$
  select t.id, t.name, t.code, t.is_paid, t.annual_quota
  from "HRMS_leave_types" t
  where t.company_id = p_company_id
  order by t.name asc;
$$;

-- LEAVE REQUESTS (list)
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

-- LEAVE REQUESTS (create)
create or replace function hrms_leave_request_create(
  p_company_id uuid,
  p_user_id uuid,
  p_leave_type_id uuid,
  p_start_date date,
  p_end_date date,
  p_total_days numeric,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  new_id uuid;
  emp_id uuid;
begin
  if p_company_id is null then raise exception 'company_id is required' using errcode='22023'; end if;
  if p_user_id is null then raise exception 'user_id is required' using errcode='22023'; end if;
  if p_leave_type_id is null then raise exception 'leave_type_id is required' using errcode='22023'; end if;
  if p_start_date is null or p_end_date is null then raise exception 'start/end date required' using errcode='22023'; end if;
  if p_end_date < p_start_date then raise exception 'end_date must be >= start_date' using errcode='22023'; end if;
  if p_total_days is null or p_total_days <= 0 then raise exception 'total_days must be > 0' using errcode='22023'; end if;

  select e.id into emp_id
  from "HRMS_employees" e
  where e.user_id = p_user_id and e.company_id = p_company_id
  limit 1;

  insert into "HRMS_leave_requests"(
    company_id, employee_id, employee_user_id, leave_type_id,
    start_date, end_date, total_days, reason, status,
    created_at, updated_at
  )
  values (
    p_company_id, emp_id, p_user_id, p_leave_type_id,
    p_start_date, p_end_date, p_total_days, nullif(trim(p_reason),''), 'pending',
    now(), now()
  )
  returning id into new_id;

  return new_id;
end;
$$;

-- LEAVE REQUESTS (cancel by employee)
create or replace function hrms_leave_request_cancel(
  p_company_id uuid,
  p_user_id uuid,
  p_request_id uuid
)
returns boolean
language plpgsql
security definer
as $$
begin
  update "HRMS_leave_requests" r
  set status = 'cancelled',
      updated_at = now()
  where r.company_id = p_company_id
    and r.id = p_request_id
    and r.employee_user_id = p_user_id
    and r.status = 'pending';
  return found;
end;
$$;

-- LEAVE REQUESTS (approve/reject by approver user)
create or replace function hrms_leave_request_decide(
  p_company_id uuid,
  p_approver_user_id uuid,
  p_request_id uuid,
  p_decision text, -- 'approved' | 'rejected'
  p_rejection_reason text default null
)
returns boolean
language plpgsql
security definer
as $$
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'invalid decision' using errcode='22023';
  end if;

  update "HRMS_leave_requests" r
  set status = p_decision::HRMS_leave_status,
      approver_user_id = p_approver_user_id,
      approved_at = case when p_decision='approved' then now() else null end,
      rejected_at = case when p_decision='rejected' then now() else null end,
      rejection_reason = case when p_decision='rejected' then nullif(trim(p_rejection_reason),'') else null end,
      updated_at = now()
  where r.company_id = p_company_id
    and r.id = p_request_id
    and r.status = 'pending';
  return found;
end;
$$;

-- REIMBURSEMENTS (list)
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
         r.created_at
  from "HRMS_reimbursements" r
  join "HRMS_users" u on u.id = r.employee_user_id
  where r.company_id = p_company_id
    and (
      case when p_scope = 'all' then true else r.employee_user_id = p_user_id end
    )
  order by r.created_at desc;
$$;

-- REIMBURSEMENTS (create)
create or replace function hrms_reimbursement_create(
  p_company_id uuid,
  p_user_id uuid,
  p_category text,
  p_amount numeric,
  p_claim_date date,
  p_description text default null,
  p_attachment_url text default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  new_id uuid;
  emp_id uuid;
begin
  if p_company_id is null then raise exception 'company_id is required' using errcode='22023'; end if;
  if p_user_id is null then raise exception 'user_id is required' using errcode='22023'; end if;
  if coalesce(trim(p_category),'') = '' then raise exception 'category is required' using errcode='22023'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'amount must be > 0' using errcode='22023'; end if;
  if p_claim_date is null then raise exception 'claim_date is required' using errcode='22023'; end if;

  select e.id into emp_id
  from "HRMS_employees" e
  where e.user_id = p_user_id and e.company_id = p_company_id
  limit 1;

  insert into "HRMS_reimbursements"(
    company_id, employee_id, employee_user_id,
    category, amount, claim_date, description, attachment_url,
    status, created_at, updated_at
  )
  values (
    p_company_id, emp_id, p_user_id,
    trim(p_category), p_amount, p_claim_date, nullif(trim(p_description),''), nullif(trim(p_attachment_url),''),
    'pending', now(), now()
  )
  returning id into new_id;

  return new_id;
end;
$$;

-- REIMBURSEMENTS (approve/reject/paid)
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
begin
  if p_status not in ('approved','rejected','paid') then
    raise exception 'invalid status' using errcode='22023';
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

