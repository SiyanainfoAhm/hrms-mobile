import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../services/payroll_excel_mobile.dart';
import '../services/payroll_run_preview_service.dart';
import '../services/private_payroll_calc.dart';
import '../services/rpc_service.dart';
import '../services/supabase_client.dart';
import '../ui/formatters.dart';

/// Native **Run** tab: live preview (web-aligned engine), editable pay days (private),
/// Excel export for completed months, deep link to web to **Generate** final run.
class PayrollRunTab extends StatefulWidget {
  const PayrollRunTab({
    super.key,
    required this.actorUserId,
    required this.year,
    required this.month,
    required this.onMonthYearChanged,
    required this.rpc,
  });

  final String actorUserId;
  final int year;
  final int month;
  final void Function(int year, int month) onMonthYearChanged;
  final RpcService rpc;

  @override
  State<PayrollRunTab> createState() => _PayrollRunTabState();
}

class _PayrollRunTabState extends State<PayrollRunTab> {
  late int _runDay;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _rows = [];
  PrivatePayrollConfig _privateCfg = defaultPrivatePayrollConfig();
  int _companyPt = 200;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _runDay = (widget.year == now.year && widget.month == now.month) ? now.day : 1;
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant PayrollRunTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.month != widget.month) {
      final now = DateTime.now().toUtc();
      _runDay = (widget.year == now.year && widget.month == now.month) ? now.day : 1;
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (widget.actorUserId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final master = await widget.rpc.payrollMasterList(actorUserId: widget.actorUserId);
      final cfg = normalizePrivatePayrollConfig(master['privatePayrollConfig']);
      final pt = ((master['companyProfessionalTaxMonthly'] ?? 200) as num).round();
      final preview = await computePayrollRunPreview(
        SupabaseApp.client,
        actorUserId: widget.actorUserId,
        year: widget.year,
        month: widget.month,
        runDay: _runDay,
      );
      final rawRows = (preview['rows'] as List?) ?? const [];
      final rows = rawRows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _privateCfg = cfg;
        _companyPt = pt;
        _preview = preview;
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    try {
      final snap = await widget.rpc.payrollPeriodSnapshot(
        actorUserId: widget.actorUserId,
        year: widget.year,
        month: widget.month,
      );
      final slips = (snap['payslips'] as List?) ?? const [];
      if (slips.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No payslips to export for this month.')));
        return;
      }
      final names = <String, String>{};
      for (final sAny in slips) {
        final s = Map<String, dynamic>.from(sAny as Map);
        final u = s['user'] is Map ? Map<String, dynamic>.from(s['user'] as Map) : null;
        final id = '${s['employee_user_id'] ?? ''}';
        if (id.isEmpty) continue;
        names[id] = (u?['name'] ?? id).toString();
      }
      final rows = slips.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final bytes = buildPayrollExcelBytes(rows, names);
      if (bytes == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not build Excel file.')));
        return;
      }
      final fileName = '${UiFormatters.monthLongName(widget.month)} ${widget.year} Payroll.xlsx';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: fileName),
          ],
          subject: fileName,
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _openWebGenerate() async {
    final base = AppConfig.webAppInviteBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Web app URL is not configured.')));
      }
      return;
    }
    final uri = Uri.parse('$base/app/payroll').replace(queryParameters: {
      'tab': 'run',
      'year': '${widget.year}',
      'month': '${widget.month}',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open browser.')));
    }
  }

  void _onPayDaysSubmitted(String uid, String text, int payDaysMax) {
    final i = _rows.indexWhere((r) => '${r['employeeUserId']}' == uid);
    if (i < 0) return;
    final row = _rows[i];
    if (row['error'] != null) return;
    if (row['payrollMode'] == 'government') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Government pay days: use web Run payroll to adjust (full grid parity).')),
      );
      return;
    }
    final parsed = double.tryParse(text.trim());
    if (parsed == null) return;
    final dim = (_preview?['daysInMonth'] as num?)?.round() ?? 30;
    final clamped = normalizePayDaysHalfStepAndClamp(parsed, payDaysMax);
    final updated = recalcPrivateRunRowAfterPayDaysChange(
      row: row,
      newPayDaysHalfStep: clamped,
      payDenom: dim,
      companyPt: _companyPt,
      privateCfg: _privateCfg,
    );
    setState(() => _rows[i] = updated);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final dim = (preview?['daysInMonth'] as num?)?.round() ?? 30;
    final eff = (preview?['effectiveRunDay'] as num?)?.round() ?? dim;
    final payDaysMax = eff;

    return Column(
      children: [
        Material(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: widget.month,
                        decoration: const InputDecoration(labelText: 'Month', isDense: true),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(UiFormatters.monthLongName(i + 1)),
                          ),
                        ),
                        onChanged: (m) {
                          if (m != null) widget.onMonthYearChanged(widget.year, m);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: widget.year,
                        decoration: const InputDecoration(labelText: 'Year', isDense: true),
                        items: [
                          for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 5; y--)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (y) {
                          if (y != null) widget.onMonthYearChanged(y, widget.month);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        key: ValueKey('runDay-${widget.year}-${widget.month}'),
                        initialValue: '$_runDay',
                        decoration: const InputDecoration(labelText: 'Run day', isDense: true),
                        keyboardType: TextInputType.number,
                        onFieldSubmitted: (v) {
                          final d = int.tryParse(v.trim());
                          if (d == null) return;
                          setState(() => _runDay = d.clamp(1, dim));
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Days in full month: $dim · Through run date: $eff',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh preview'),
                    ),
                    if (preview?['alreadyRun'] == true)
                      OutlinedButton.icon(
                        onPressed: _exportExcel,
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: const Text('Download Excel'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: _openWebGenerate,
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text('Generate on web'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            'Preview matches the web Run engine (masters, leave, PL balance, attendance for weekend rules). '
            'Edit pay days (private) to recalculate like the web grid. Final payroll generation runs on the web app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        if (preview != null && preview['alreadyRun'] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                preview['payrollComplete'] == true
                    ? 'Payroll complete for this month.'
                    : 'Missing payslips: ${preview['missingPayslipCount'] ?? 0}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: preview['payrollComplete'] == true ? Colors.green.shade800 : Colors.deepOrange,
                    ),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading && _rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())],
                  )
                : _error != null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text('Could not load preview.', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        children: [
                          if (_rows.isEmpty)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  preview == null
                                      ? 'Loading…'
                                      : 'No employees in preview for ${UiFormatters.monthLongName(widget.month)} ${widget.year}.',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                            )
                          else
                            for (final r in _rows)
                              _RunEmployeeCard(
                                row: r,
                                payDaysMax: payDaysMax,
                                onPayDaysSubmitted: (uid, text) => _onPayDaysSubmitted(uid, text, payDaysMax),
                              ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}

class _RunEmployeeCard extends StatefulWidget {
  const _RunEmployeeCard({
    required this.row,
    required this.payDaysMax,
    required this.onPayDaysSubmitted,
  });

  final Map<String, dynamic> row;
  final int payDaysMax;
  final void Function(String employeeUserId, String text) onPayDaysSubmitted;

  @override
  State<_RunEmployeeCard> createState() => _RunEmployeeCardState();
}

class _RunEmployeeCardState extends State<_RunEmployeeCard> {
  late TextEditingController _payDaysCtrl;

  @override
  void initState() {
    super.initState();
    _payDaysCtrl = TextEditingController(text: _formatPayDays(widget.row['payDays']));
  }

  String _formatPayDays(dynamic pd) {
    if (pd == null) return '';
    if (pd is num && pd % 1 != 0) return '$pd';
    if (pd is num) return '${pd.round()}';
    return '$pd';
  }

  @override
  void didUpdateWidget(covariant _RunEmployeeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['payDays'] != widget.row['payDays']) {
      _payDaysCtrl.text = _formatPayDays(widget.row['payDays']);
    }
  }

  @override
  void dispose() {
    _payDaysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final name = (r['employeeName'] ?? '—').toString();
    final email = (r['employeeEmail'] ?? '').toString();
    final mode = (r['payrollMode'] ?? 'private').toString();
    final err = r['error']?.toString();
    final pending = r['payslipPending'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleSmall),
                      if (email.isNotEmpty) Text(email, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Text(
                        [if (mode == 'government') 'Government' else 'Private', if (pending) ' · Payslip pending'].join(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ] else ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _payDaysCtrl,
                      readOnly: mode == 'government',
                      decoration: InputDecoration(
                        labelText: 'Pay days',
                        isDense: true,
                        helperText: mode == 'government' ? 'view only (use web to edit)' : 'max ${widget.payDaysMax} (0.5 steps)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onSubmitted: (_) {
                        final id = '${r['employeeUserId'] ?? ''}';
                        if (id.isNotEmpty) widget.onPayDaysSubmitted(id, _payDaysCtrl.text);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Recalculate',
                    onPressed: mode == 'government'
                        ? null
                        : () {
                            final id = '${r['employeeUserId'] ?? ''}';
                            if (id.isNotEmpty) widget.onPayDaysSubmitted(id, _payDaysCtrl.text);
                          },
                    icon: const Icon(Icons.calculate_outlined, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _numRow(context, 'Gross', r['grossPay']),
              _numRow(context, 'Net', r['netPay']),
              _numRow(context, 'PF / PF(R)', '${UiFormatters.inr(r['pfEmployee'])} / ${UiFormatters.inr(r['pfEmployer'])}'),
              _numRow(context, 'ESIC / ESIC(R)', '${UiFormatters.inr(r['esicEmployee'])} / ${UiFormatters.inr(r['esicEmployer'])}'),
              _numRow(context, 'PT', r['profTax']),
              _numRow(context, 'TDS', r['tds']),
              _numRow(
                context,
                'Bonus / Inc / Reimb',
                '${UiFormatters.inr(r['prBonus'])} / ${UiFormatters.inr(r['incentive'])} / ${UiFormatters.inr(r['reimbursement'])}',
              ),
              _numRow(context, 'Take home', r['takeHome']),
              _numRow(context, 'CTC', r['ctc']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numRow(BuildContext context, String label, dynamic v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          Expanded(
            flex: 6,
            child: Text(
              label.contains('/') ? '$v' : UiFormatters.inr(v),
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
