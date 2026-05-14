import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../ui/empty_state.dart';
import '../ui/payslip_html.dart';
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
  String? selectedMonth;
  String? selectedYear;
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

  Future<void> _downloadPdf() async {
    final slip = _selectedSlip();
    if (slip == null) return;
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
    // ignore: deprecated_member_use
    final bytes = await Printing.convertHtml(html: html, format: PdfPageFormat.a4);
    await Printing.sharePdf(bytes: bytes, filename: 'payslip_${selectedYear ?? ''}-${selectedMonth ?? ''}.pdf');
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

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final slips = _slips();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payslips'),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            onPressed: loading || _selectedSlip() == null ? null : _downloadPdf,
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
                      ? const EmptyState(
                          title: 'No payslips yet',
                          subtitle: 'Your payslips will appear here once generated.',
                          icon: Icons.description_outlined,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                            const Divider(height: 1),
                            Expanded(child: WebViewWidget(controller: _web)),
                          ],
                        ),
    );
  }
}
