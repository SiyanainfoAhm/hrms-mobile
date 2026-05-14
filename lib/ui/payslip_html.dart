import 'formatters.dart';

num _n(dynamic v) => num.tryParse((v ?? 0).toString()) ?? 0;

/// YYYY-MM from slip `period_start` (matches web `periodMonth`).
String payslipPeriodMonthKey(Map<String, dynamic> slip) {
  final ps = (slip['period_start'] ?? '').toString();
  if (ps.length >= 7) return ps.substring(0, 7);
  return '';
}

Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return null;
}

/// Reads company payroll private_config (same keys as hrms-web `normalizePrivatePayrollConfig`).
(String mode, String effectiveYm) _payslipEarningsCfg(Map<String, dynamic>? raw) {
  if (raw == null) return ('classic', '');
  final m = raw['payslipEarningsMode']?.toString();
  final mode = m == 'basic_hra_advance_special' ? 'basic_hra_advance_special' : 'classic';
  final ym = raw['payslipEarningsEffectiveFromYm']?.toString().trim() ?? '';
  final eff = RegExp(r'^\d{4}-\d{2}$').hasMatch(ym) ? ym : '';
  return (mode, eff);
}

String _governmentPeriodTitle(String periodStart) {
  if (periodStart.length < 7) return 'PAY SLIP';
  final y = periodStart.substring(0, 4);
  final mi = int.tryParse(periodStart.substring(5, 7)) ?? 1;
  final m = mi.clamp(1, 12);
  const upper = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  return 'PAY SLIP FOR ${upper[m - 1]} $y';
}

num _gnum(Map<String, dynamic> gov, String key) => _n(gov[key]);

List<(String, num)> _govEarningPairs(Map<String, dynamic> gov) {
  return [
    ('Basic', _gnum(gov, 'basic_paid')),
    ('SP. Pay', _gnum(gov, 'sp_pay_paid')),
    ('DA', _gnum(gov, 'da_paid')),
    ('Transport', _gnum(gov, 'transport_paid')),
    ('HRA', _gnum(gov, 'hra_paid')),
    ('Medical', _gnum(gov, 'medical_paid')),
    ('Extra Work Allowance', _gnum(gov, 'extra_work_allowance_paid')),
    ('Night Allowance', _gnum(gov, 'night_allowance_paid')),
    ('Uniform Allowance', _gnum(gov, 'uniform_allowance_paid')),
    ('Education Allowance', _gnum(gov, 'education_allowance_paid')),
    ('DA Arrears', _gnum(gov, 'da_arrears_paid')),
    ('Transport Arrears', _gnum(gov, 'transport_arrears_paid')),
    ('Encashment', _gnum(gov, 'encashment_paid')),
    ('Encashment DA', _gnum(gov, 'encashment_da_paid')),
  ];
}

List<(String, num)> _govDeductionPairs(Map<String, dynamic> gov) {
  num incomeTaxOrTds = _gnum(gov, 'income_tax_amount');
  if (incomeTaxOrTds == 0) incomeTaxOrTds = _gnum(gov, 'tds');
  if (incomeTaxOrTds == 0) incomeTaxOrTds = _gnum(gov, 'tds_amount');
  num pt = _gnum(gov, 'pt_amount');
  if (pt == 0) pt = _gnum(gov, 'professional_tax');
  num cpf = _gnum(gov, 'cpf_amount');
  if (cpf == 0) cpf = _gnum(gov, 'pf_employee');
  return [
    ('TDS / Income Tax', incomeTaxOrTds),
    ('P.Tax', pt),
    ('LIC', _gnum(gov, 'lic_amount')),
    ('CPF', cpf),
    ('DA CPF', _gnum(gov, 'da_cpf_amount')),
    ('VPF', _gnum(gov, 'vpf_amount')),
    ('PF Loan', _gnum(gov, 'pf_loan_amount')),
    ('Post Office', _gnum(gov, 'post_office_amount')),
    ('Credit Society', _gnum(gov, 'credit_society_amount')),
    ('Std Licence fee', _gnum(gov, 'std_licence_fee_amount')),
    ('Electricity', _gnum(gov, 'electricity_amount')),
    ('Water', _gnum(gov, 'water_amount')),
    ('Mess', _gnum(gov, 'mess_amount')),
    ('Horticulture', _gnum(gov, 'horticulture_amount')),
    ('Welfare', _gnum(gov, 'welfare_amount')),
    ('Veh Charge', _gnum(gov, 'veh_charge_amount')),
    ('Other', _gnum(gov, 'other_deduction_amount')),
  ];
}

