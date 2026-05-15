import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/payslip_pdf_service.dart';
import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../ui/empty_state.dart';
import '../ui/payslip_html.dart';
import '../theme/tokens.dart';
import '../ui/formatters.dart';
import '../widgets/hrms_ui/app_card.dart';
import '../widgets/hrms_ui/app_snackbar.dart';
import '../widgets/hrms_ui/metric_card.dart';
import '../widgets/hrms_ui/skeleton.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  final rpc = RpcService();
  Map<String, dynamic>? data;
  String? selectedMonth;
  String? selectedYear;
  bool loading = true;
  bool _pdfBusy = false;
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

  /// One slip per calendar month (latest `generated_at` wins).
  List<Map<String, dynamic>> _uniqueSlipsByPeriodDesc() {
    final byKey = <String, Map<String, dynamic>>{};
    for (final s in _slips()) {
      final k = payslipPeriodMonthKey(s);
      if (k.length != 7) continue;
      final existing = byKey[k];
      if (existing == null) {
        byKey[k] = s;
        continue;
      }
      final eg = DateTime.tryParse((existing['generated_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final sg = DateTime.tryParse((s['generated_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (sg.isAfter(eg)) byKey[k] = s;
    }
    final keys = byKey.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) => byKey[k]!).toList();
  }

  Map<String, dynamic>? _cfg() {
    final raw = data?['privatePayrollConfig'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
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
      final now = DateTime.now();
      selectedYear ??= now.year.toString();
      selectedMonth ??= now.month.toString().padLeft(2, '0');

      // Load all payslips once (same as web `/api/payslips/me`).
      final d = await rpc.payslipsMe(userId: u.id, companyId: u.companyId);
      data = d;

      final cards = _uniqueSlipsByPeriodDesc();
      final curKey = '${selectedYear!}-${selectedMonth!}';
      final hasCur = cards.any((s) => payslipPeriodMonthKey(s) == curKey);
      if (!hasCur && cards.isNotEmpty) {
        final first = cards.first;
        final k = payslipPeriodMonthKey(first);
        if (k.length == 7) {
          final parts = k.split('-');
          selectedYear = parts[0];
          selectedMonth = parts[1];
        }
      }

      await _renderSelected();
    } catch (e) {
      err = e;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic>? _selectedSlip() {
    final key = '${selectedYear ?? ''}-${selectedMonth ?? ''}';
    // Keys are always `YYYY-MM` (7 chars), e.g. `2026-04` — not a full date length.
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(key)) return null;
    for (final s in _slips()) {
      if (payslipPeriodMonthKey(s) == key) return s;
    }
    return null;
  }

  Future<void> _renderSelected() async {
    final slip = _selectedSlip();
    if (slip == null) {
      await _web.loadHtmlString(
        '<html><body style="font-family:sans-serif;padding:16px;color:#64748b;">No payslip for the selected period.</body></html>',
      );
      return;
    }
    final company = data?['company'] == null ? null : Map<String, dynamic>.from(data!['company'] as Map);
    final user = data?['user'] == null ? null : Map<String, dynamic>.from(data!['user'] as Map);
    final html = buildPayslipHtml(
      slip: slip,
      company: company,
      user: user,
      selectedMonth: selectedMonth ?? '01',
      selectedYear: selectedYear ?? '',
      privatePayrollConfig: _cfg(),
    );
    await _web.loadHtmlString(html);
  }

  Future<void> _selectPeriod(String year, String month) async {
    setState(() {
      selectedYear = year;
      selectedMonth = month;
    });
    await _renderSelected();
  }

  PayslipPdfInput? _payslipPdfInput() {
    final slip = _selectedSlip();
    if (slip == null) return null;
    final company = data?['company'] == null ? null : Map<String, dynamic>.from(data!['company'] as Map);
    final user = data?['user'] == null ? null : Map<String, dynamic>.from(data!['user'] as Map);
    return PayslipPdfInput(
      slip: slip,
      company: company,
      user: user,
      selectedMonth: selectedMonth ?? '01',
      selectedYear: selectedYear ?? '',
      privatePayrollConfig: _cfg(),
    );
  }

  String _payslipPdfFileName() {
    final user = data?['user'] is Map ? Map<String, dynamic>.from(data!['user'] as Map) : null;
    final base = PayslipPdfService.buildPdfBaseName(
      user: user,
      selectedMonth: selectedMonth ?? '01',
      selectedYear: selectedYear ?? '',
    );
    return '$base.pdf';
  }

  Future<void> _withPayslipPdf(
    Future<void> Function(PayslipPdfInput input) action,
  ) async {
    final input = _payslipPdfInput();
    if (input == null) {
      if (mounted) showAppSnackBar(context, 'No payslip for this period.', error: true);
      return;
    }
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      await action(input);
    } catch (e, st) {
      debugPrint('Payslip PDF: $e\n$st');
      if (mounted) showAppSnackBar(context, 'PDF failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _downloadPayslipPdf() async {
    await _withPayslipPdf((input) async {
      final bytes = await PayslipPdfService.generatePayslipPdfBytes(input);
      final base = PayslipPdfService.buildPdfBaseName(
        user: input.user,
        selectedMonth: input.selectedMonth,
        selectedYear: input.selectedYear,
      );
      final r = await PayslipPdfService.downloadPayslipPdf(bytes: bytes, baseFileName: base);
      if (!mounted) return;
      showAppSnackBar(
        context,
        r.usedShareFallback
            ? 'Opened share sheet to save PDF. Tip: fully restart the app (not hot reload) so FileSaver can save directly.'
            : 'PDF saved successfully.',
      );
    });
  }

  Future<void> _sharePayslipPdf() async {
    await _withPayslipPdf((input) async {
      final bytes = await PayslipPdfService.generatePayslipPdfBytes(input);
      final name = _payslipPdfFileName();
      final ok = await PayslipPdfService.sharePayslipPdf(bytes: bytes, filename: name);
      if (!ok && mounted) {
        showAppSnackBar(context, 'Could not open the share sheet.', error: true);
      }
    });
  }

  Future<void> _previewPayslipPdf(BuildContext dialogContext) async {
    final input = _payslipPdfInput();
    if (input == null) {
      if (mounted) showAppSnackBar(context, 'No payslip for this period.', error: true);
      return;
    }
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await PayslipPdfService.generatePayslipPdfBytes(input);
      final name = _payslipPdfFileName();
      if (!dialogContext.mounted) return;
      await PayslipPdfService.previewPayslipPdf(context: dialogContext, bytes: bytes, pdfFileName: name);
    } catch (e, st) {
      debugPrint('Payslip PDF preview: $e\n$st');
      if (mounted) showAppSnackBar(context, 'PDF preview failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  List<String> _yearChoices(Map<String, dynamic>? user) {
    final set = <String>{};
    for (final s in _slips()) {
      final k = payslipPeriodMonthKey(s);
      if (k.length >= 4) set.add(k.substring(0, 4));
    }
    final dojStr = (user?['date_of_joining'] ?? '').toString();
    final joinY = dojStr.length >= 4 ? (int.tryParse(dojStr.substring(0, 4)) ?? (DateTime.now().year - 2)) : (DateTime.now().year - 2);
    final currentYear = DateTime.now().year;
    for (var y = currentYear; y >= joinY.clamp(2020, currentYear); y--) {
      set.add(y.toString());
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    if (list.isEmpty) list.add(DateTime.now().year.toString());
    return list;
  }

  num _n(dynamic v) => num.tryParse((v ?? '').toString()) ?? 0;

  Future<void> _openSlipViewer() async {
    await _renderSelected();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Salary slip'),
            actions: [
              IconButton(
                tooltip: 'Preview PDF',
                onPressed: _pdfBusy || _selectedSlip() == null ? null : () => _previewPayslipPdf(ctx),
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              IconButton(
                tooltip: 'Download PDF',
                onPressed: _pdfBusy || _selectedSlip() == null ? null : _downloadPayslipPdf,
                icon: const Icon(Icons.download_outlined),
              ),
              IconButton(
                tooltip: 'Share PDF',
                onPressed: _pdfBusy || _selectedSlip() == null ? null : _sharePayslipPdf,
                icon: const Icon(Icons.share_outlined),
              ),
            ],
          ),
          body: SafeArea(child: WebViewWidget(controller: _web)),
        ),
      ),
    );
    if (mounted) await _renderSelected();
  }

  List<Widget> _moneyRows(Map<String, dynamic> slip, List<(String, String)> keys) {
    return [
      for (final (k, label) in keys)
        if (_n(slip[k]) != 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(label, style: const TextStyle(color: HrmsTokens.muted, fontSize: 13))),
                Text(UiFormatters.inr(_n(slip[k])), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final slips = _slips();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Payslips'),
      ),
      body: loading
          ? ListView(
              padding: const EdgeInsets.all(HrmsTokens.s4),
              children: const [
                SkeletonCard(lines: 2),
                SizedBox(height: 12),
                SkeletonCard(lines: 4),
                SizedBox(height: 12),
                SkeletonCard(lines: 3),
              ],
            )
          : err != null
              ? EmptyState(title: 'Could not load payslips', subtitle: err.toString(), icon: Icons.error_outline)
              : (u == null)
                  ? const EmptyState(title: 'Not logged in', subtitle: 'Please login again.', icon: Icons.lock_outline)
                  : slips.isEmpty
                      ? const EmptyState(
                          title: 'No payslips yet',
                          subtitle: 'Your payslips will appear here once generated.',
                          icon: Icons.description_outlined,
                        )
                      : Builder(
                          builder: (context) {
                            final slip = _selectedSlip();
                            final gross = slip != null ? _n(slip['gross_pay']) : 0;
                            final net = slip != null ? _n(slip['net_pay']) : 0;
                            final ded = slip != null ? (gross - net).clamp(0, 1e15) : 0;
                            final payDays = slip != null ? _n(slip['pay_days']) : 0;
                            final unpaid = slip != null ? _n(slip['unpaid_leave_days']) : 0;

                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(HrmsTokens.s4, HrmsTokens.s3, HrmsTokens.s4, 100),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AppCard(
                                    title: 'Pay period',
                                    subtitle: 'Month and year',
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
                                                .map(
                                                  (m) => DropdownMenuItem(
                                                    value: m,
                                                    child: Text(
                                                      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][int.parse(m) - 1],
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: (v) async {
                                              if (v == null) return;
                                              await _selectPeriod(selectedYear ?? DateTime.now().year.toString(), v);
                                              if (mounted) setState(() {});
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
                                            items: _yearChoices(data?['user'] is Map ? Map<String, dynamic>.from(data!['user'] as Map) : null)
                                                .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                                                .toList(),
                                            onChanged: (v) async {
                                              if (v == null) return;
                                              await _selectPeriod(v, selectedMonth ?? '01');
                                              if (mounted) setState(() {});
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (slip == null)
                                    AppCard(
                                      title: 'No payslip',
                                      child: Text(
                                        'No payslip for the selected period.',
                                        style: GoogleFonts.inter(color: HrmsTokens.muted, fontSize: 14),
                                      ),
                                    )
                                  else ...[
                                    AppCard(
                                      title: 'Net pay',
                                      subtitle: 'Take-home for this period',
                                      child: Text(
                                        UiFormatters.inr(net),
                                        style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, color: HrmsTokens.primary),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: MetricCard(
                                            label: 'Gross pay',
                                            value: UiFormatters.inr(gross),
                                            icon: Icons.trending_up_outlined,
                                            compact: true,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: MetricCard(
                                            label: 'Total deductions',
                                            value: UiFormatters.inr(ded),
                                            icon: Icons.trending_down_outlined,
                                            iconBackground: HrmsTokens.danger.withValues(alpha: 0.12),
                                            compact: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: MetricCard(
                                            label: 'Paid days',
                                            value: payDays == 0 ? '—' : '${payDays.round()}',
                                            icon: Icons.calendar_today_outlined,
                                            compact: true,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: MetricCard(
                                            label: 'Unpaid leaves',
                                            value: unpaid == 0 ? '—' : unpaid.toString(),
                                            icon: Icons.event_busy_outlined,
                                            compact: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    AppCard(
                                      title: 'Earnings',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: _moneyRows(slip, const [
                                          ('basic', 'Basic'),
                                          ('hra', 'HRA'),
                                          ('medical', 'Medical'),
                                          ('trans', 'Transport'),
                                          ('lta', 'LTA'),
                                          ('personal', 'Personal'),
                                          ('incentive', 'Incentive'),
                                          ('pr_bonus', 'PR Bonus'),
                                          ('reimbursement', 'Reimbursement'),
                                        ]),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    AppCard(
                                      title: 'Deductions',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: _moneyRows(slip, const [
                                          ('professional_tax', 'Professional tax'),
                                          ('pf_employee', 'PF (employee)'),
                                          ('esic_employee', 'ESIC (employee)'),
                                          ('tds', 'TDS'),
                                        ]),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: _openSlipViewer,
                                      icon: const Icon(Icons.visibility_outlined),
                                      label: const Text('View salary slip'),
                                    ),
                                    const SizedBox(height: 10),
                                    if (_pdfBusy) const LinearProgressIndicator(minHeight: 3),
                                    if (_pdfBusy) const SizedBox(height: 10),
                                    FilledButton.tonalIcon(
                                      onPressed: _pdfBusy ? null : _downloadPayslipPdf,
                                      icon: const Icon(Icons.download_outlined),
                                      label: const Text('Download PDF'),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _pdfBusy ? null : _sharePayslipPdf,
                                      icon: const Icon(Icons.share_outlined),
                                      label: const Text('Share PDF'),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
    );
  }
}
