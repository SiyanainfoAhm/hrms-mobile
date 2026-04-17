-- Payslips (employee) - return company + user + full payslip rows for rendering

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
           coalesce(p_company_id, u.company_id) as company_id
    from "HRMS_users" u
    where u.id = p_user_id
    limit 1
  ),
  -- If caller passes a company_id it must match the user's company_id
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
  userx as (
    select u.name,
           u.employee_code,
           u.designation,
           u.date_of_joining,
           u.aadhaar,
           u.pan,
           u.uan_number,
           u.pf_number,
           u.esic_number
    from "HRMS_users" u
    where u.id = p_user_id
    limit 1
  ),
  ym as (
    select coalesce(p_year, extract(year from now())::int) as yr,
           coalesce(p_month, extract(month from now())::int) as mo
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
           pp.period_start,
           pp.period_end,
           pp.period_name
    from me
    join "HRMS_payslips" ps on ps.employee_user_id = me.id and ps.company_id = me.company_id
    left join "HRMS_payroll_periods" pp on pp.id = ps.payroll_period_id
    cross join ym
    where (pp.period_start is null or (extract(year from pp.period_start)::int = ym.yr and extract(month from pp.period_start)::int = ym.mo))
    order by ps.generated_at desc
  )
  select jsonb_build_object(
    'company', (select to_jsonb(company) from company),
    'user', (select to_jsonb(userx) from userx),
    'payslips', coalesce((select jsonb_agg(to_jsonb(slips)) from slips), '[]'::jsonb)
  );
$$;

