-- Extend payroll master list with company payroll context; add managerial save RPCs
-- for private payroll master + bank details (mirrors hrms-web `/api/payroll/master` PATCH).

-- ---------------------------------------------------------------------------
-- LIST + company private config / PT default / government flag
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
  v_cfg jsonb;
  v_pt numeric;
  v_gov_ok boolean := false;
begin
  select u.company_id, u.role::text
  into v_company, v_role
  from "HRMS_users" u
  where u.id = p_actor_user_id;

  if v_company is null then
    return jsonb_build_object(
      'masters', '[]'::jsonb,
      'privatePayrollConfig', null,
      'companyProfessionalTaxMonthly', 200,
      'companyAllowsGovernmentPayroll', false
    );
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

  select to_jsonb(cfg.private_config)
  into v_cfg
  from "HRMS_company_payroll_config" cfg
  where cfg.company_id = v_company
  limit 1;

  select coalesce(c.professional_tax_monthly, 200)::numeric
  into v_pt
  from "HRMS_companies" c
  where c.id = v_company;

  return jsonb_build_object(
    'masters', v_masters,
    'privatePayrollConfig', v_cfg,
    'companyProfessionalTaxMonthly', v_pt,
    'companyAllowsGovernmentPayroll', coalesce(v_gov_ok, false)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- BANK ONLY (same semantics as web updateBankOnly)
-- ---------------------------------------------------------------------------
create or replace function hrms_payroll_master_save_bank(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_bank_name text,
  p_bank_account_holder_name text,
  p_bank_account_number text,
  p_bank_ifsc text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
  v_acct text := regexp_replace(coalesce(p_bank_account_number, ''), '\s', '', 'g');
  v_ifsc text := upper(regexp_replace(coalesce(p_bank_ifsc, ''), '\s', '', 'g'));
begin
  select u.company_id, u.role::text into v_company, v_role from "HRMS_users" u where u.id = p_actor_user_id;
  if v_role is null or v_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  if v_company is null then raise exception 'No company' using errcode = '22023'; end if;
  if p_target_user_id is null then raise exception 'target user required' using errcode = '22023'; end if;
  if coalesce(trim(p_bank_account_holder_name), '') = '' then
    raise exception 'Account holder name is required' using errcode = '22023';
  end if;
  if v_acct is null or length(v_acct) < 9 or length(v_acct) > 34 then
    raise exception 'Bank account number is required (9–34 digits)' using errcode = '22023';
  end if;
  if v_ifsc is null or length(v_ifsc) <> 11 then
    raise exception 'IFSC must be 11 characters' using errcode = '22023';
  end if;

  if not exists (
    select 1 from "HRMS_users" t
    where t.id = p_target_user_id and t.company_id = v_company and t.employment_status::text = 'current'
  ) then
    raise exception 'Invalid employee' using errcode = '22023';
  end if;

  update "HRMS_users" u
  set bank_name = nullif(trim(p_bank_name), ''),
      bank_account_holder_name = nullif(trim(p_bank_account_holder_name), ''),
      bank_account_number = nullif(v_acct, ''),
      bank_ifsc = nullif(v_ifsc, ''),
      updated_at = now()
  where u.id = p_target_user_id and u.company_id = v_company;

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- PRIVATE master new revision (client-computed statutory fields; server validates dates)
-- ---------------------------------------------------------------------------
create or replace function hrms_payroll_master_save_private(
  p_actor_user_id uuid,
  p_target_user_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
  v_old_id uuid;
  v_old_start date;
  pe date;
  ps date;
  v_reason text;
  gs numeric;
begin
  select u.company_id, u.role::text into v_company, v_role from "HRMS_users" u where u.id = p_actor_user_id;
  if v_role is null or v_role not in ('super_admin', 'admin', 'hr') then
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  if v_company is null then raise exception 'No company' using errcode = '22023'; end if;

  if not exists (
    select 1 from "HRMS_users" t
    where t.id = p_target_user_id and t.company_id = v_company and t.employment_status::text = 'current'
  ) then
    raise exception 'Invalid employee' using errcode = '22023';
  end if;

  v_reason := nullif(trim(p_payload->>'reason_for_change'), '');
  if v_reason is null then
    raise exception 'reason_for_change is required' using errcode = '22023';
  end if;

  pe := (p_payload->>'previous_effective_end_date')::date;
  ps := (p_payload->>'effective_start_date')::date;
  if ps is null then raise exception 'effective_start_date is required' using errcode = '22023'; end if;
  if pe is null then raise exception 'previous_effective_end_date is required' using errcode = '22023'; end if;
  if pe >= ps then
    raise exception 'Previous effective end must be strictly before new effective start' using errcode = '22023';
  end if;

  gs := coalesce((p_payload->>'gross_salary')::numeric, 0);
  if gs <= 0 then raise exception 'gross_salary must be positive' using errcode = '22023'; end if;

  select m.id, m.effective_start_date::date
  into v_old_id, v_old_start
  from "HRMS_payroll_master" m
  where m.company_id = v_company
    and m.employee_user_id = p_target_user_id
    and m.effective_end_date is null
  limit 1;

  if v_old_id is not null then
    if v_old_start is not null and ps <= v_old_start then
      raise exception 'New effective start must be after the current master start date' using errcode = '22023';
    end if;
    if v_old_start is not null and pe < v_old_start then
      raise exception 'Previous effective end cannot be before the current row start date' using errcode = '22023';
    end if;

    update "HRMS_payroll_master" m
    set effective_end_date = pe
    where m.id = v_old_id;
  end if;

  insert into "HRMS_payroll_master" (
    company_id,
    employee_user_id,
    payroll_mode,
    gross_salary,
    ctc,
    pf_eligible,
    esic_eligible,
    pf_employee,
    pf_employer,
    esic_employee,
    esic_employer,
    pt,
    tds,
    advance_bonus,
    take_home,
    effective_start_date,
    effective_end_date,
    reason_for_change,
    created_by,
    basic,
    hra,
    medical,
    trans,
    lta,
    personal
  ) values (
    v_company,
    p_target_user_id,
    'private',
    (p_payload->>'gross_salary')::numeric,
    (p_payload->>'ctc')::numeric,
    coalesce((p_payload->>'pf_eligible')::boolean, true),
    coalesce((p_payload->>'esic_eligible')::boolean, false),
    (p_payload->>'pf_employee')::numeric,
    (p_payload->>'pf_employer')::numeric,
    (p_payload->>'esic_employee')::numeric,
    (p_payload->>'esic_employer')::numeric,
    (p_payload->>'pt')::numeric,
    (p_payload->>'tds')::numeric,
    (p_payload->>'advance_bonus')::numeric,
    (p_payload->>'take_home')::numeric,
    ps,
    null,
    v_reason,
    p_actor_user_id,
    (p_payload->>'basic')::numeric,
    (p_payload->>'hra')::numeric,
    (p_payload->>'medical')::numeric,
    (p_payload->>'trans')::numeric,
    (p_payload->>'lta')::numeric,
    (p_payload->>'personal')::numeric
  );

  update "HRMS_users" u
  set ctc = (p_payload->>'ctc')::numeric,
      gross_salary = (p_payload->>'gross_salary')::numeric,
      pf_eligible = coalesce((p_payload->>'pf_eligible')::boolean, true),
      esic_eligible = coalesce((p_payload->>'esic_eligible')::boolean, false),
      updated_at = now()
  where u.id = p_target_user_id and u.company_id = v_company;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function hrms_payroll_master_list(uuid) to anon, authenticated;
grant execute on function hrms_payroll_master_save_bank(uuid, uuid, text, text, text, text) to anon, authenticated;
grant execute on function hrms_payroll_master_save_private(uuid, uuid, jsonb) to anon, authenticated;