String _buildGovernmentPayslipHtml({
  required Map<String, dynamic> slip,
  required Map<String, dynamic> gov,
  required Map<String, dynamic>? company,
  required Map<String, dynamic>? user,
}) {
  final cellClass = 'cell';
  final thClass = 'th';
  String fmt(num x) => UiFormatters.indianNumber(x.round());

  final companyName = (company?['name'] ?? '').toString();
  final companyAddr = (company?['address'] ?? '').toString();
  final logoUrl = (company?['logo_url'] ?? '').toString().trim();

  final periodStartStr = (slip['period_start'] ?? '').toString();
  final title = _governmentPeriodTitle(periodStartStr);

  num grossBasic = _gnum(gov, 'basic_actual');
  if (grossBasic == 0) grossBasic = _gnum(gov, 'basic_paid');
  final dim = _gnum(gov, 'days_in_month');
  num paidDays = _gnum(gov, 'paid_days');
  if (paidDays == 0) paidDays = _n(slip['pay_days']);
  final periodEndStr = (slip['period_end'] ?? '').toString();
  final psDt = DateTime.tryParse(periodStartStr);
  final peDt = DateTime.tryParse(periodEndStr);
  final totalDays = (psDt != null && peDt != null)
      ? (DateTime(peDt.year, peDt.month, peDt.day).difference(DateTime(psDt.year, psDt.month, psDt.day)).inDays + 1)
      : 0;
  final unpaid = totalDays > 0 ? (totalDays - paidDays).clamp(0, 366) : 0;
  final netRounded = (_n(slip['net_pay']) != 0 ? _n(slip['net_pay']) : _gnum(gov, 'net_salary')).round();

  final left = _govEarningPairs(gov);
  final right = _govDeductionPairs(gov);
  final len = left.length > right.length ? left.length : right.length;
  final rows = StringBuffer();
  for (var i = 0; i < len; i++) {
    final L = i < left.length ? left[i] : ('', 0);
    final R = i < right.length ? right[i] : ('', 0);
    final el = L.$1;
    final ev = L.$2;
    final dl = R.$1;
    final dv = R.$2;
    rows.write('''
                <tr>
                  <td class="$cellClass">${el.isEmpty ? '' : el}</td>
                  <td class="$cellClass text-right">${el.isEmpty ? '' : fmt(ev)}</td>
                  <td class="$cellClass">${dl.isEmpty ? '' : dl}</td>
                  <td class="$cellClass text-right">${dl.isEmpty ? '' : fmt(dv)}</td>
                </tr>
''');
  }

  final empCode = (user?['employee_code'] ?? '').toString();
  final empName = (user?['name'] ?? '').toString();
  final designation = (user?['designation'] ?? '').toString();
  final dept = (user?['department_name'] ?? '').toString();
  final doj = UiFormatters.fmtDmy(user?['date_of_joining']);
  final uan = (user?['uan_number'] ?? '').toString();
  final pfNo = (user?['pf_number'] ?? '').toString();
  final bank = (slip['bank_name'] ?? '').toString();
  final acct = (slip['bank_account_number'] ?? '').toString();
  final salaryDate = UiFormatters.indianDateLong(slip['generated_at']);
  final totalEarn = _gnum(gov, 'total_earnings');
  final totalDed = _gnum(gov, 'total_deductions');

  return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<style>
  body { font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif; margin: 0; padding: 16px; background: #fff; }
  .payslip-print-area { overflow-x: auto; border: 1px solid #000; border-radius: 12px; background: #fff; padding: 20px; max-width: 190mm; margin: 0 auto; }
  table { width: 100%; border-collapse: collapse; }
  .muted { color: #64748b; }
  .text-right { text-align: right; }
  td.$cellClass, th.$thClass { border: 1px solid #000; padding: 8px 10px; font-size: 14px; vertical-align: top; }
  th.$thClass { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; background: #f1f5f9; }
  .payslip-logo-banner { display: flex; justify-content: center; margin-bottom: 8px; padding-bottom: 8px; border-bottom: 1px solid rgba(0,0,0,0.2); }
  .payslip-logo-banner img { max-height: 64px; max-width: 260px; object-fit: contain; }
</style>
</head>
<body>
  <div class="payslip-print-area">
    <table style="border:1px solid #000;">
      <tbody>
        <tr>
          <td colspan="2" style="border:1px solid #000;padding:12px;text-align:center;">
            ${logoUrl.isNotEmpty ? '<div class="payslip-logo-banner"><img src="$logoUrl" alt=""/></div>' : ''}
            ${companyAddr.isNotEmpty ? '<div style="font-size:12px;text-transform:uppercase;color:#334155;">$companyAddr</div>' : ''}
            <div style="margin-top:8px;font-size:14px;font-weight:700;">$companyName</div>
            <div style="margin-top:8px;font-size:16px;font-weight:700;letter-spacing:0.05em;">$title</div>
          </td>
        </tr>
        <tr>
          <td class="$cellClass" style="width:50%;">
            <div style="font-size:14px;line-height:1.55;">
              <div><span class="muted">Employee ID:</span> $empCode</div>
              <div><span class="muted">Employee Name:</span> $empName</div>
              <div><span class="muted">Designation:</span> $designation</div>
              <div><span class="muted">Department:</span> $dept</div>
              <div><span class="muted">Date of Joining:</span> $doj</div>
            </div>
          </td>
          <td class="$cellClass" style="width:50%;">
            <div style="font-size:14px;line-height:1.55;">
              <div><span class="muted">UAN:</span> $uan</div>
              <div><span class="muted">CPF No:</span> $pfNo</div>
              <div><span class="muted">Bank:</span> $bank</div>
              <div><span class="muted">Account No:</span> $acct</div>
            </div>
          </td>
        </tr>
        <tr>
          <td class="$cellClass" style="padding:0;">
            <table style="width:100%;border-collapse:collapse;"><tbody>
              <tr>
                <td style="border-bottom:1px solid #000;padding:8px;font-weight:600;">Gross Basic</td>
                <td style="border-bottom:1px solid #000;border-left:1px solid #000;padding:8px;text-align:right;font-weight:600;">${fmt(grossBasic)}</td>
              </tr>
            </tbody></table>
            <div style="padding:8px;font-size:14px;line-height:1.5;">
              <div><span class="muted">Salary date:</span> $salaryDate</div>
              <div><span class="muted">Total working days:</span> ${dim > 0 ? fmt(dim) : ''}</div>
              <div><span class="muted">Paid days:</span> ${fmt(paidDays)}</div>
              <div><span class="muted">Unpaid leave days:</span> ${fmt(unpaid)}</div>
            </div>
          </td>
          <td class="$cellClass">
            <div style="font-size:14px;color:#334155;line-height:1.5;">
              <div><span class="muted">Leave balance:</span> </div>
              <div><span class="muted">Casual leave:</span> </div>
              <div><span class="muted">Earned leave:</span> </div>
              <div><span class="muted">HPL:</span> </div>
              <div><span class="muted">HL:</span> </div>
            </div>
          </td>
        </tr>
        <tr>
          <td colspan="2" style="border:1px solid #000;padding:0;">
            <table style="width:100%;border-collapse:collapse;">
              <thead>
                <tr>
                  <th class="$thClass" style="width:38%;">Earnings</th>
                  <th class="$thClass text-right">Amount</th>
                  <th class="$thClass" style="width:38%;">Deductions</th>
                  <th class="$thClass text-right">Amount</th>
                </tr>
              </thead>
              <tbody>
$rows
                <tr>
                  <td class="$cellClass" style="font-weight:600;">TOTAL EARNINGS</td>
                  <td class="$cellClass text-right" style="font-weight:600;">${fmt(totalEarn)}</td>
                  <td class="$cellClass" style="font-weight:600;">TOTAL DEDUCTIONS</td>
                  <td class="$cellClass text-right" style="font-weight:600;">${fmt(totalDed)}</td>
                </tr>
                <tr>
                  <td class="$cellClass" style="font-weight:700;" colspan="3">NET SALARY</td>
                  <td class="$cellClass text-right" style="font-weight:700;">${fmt(netRounded)}</td>
                </tr>
              </tbody>
            </table>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</body>
</html>
''';
}

String _buildPrivatePayslipHtml({
  required Map<String, dynamic> slip,
  required Map<String, dynamic>? company,
  required Map<String, dynamic>? user,
  required String selectedMonth,
  required String selectedYear,
  Map<String, dynamic>? privatePayrollConfig,
}) {
  final monthIdx = (int.tryParse(selectedMonth) ?? 1).clamp(1, 12);
  final monthShort = UiFormatters.monthShort(monthIdx);
  final year = selectedYear;

  final salaryDate = UiFormatters.indianDateLong(slip['generated_at']);
  final dojFormatted = UiFormatters.indianDateShort(user?['date_of_joining']);

  final periodStart = slip['period_start'];
  final periodEnd = slip['period_end'];
  final periodStartDt = DateTime.tryParse((periodStart ?? '').toString());
  final periodEndDt = DateTime.tryParse((periodEnd ?? '').toString());
  final totalDays = (periodStartDt != null && periodEndDt != null)
      ? (DateTime(periodEndDt.year, periodEndDt.month, periodEndDt.day)
              .difference(DateTime(periodStartDt.year, periodStartDt.month, periodStartDt.day))
              .inDays +
          1)
      : 0;
  final payDays = _n(slip['pay_days']);
  final unpaidLeaves = totalDays > 0 ? (totalDays - payDays).clamp(0, 366) : 0;

  final companyName = (company?['name'] ?? 'Company').toString();
  final companyAddr = (company?['address'] ?? '').toString();
  final logoUrl = (company?['logo_url'] ?? '').toString().trim();

  final empName = (user?['name'] ?? '').toString();
  final designation = (user?['designation'] ?? '').toString();
  final department = (user?['department_name'] ?? '').toString();
  final aadhaar = (user?['aadhaar'] ?? '').toString();
  final pan = (user?['pan'] ?? '').toString();
  final esicNo = (user?['esic_number'] ?? '').toString();
  final uanNo = (user?['uan_number'] ?? '').toString();
  final pfNo = (user?['pf_number'] ?? '').toString();

  final basic = _n(slip['basic']);
  final hra = _n(slip['hra']);
  final medical = _n(slip['medical']);
  final trans = _n(slip['trans']);
  final lta = _n(slip['lta']);
  final personal = _n(slip['personal']);
  final grossPay = _n(slip['gross_pay']);
  final professionalTax = _n(slip['professional_tax']);
  final pfEmployee = _n(slip['pf_employee']);
  final esicEmployee = _n(slip['esic_employee']);
  final tds = _n(slip['tds']);
  final incentive = _n(slip['incentive']);
  final prBonus = _n(slip['pr_bonus']);
  final reimbursement = _n(slip['reimbursement']);
  final totalPerf = incentive + prBonus + reimbursement;

  // Align with hrms-web ProfileContent.tsx (private payslip).
  final totalEmployeeDeductions = professionalTax + pfEmployee + esicEmployee + tds;
  final takeHome = (grossPay - totalEmployeeDeductions + totalPerf).round();

  final cfg = _asStringKeyedMap(privatePayrollConfig);
  final (mode, effYm) = _payslipEarningsCfg(cfg);
  final pm = payslipPeriodMonthKey(slip);
  final useCompactHeads =
      mode == 'basic_hra_advance_special' && RegExp(r'^\d{4}-\d{2}$').hasMatch(effYm) && pm.isNotEmpty && pm.compareTo(effYm) >= 0;

  final earningsRows = useCompactHeads
      ? <(String, num)>[
          ('Basic + DA', basic),
          ('HRA', hra),
          ('Advance bonus', medical),
          ('Special allowance', personal),
        ]
      : <(String, num)>[
          ('Basic', basic),
          ('HRA', hra),
          ('Medical', medical),
          ('Trans', trans),
          ('LTA', lta),
          ('Personal', personal),
        ];

  final cellClass = 'cell';
  final thClass = 'th';
  String n(num x) => UiFormatters.indianNumber(x);

  final bodyRows = StringBuffer();
  for (var idx = 0; idx < earningsRows.length; idx++) {
    final label = earningsRows[idx].$1;
    final val = earningsRows[idx].$2;
    bodyRows.write('<tr>');
    bodyRows.write('<td class="$cellClass">$label</td>');
    bodyRows.write('<td class="$cellClass text-right">${n(val)}</td>');
    bodyRows.write('<td class="$cellClass text-right">${n(val)}</td>');
    if (idx == 0) {
      bodyRows.write('<td class="$cellClass">Professional Tax</td><td class="$cellClass text-right">${n(professionalTax)}</td>');
      bodyRows.write('<td class="$cellClass">Bonus</td><td class="$cellClass text-right">${n(prBonus)}</td>');
    } else if (idx == 1) {
      bodyRows.write('<td class="$cellClass">PF</td><td class="$cellClass text-right">${n(pfEmployee)}</td>');
      bodyRows.write('<td class="$cellClass">Incentive</td><td class="$cellClass text-right">${n(incentive)}</td>');
    } else if (idx == 2) {
      bodyRows.write('<td class="$cellClass">ESIC</td><td class="$cellClass text-right">${n(esicEmployee)}</td>');
      bodyRows.write('<td class="$cellClass">Reimbursement</td><td class="$cellClass text-right">${n(reimbursement)}</td>');
    } else {
      bodyRows.write('<td colspan="2" class="$cellClass"></td><td colspan="2" class="$cellClass"></td>');
    }
    bodyRows.write('</tr>');
  }

  return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<style>
  body {
    font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;
    margin: 0;
    padding: 16px;
    background: #fff;
  }
  .payslip-print-area {
    overflow-x: auto;
    border: 1px solid #000;
    border-radius: 12px;
    background: #fff;
    padding: 24px;
    box-sizing: border-box;
    width: min(100%, 190mm);
    max-width: 190mm;
    margin: 0 auto;
  }
  table { width: 100%; border-collapse: collapse; }
  .payslip-logo-banner {
    display: flex;
    justify-content: center;
    border-bottom: 1px solid rgba(0,0,0,0.15);
    padding-bottom: 12px;
    margin-bottom: 12px;
  }
  .payslip-logo-banner img {
    max-height: 72px;
    width: auto;
    max-width: min(100%, 280px);
    object-fit: contain;
    object-position: center;
  }
  .muted { color: #64748b; }
  .text-center { text-align: center; }
  .text-right { text-align: right; }
  .font-bold { font-weight: 700; }
  .font-semibold { font-weight: 600; }
  .font-medium { font-weight: 600; }
  .uppercase { text-transform: uppercase; }
  .tracking-wide { letter-spacing: 0.05em; }
  .text-sm { font-size: 14px; }
  .text-base { font-size: 16px; }
  .leading-relaxed { line-height: 1.55; }
  .space-y-1-5 > div { margin-top: 6px; }
  td.$cellClass {
    border: 1px solid #000;
    padding: 8px 12px;
    vertical-align: top;
    font-size: 14px;
  }
  th.$thClass {
    border: 1px solid #000;
    padding: 8px 12px;
    text-align: left;
    font-weight: 600;
    font-size: 14px;
    vertical-align: top;
  }
  td.b { font-weight: 700; }
  .hdrCell {
    border: 1px solid #000;
    padding: 16px;
    text-align: center;
  }
  @media print {
    body { padding: 0; }
    .payslip-print-area {
      position: absolute;
      left: 0;
      top: 0;
      width: 190mm !important;
      max-width: 190mm !important;
      overflow: visible !important;
      box-sizing: border-box;
      border-radius: 0;
    }
    .payslip-financial-table {
      table-layout: fixed;
      width: 100% !important;
      font-size: 12px !important;
    }
    .payslip-financial-table th,
    .payslip-financial-table td {
      padding: 8px 12px !important;
      border-color: #000 !important;
    }
    .payslip-header-table td { padding: 12px 16px !important; border-color: #000 !important; }
    @page { size: 210mm 170mm; margin: 10mm; }
  }
</style>
</head>
<body>
  <div class="payslip-print-area">
    <table class="payslip-header-table" style="border: 1px solid #000;">
      <tbody>
        <tr>
          <td colspan="2" class="hdrCell">
            ${logoUrl.isNotEmpty ? '<div class="payslip-logo-banner"><img src="$logoUrl" alt=""/></div>' : ''}
            <div class="text-base font-bold">$companyName</div>
            ${companyAddr.isNotEmpty ? '<div class="text-sm muted">$companyAddr</div>' : ''}
            <div class="mt-2 text-base font-bold uppercase tracking-wide">Salary Slip</div>
            <div class="text-sm font-semibold">$monthShort $year</div>
          </td>
        </tr>
        <tr>
          <td class="w-1/2 $cellClass">
            <div class="space-y-1-5 text-sm leading-relaxed">
              <div><span class="muted">Employee Name:</span> ${empName.isEmpty ? '—' : empName}</div>
              <div><span class="muted">Designation:</span> ${designation.isEmpty ? '—' : designation}</div>
              <div><span class="muted">Department:</span> ${department.isEmpty ? '—' : department}</div>
              <div><span class="muted">Salary Date:</span> $salaryDate</div>
            </div>
          </td>
          <td class="w-1/2 $cellClass">
            <div class="space-y-1-5 text-sm leading-relaxed">
              <div><span class="muted">Joining Date:</span> ${dojFormatted.isEmpty ? '—' : dojFormatted}</div>
              <div><span class="muted">Aadhaar:</span> ${aadhaar.isEmpty ? '—' : aadhaar}</div>
              <div><span class="muted">PAN:</span> ${pan.isEmpty ? '—' : pan}</div>
            </div>
          </td>
        </tr>
        <tr>
          <td class="$cellClass">
            <div class="space-y-1-5 text-sm leading-relaxed">
              <div><span class="muted">Total Paid Days:</span> ${n(payDays)}</div>
              <div><span class="muted">Unpaid Leaves:</span> ${n(unpaidLeaves)}</div>
            </div>
          </td>
          <td class="$cellClass">
            <div class="space-y-1-5 text-sm leading-relaxed">
              <div><span class="muted">ESIC number:</span> ${esicNo.isEmpty ? '—' : esicNo}</div>
              <div><span class="muted">UAN number:</span> ${uanNo.isEmpty ? '—' : uanNo}</div>
              <div><span class="muted">PF number:</span> ${pfNo.isEmpty ? '—' : pfNo}</div>
            </div>
          </td>
        </tr>
        <tr>
          <td colspan="2" class="border border-black p-0">
            <table class="payslip-financial-table w-full border-collapse text-sm">
              <thead>
                <tr>
                  <th class="$thClass" style="width: 20%;">Earnings</th>
                  <th class="$thClass text-right" style="width: 12%;">Actual</th>
                  <th class="$thClass text-right" style="width: 12%;">Paid</th>
                  <th class="$thClass" style="width: 22%;">Employee Deductions</th>
                  <th class="$thClass text-right" style="width: 12%;">Amount</th>
                  <th class="$thClass" style="width: 22%;">Performance Earnings</th>
                  <th class="$thClass text-right" style="width: 12%;">Amount</th>
                </tr>
              </thead>
              <tbody>
                $bodyRows
                <tr>
                  <td class="$cellClass font-medium">GROSS</td>
                  <td class="$cellClass text-right font-medium">${n(grossPay)}</td>
                  <td class="$cellClass text-right font-medium">${n(grossPay)}</td>
                  <td class="$cellClass font-medium">Total Deduction</td>
                  <td class="$cellClass text-right font-medium">${n(totalEmployeeDeductions)}</td>
                  <td class="$cellClass font-medium">Total</td>
                  <td class="$cellClass text-right font-medium">${n(totalPerf)}</td>
                </tr>
                <tr>
                  <td class="$cellClass font-medium">Net Payable Salary</td>
                  <td class="$cellClass text-right font-medium">${n(takeHome)}</td>
                  <td class="$cellClass text-right font-medium">${n(takeHome)}</td>
                  <td colspan="2" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                </tr>
                <tr>
                  <td class="$cellClass font-bold">Net Pay</td>
                  <td colspan="5" class="$cellClass"></td>
                  <td class="$cellClass text-right font-bold">${n(takeHome)}</td>
                </tr>
                <tr>
                  <td colspan="3" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                </tr>
                <tr>
                  <td colspan="3" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                </tr>
              </tbody>
            </table>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</body>
</html>
''';
}

/// Shared payslip HTML aligned with hrms-web Profile → Pay (private + government modes).
String buildPayslipHtml({
  required Map<String, dynamic> slip,
  required Map<String, dynamic>? company,
  required Map<String, dynamic>? user,
  required String selectedMonth,
  required String selectedYear,
  Map<String, dynamic>? privatePayrollConfig,
}) {
  final gov = _asStringKeyedMap(slip['government_monthly']);
  if (gov != null && gov.isNotEmpty) {
    return _buildGovernmentPayslipHtml(slip: slip, gov: gov, company: company, user: user);
  }
  return _buildPrivatePayslipHtml(
    slip: slip,
    company: company,
    user: user,
    selectedMonth: selectedMonth,
    selectedYear: selectedYear,
    privatePayrollConfig: privatePayrollConfig,
  );
}
