import 'formatters.dart';

/// Shared payslip HTML renderer (copied from `PayslipsScreen` so Profile → My Pay can reuse it).
String buildPayslipHtml({
  required Map<String, dynamic> slip,
  required Map<String, dynamic>? company,
  required Map<String, dynamic>? user,
  required String selectedMonth,
  required String selectedYear,
}) {
  final monthIdx = (int.tryParse(selectedMonth) ?? 1).clamp(1, 12);
  final monthShort = const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][monthIdx - 1];
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
  final payDays = num.tryParse((slip['pay_days'] ?? 0).toString()) ?? 0;
  final unpaidLeaves = totalDays > 0 ? (totalDays - payDays).clamp(0, 366) : 0;

  final companyName = (company?['name'] ?? 'Company').toString();
  final companyAddr = (company?['address'] ?? '').toString();
  final logoUrl = (company?['logo_url'] ?? '').toString().trim();

  final empName = (user?['name'] ?? '').toString();
  final designation = (user?['designation'] ?? '').toString();
  final aadhaar = (user?['aadhaar'] ?? '').toString();
  final pan = (user?['pan'] ?? '').toString();
  final esicNo = (user?['esic_number'] ?? '').toString();
  final uanNo = (user?['uan_number'] ?? '').toString();
  final pfNo = (user?['pf_number'] ?? '').toString();

  final basic = num.tryParse((slip['basic'] ?? 0).toString()) ?? 0;
  final hra = num.tryParse((slip['hra'] ?? 0).toString()) ?? 0;
  final medical = num.tryParse((slip['medical'] ?? 0).toString()) ?? 0;
  final trans = num.tryParse((slip['trans'] ?? 0).toString()) ?? 0;
  final lta = num.tryParse((slip['lta'] ?? 0).toString()) ?? 0;
  final personal = num.tryParse((slip['personal'] ?? 0).toString()) ?? 0;
  final grossPay = num.tryParse((slip['gross_pay'] ?? 0).toString()) ?? 0;
  final deductions = num.tryParse((slip['deductions'] ?? 0).toString()) ?? 0;
  final professionalTax = num.tryParse((slip['professional_tax'] ?? 0).toString()) ?? 0;
  final pfEmployee = num.tryParse((slip['pf_employee'] ?? 0).toString()) ?? 0;
  final esicEmployee = num.tryParse((slip['esic_employee'] ?? 0).toString()) ?? 0;
  final incentive = num.tryParse((slip['incentive'] ?? 0).toString()) ?? 0;
  final prBonus = num.tryParse((slip['pr_bonus'] ?? 0).toString()) ?? 0;
  final reimbursement = num.tryParse((slip['reimbursement'] ?? 0).toString()) ?? 0;
  final tds = num.tryParse((slip['tds'] ?? 0).toString()) ?? 0;
  final totalPerf = incentive + prBonus + reimbursement;
  final takeHome = (grossPay - deductions - tds + totalPerf).round();

  // Match web payslip styling (role-profile.tsx)
  final cellClass = "cell";
  final thClass = "th";

  String n(num x) => UiFormatters.indianNumber(x);

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

  /* Matches web wrapper: rounded-lg border border-black bg-white p-6 */
  .payslip-print-area {
    overflow-x: auto;
    border: 1px solid #000;
    border-radius: 12px;
    background: #fff;
    padding: 24px;
    box-sizing: border-box;
    width: min(100%, 190mm);
    max-width: 190mm;
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

  /* Match web cellClass/thClass: border border-black px-3 py-2 align-top text-sm */
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
  }
