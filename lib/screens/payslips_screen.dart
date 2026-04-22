import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../ui/empty_state.dart';
import '../ui/formatters.dart';
import '../widgets/app_drawer.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  final rpc = RpcService();
  Map<String, dynamic>? data;
  String? selectedMonth; // '01'..'12'
  String? selectedYear; // '2026'
  bool loading = true;
  Object? err;

  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white);

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _slips() {
    final arr = (data?['payslips'] as List?) ?? const [];
    return arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String? _periodMonth(Map<String, dynamic> slip) {
    final ps = (slip['period_start'] ?? '').toString();
    if (ps.length >= 7) return ps.substring(0, 7);
    return null;
  }

  Future<void> _load() async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() {
      loading = true;
      err = null;
    });
    try {
      // Always default to current month/year (even if older payslips exist).
      final now = DateTime.now();
      selectedYear = now.year.toString();
      selectedMonth = now.month.toString().padLeft(2, '0');

      await _fetchForSelection();
    } catch (e) {
      err = e;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchForSelection() async {
    final u = widget.app.user;
    if (u == null) return;
    final y = int.tryParse((selectedYear ?? '').trim());
    final m = int.tryParse((selectedMonth ?? '').trim());
    final d = await rpc.payslipsMe(
      userId: u.id,
      companyId: u.companyId,
      year: y,
      month: m,
    );
    data = d;
    await _renderSelected();
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? _selectedSlip() {
    final slips = _slips();
    if (slips.isEmpty) return null;
    return slips.first;
  }

  String _htmlForSlip({
    required Map<String, dynamic> slip,
    required Map<String, dynamic>? company,
    required Map<String, dynamic>? user,
  }) {
    final monthIdx = (int.tryParse(selectedMonth ?? '01') ?? 1).clamp(1, 12);
    final monthShort = const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][monthIdx - 1];
    final year = selectedYear ?? '';

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
    // Prefer server-calculated net_pay to avoid drift when company-specific payroll formulas change.
    final takeHome = (num.tryParse((slip['net_pay'] ?? 0).toString()) ?? (grossPay - deductions - tds + totalPerf)).round();

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
  td.cell {
    border: 1px solid #000;
    padding: 8px 12px;
    vertical-align: top;
    font-size: 14px;
  }
  th.th {
    border: 1px solid #000;
    padding: 8px 12px;
    text-align: left;
    font-weight: 600;
    font-size: 14px;
    vertical-align: top;
  }
  td.b { font-weight: 700; }

  /* Header table cells match web: border border-black px-4 py-4 */
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
                <tr>
                  <td class="$cellClass">Basic</td>
                  <td class="$cellClass text-right">${n(basic)}</td>
                  <td class="$cellClass text-right">${n(basic)}</td>
                  <td class="$cellClass">Professional Tax</td>
                  <td class="$cellClass text-right">${n(professionalTax)}</td>
                  <td class="$cellClass">Bonus</td>
                  <td class="$cellClass text-right">${n(prBonus)}</td>
                </tr>
                <tr>
                  <td class="$cellClass">HRA</td>
                  <td class="$cellClass text-right">${n(hra)}</td>
                  <td class="$cellClass text-right">${n(hra)}</td>
                  <td class="$cellClass">PF</td>
                  <td class="$cellClass text-right">${n(pfEmployee)}</td>
                  <td class="$cellClass">Incentive</td>
                  <td class="$cellClass text-right">${n(incentive)}</td>
                </tr>
                <tr>
                  <td class="$cellClass">Medical</td>
                  <td class="$cellClass text-right">${n(medical)}</td>
                  <td class="$cellClass text-right">${n(medical)}</td>
                  <td class="$cellClass">ESIC</td>
                  <td class="$cellClass text-right">${n(esicEmployee)}</td>
                  <td class="$cellClass">Reimbursement</td>
                  <td class="$cellClass text-right">${n(reimbursement)}</td>
                </tr>
                <tr>
                  <td class="$cellClass">Trans</td>
                  <td class="$cellClass text-right">${n(trans)}</td>
                  <td class="$cellClass text-right">${n(trans)}</td>
                  <td colspan="2" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                </tr>
                <tr>
                  <td class="$cellClass">LTA</td>
                  <td class="$cellClass text-right">${n(lta)}</td>
                  <td class="$cellClass text-right">${n(lta)}</td>
                  <td colspan="2" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                </tr>
                <tr>
                  <td class="$cellClass">Personal</td>
                  <td class="$cellClass text-right">${n(personal)}</td>
                  <td class="$cellClass text-right">${n(personal)}</td>
                  <td colspan="2" class="$cellClass"></td>
                  <td colspan="2" class="$cellClass"></td>
                </tr>
                <tr>
                  <td class="$cellClass font-medium">GROSS</td>
                  <td class="$cellClass text-right font-medium">${n(grossPay)}</td>
                  <td class="$cellClass text-right font-medium">${n(grossPay)}</td>
                  <td class="$cellClass font-medium">Total Deduction</td>
                  <td class="$cellClass text-right font-medium">${n(deductions)}</td>
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

  Future<void> _renderSelected() async {
    final slip = _selectedSlip();
    if (slip == null) {
      await _web.loadHtmlString('<html><body style="font-family:sans-serif;padding:16px;">No payslip for selected period.</body></html>');
      return;
    }
    final company = data?['company'] == null ? null : Map<String, dynamic>.from(data!['company'] as Map);
    final user = data?['user'] == null ? null : Map<String, dynamic>.from(data!['user'] as Map);
    final html = _htmlForSlip(slip: slip, company: company, user: user);
    await _web.loadHtmlString(html);
  }

  Future<void> _downloadPdf() async {
    final slip = _selectedSlip();
    if (slip == null) return;
    final company = data?['company'] == null ? null : Map<String, dynamic>.from(data!['company'] as Map);
    final user = data?['user'] == null ? null : Map<String, dynamic>.from(data!['user'] as Map);
    final html = _htmlForSlip(slip: slip, company: company, user: user);
    // ignore: deprecated_member_use
    final bytes = await Printing.convertHtml(html: html, format: PdfPageFormat.a4);
    await Printing.sharePdf(bytes: bytes, filename: 'payslip_${selectedYear ?? ''}-${selectedMonth ?? ''}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final slips = _slips();

    List<String> years() {
      final set = <String>{};
      for (final s in slips) {
        final pm = _periodMonth(s);
        if (pm != null && pm.contains('-')) set.add(pm.split('-')[0]);
      }
      final list = set.toList()..sort((a, b) => b.compareTo(a));
      if (list.isEmpty) list.add(DateTime.now().year.toString());
      return list;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payslips'),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            onPressed: loading ? null : _downloadPdf,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      drawer: AppDrawer(app: widget.app),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? EmptyState(title: 'Could not load payslips', subtitle: err.toString(), icon: Icons.error_outline)
              : (u == null)
                  ? const EmptyState(title: 'Not logged in', subtitle: 'Please login again.', icon: Icons.lock_outline)
                  : slips.isEmpty
                      ? const EmptyState(title: 'No payslips yet', subtitle: 'Your payslips will appear here once generated.', icon: Icons.description_outlined)
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: selectedMonth,
                                      decoration: const InputDecoration(
                                        labelText: 'Month',
                                        prefixIcon: Icon(Icons.calendar_month_outlined),
                                      ),
                                      items: List.generate(12, (i) => (i + 1).toString().padLeft(2, '0'))
                                          .map((m) => DropdownMenuItem(
                                                value: m,
                                                child: Text(
                                                  const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][int.parse(m) - 1],
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (v) async {
                                        setState(() => selectedMonth = v);
                                        await _fetchForSelection();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: selectedYear,
                                      decoration: const InputDecoration(
                                        labelText: 'Year',
                                        prefixIcon: Icon(Icons.event_outlined),
                                      ),
                                      items: years().map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                                      onChanged: (v) async {
                                        setState(() => selectedYear = v);
                                        await _fetchForSelection();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(child: WebViewWidget(controller: _web)),
                          ],
                        ),
    );
  }
}

