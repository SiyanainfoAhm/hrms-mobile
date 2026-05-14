-- Mobile payroll (managerial): list payroll masters and month snapshot (period + payslips)
-- for native UI. Mirrors hrms-web /api/payroll/master GET shape and payslip payload used by
-- hrms_payslips_me / buildPayslipHtml. Web app does not call these RPCs.

-- ---------------------------------------------------------------------------
-- PAYROLL MASTER (list, current effective rows only)
-- ---------------------------------------------------------------------------
create or replace function hrms_payroll_master_list(p_actor_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
  v_masters jsonb;
begin
  select u.company_id, u.role::text
  into v_company, v_role
  from "HRMS_users" u
  where u.id = p_actor_user_id;

  if v_company is null then
    return jsonb_build_object('masters', '[]'::jsonb);
  end if;

  if v_role is null or v_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(obj order by (obj->>'employeeName') nulls last), '[]'::jsonb)
  into v_masters
  from (
    select jsonb_build_object(
      'employeeUserId', m.employee_user_id,
      'employeeName', u.name,
      'employeeEmail', coalesce(u.email, ''),
      'governmentPayLevel', u.government_pay_level,
      'bankName', coalesce(u.bank_name, ''),
      'bankAccountHolderName', coalesce(u.bank_account_holder_name, ''),
      'bankAccountNumber', coalesce(u.bank_account_number, ''),
      'bankIfsc', coalesce(u.bank_ifsc, ''),
      'master', (
        to_jsonb(m)
        - 'company_id'
        - 'created_at'
        - 'updated_at'
      )
    ) as obj
    from "HRMS_payroll_master" m
    join "HRMS_users" u on u.id = m.employee_user_id
    where m.company_id = v_company
      and m.effective_end_date is null
      and coalesce(u.role::text, '') <> 'super_admin'
  ) s;

  return jsonb_build_object('masters', v_masters);
end;
$$;

-- ---------------------------------------------------------------------------
-- PAYROLL MONTH SNAPSHOT: period row (if run) + payslips + company + config
-- (same slip shape as hrms_payslips_me for HTML preview)
-- ---------------------------------------------------------------------------
create or replace function hrms_payroll_period_snapshot(
  p_actor_user_id uuid,
  p_year int,
  p_month int
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
  v_period_start date;
  v_period jsonb;
  v_slips jsonb;
  v_company_json jsonb;
  v_cfg jsonb;
begin
  if p_year < 2000 or p_year > 2100 or p_month < 1 or p_month > 12 then
    raise exception 'Invalid year or month' using errcode = '22023';
  end if;

  select u.company_id, u.role::text
  into v_company, v_role
  from "HRMS_users" u
  where u.id = p_actor_user_id;

  if v_company is null then
    return jsonb_build_object(
      'period', null,
      'payslips', '[]'::jsonb,
      'company', null,
      'privatePayrollConfig', null
    );
  end if;

  if v_role is null or v_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  v_period_start := make_date(p_year, p_month, 1);

  select to_jsonb(p)
  into v_period
  from "HRMS_payroll_periods" p
  where p.company_id = v_company
    and p.period_start = v_period_start
  limit 1;

  select jsonb_build_object(
    'name', c.name,
    'logo_url', c.logo_url,
    'address', trim(concat_ws(', ',
      nullif(trim(c.address_line1), ''),
      nullif(trim(c.address_line2), ''),
      nullif(trim(concat_ws(', ', nullif(trim(c.city), ''), nullif(trim(c.state), ''), nullif(trim(c.postal_code), ''))), ''),
      nullif(trim(c.country), '')
    ))
  )
  into v_company_json
  from "HRMS_companies" c
  where c.id = v_company;

  select to_jsonb(cfg.private_config)
  into v_cfg
  from "HRMS_company_payroll_config" cfg
  where cfg.company_id = v_company
  limit 1;

  if v_period is null then
    v_slips := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(row_obj order by row_obj #>> '{user,name}' nulls last), '[]'::jsonb)
    into v_slips
    from (
      select
        to_jsonb(ps)
        || jsonb_build_object(
          'employee_email', u.email,
          'period_name', pp.period_name,
          'period_start', pp.period_start,
          'period_end', pp.period_end,
          'government_monthly', (
            select to_jsonb(g)
            from "HRMS_government_monthly_payroll" g
            where g.payslip_id = ps.id
            limit 1
          ),
          'user', jsonb_build_object(
            'name', u.name,
            'employee_code', u.employee_code,
            'designation', u.designation,
            'date_of_joining', u.date_of_joining,
            'aadhaar', u.aadhaar,
            'pan', u.pan,
            'uan_number', u.uan_number,
            'pf_number', u.pf_number,
            'esic_number', u.esic_number,
            'government_pay_level', u.government_pay_level,
            'department_name', coalesce(
              (select d.name from "HRMS_departments" d where d.id = u.department_id limit 1),
              ''
            )
          )
        ) as row_obj
      from "HRMS_payslips" ps
      join "HRMS_payroll_periods" pp on pp.id = ps.payroll_period_id
      join "HRMS_users" u on u.id = ps.employee_user_id
      where ps.company_id = v_company
        and ps.payroll_period_id = (v_period->>'id')::uuid
    ) q;
  end if;

  return jsonb_build_object(
    'period', v_period,
    'payslips', coalesce(v_slips, '[]'::jsonb),
    'company', v_company_json,
    'privatePayrollConfig', v_cfg
  );
end;
$$;

grant execute on function hrms_payroll_master_list(uuid) to anon, authenticated;
grant execute on function hrms_payroll_period_snapshot(uuid, int, int) to anon, authenticated;