</style>
</head>
<body>
  <div class="payslip-print-area">
    ${logoUrl.isNotEmpty ? '<div class="payslip-logo-banner"><img src="$logoUrl" alt="Logo" /></div>' : ''}
    <div class="text-center">
      <div class="font-bold text-base">$companyName</div>
      ${companyAddr.isNotEmpty ? '<div class="muted text-sm leading-relaxed">$companyAddr</div>' : ''}
      <div class="font-bold text-base" style="margin-top: 8px;">PAY SLIP</div>
      <div class="muted text-sm">$monthShort $year</div>
    </div>

    <div style="height: 12px;"></div>

    <table>
      <tr>
        <th class="$thClass">Employee</th>
        <td class="$cellClass">$empName</td>
      </tr>
      <tr>
        <th class="$thClass">Designation</th>
        <td class="$cellClass">$designation</td>
      </tr>
      <tr>
        <th class="$thClass">Date of joining</th>
        <td class="$cellClass">$dojFormatted</td>
      </tr>
      <tr>
        <th class="$thClass">Salary date</th>
        <td class="$cellClass">$salaryDate</td>
      </tr>
      <tr>
        <th class="$thClass">Total days</th>
        <td class="$cellClass">$totalDays</td>
      </tr>
      <tr>
        <th class="$thClass">Pay days</th>
        <td class="$cellClass">$payDays</td>
      </tr>
      <tr>
        <th class="$thClass">Unpaid leaves</th>
        <td class="$cellClass">$unpaidLeaves</td>
      </tr>
      <tr>
        <th class="$thClass">Aadhaar</th>
        <td class="$cellClass">$aadhaar</td>
      </tr>
      <tr>
        <th class="$thClass">PAN</th>
        <td class="$cellClass">$pan</td>
      </tr>
      <tr>
        <th class="$thClass">ESIC</th>
        <td class="$cellClass">$esicNo</td>
      </tr>
      <tr>
        <th class="$thClass">UAN</th>
        <td class="$cellClass">$uanNo</td>
      </tr>
      <tr>
        <th class="$thClass">PF</th>
        <td class="$cellClass">$pfNo</td>
      </tr>
    </table>

    <div style="height: 14px;"></div>

    <table>
      <tr>
        <th class="$thClass">Earnings</th>
        <th class="$thClass" style="text-align:right;">Amount</th>
        <th class="$thClass">Deductions</th>
        <th class="$thClass" style="text-align:right;">Amount</th>
      </tr>
      <tr>
        <td class="$cellClass">Basic</td>
        <td class="$cellClass text-right">${n(basic)}</td>
        <td class="$cellClass">PF (Employee)</td>
        <td class="$cellClass text-right">${n(pfEmployee)}</td>
      </tr>
      <tr>
        <td class="$cellClass">HRA</td>
        <td class="$cellClass text-right">${n(hra)}</td>
        <td class="$cellClass">ESIC (Employee)</td>
        <td class="$cellClass text-right">${n(esicEmployee)}</td>
      </tr>
      <tr>
        <td class="$cellClass">Medical</td>
        <td class="$cellClass text-right">${n(medical)}</td>
        <td class="$cellClass">Professional tax</td>
        <td class="$cellClass text-right">${n(professionalTax)}</td>
      </tr>
      <tr>
        <td class="$cellClass">Transport</td>
        <td class="$cellClass text-right">${n(trans)}</td>
        <td class="$cellClass">TDS</td>
        <td class="$cellClass text-right">${n(tds)}</td>
      </tr>
      <tr>
        <td class="$cellClass">LTA</td>
        <td class="$cellClass text-right">${n(lta)}</td>
        <td class="$cellClass">Other deductions</td>
        <td class="$cellClass text-right">${n(deductions - professionalTax - pfEmployee - esicEmployee)}</td>
      </tr>
      <tr>
        <td class="$cellClass">Personal</td>
        <td class="$cellClass text-right">${n(personal)}</td>
        <td class="$cellClass"></td>
        <td class="$cellClass"></td>
      </tr>
      <tr>
        <td class="$cellClass font-semibold">Gross pay</td>
        <td class="$cellClass text-right font-semibold">${n(grossPay)}</td>
        <td class="$cellClass font-semibold">Total deductions</td>
        <td class="$cellClass text-right font-semibold">${n(deductions + tds)}</td>
      </tr>
      <tr>
        <td class="$cellClass">Performance (Incentive + PR bonus + Reimbursement)</td>
        <td class="$cellClass text-right">${n(totalPerf)}</td>
        <td class="$cellClass font-bold">Take home</td>
        <td class="$cellClass text-right font-bold">${n(takeHome)}</td>
      </tr>
    </table>
  </div>
</body>
</html>
''';
}

