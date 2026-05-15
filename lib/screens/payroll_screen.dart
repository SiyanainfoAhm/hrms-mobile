import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/private_payroll_calc.dart';
import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../ui/formatters.dart';
import '../ui/payslip_html.dart';
import 'payroll_private_master_editor.dart';
import 'payroll_run_tab.dart';

/// Admin / HR payroll: **Payroll Master**, **Run** (live preview + pay-day edits + Excel for past runs),
/// and **Slips** (payslip preview) using native UI — same data model as the web app.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.app});

  final AppState app;

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> with SingleTickerProviderStateMixin {
  final _rpc = RpcService();
  late final TabController _tabController;

  Future<Map<String, dynamic>>? _masterFuture;
  Future<Map<String, dynamic>>? _snapshotFuture;
  int _snapshotYear = DateTime.now().year;
  int _snapshotMonth = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _reloadMaster();
    _reloadSnapshot();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _reloadMaster() async {
    final u = widget.app.user;
    if (u == null) return;
    final f = _rpc.payrollMasterList(actorUserId: u.id);
    setState(() => _masterFuture = f);
    await f;
  }

  Future<void> _reloadSnapshot() async {
    final u = widget.app.user;
    if (u == null) return;
    final f = _rpc.payrollPeriodSnapshot(
      actorUserId: u.id,
      year: _snapshotYear,
      month: _snapshotMonth,
    );
    setState(() => _snapshotFuture = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Master'),
            Tab(text: 'Run'),
            Tab(text: 'Slips'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MasterTab(
            future: _masterFuture,
            onRefresh: _reloadMaster,
            app: widget.app,
            rpc: _rpc,
          ),
          if (widget.app.user == null)
            const Center(child: Text('Sign in to use payroll.'))
          else
            PayrollRunTab(
              actorUserId: widget.app.user!.id,
              year: _snapshotYear,
              month: _snapshotMonth,
              onMonthYearChanged: (y, m) {
                setState(() {
                  _snapshotYear = y;
                  _snapshotMonth = m;
                });
                _reloadSnapshot();
              },
              rpc: _rpc,
            ),
          _RunSlipsTab(
            year: _snapshotYear,
            month: _snapshotMonth,
            onMonthChanged: (y, m) {
              setState(() {
                _snapshotYear = y;
                _snapshotMonth = m;
              });
              _reloadSnapshot();
            },
            future: _snapshotFuture,
            onRefresh: _reloadSnapshot,
            showSlipPreview: true,
          ),
        ],
      ),
    );
  }
}

class _MasterTab extends StatelessWidget {
  const _MasterTab({
    required this.future,
    required this.onRefresh,
    required this.app,
    required this.rpc,
  });

  final Future<Map<String, dynamic>>? future;
  final Future<void> Function() onRefresh;
  final AppState app;
  final RpcService rpc;

  @override
  Widget build(BuildContext context) {
    final actorId = app.user?.id ?? '';
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())],
            );
          }
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Text('Could not load payroll master.', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(snap.error.toString(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            );
          }
          final data = snap.data ?? const <String, dynamic>{};
          final masters = (data['masters'] as List?) ?? const [];
          if (masters.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: const [
                Text('No active payroll master rows for your company.'),
              ],
            );
          }
          final cfg = normalizePrivatePayrollConfig(data['privatePayrollConfig']);
          final companyPt = ((data['companyProfessionalTaxMonthly'] ?? 200) as num).round();
          final companyAllowsGov = data['companyAllowsGovernmentPayroll'] == true;

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: masters.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final row = Map<String, dynamic>.from(masters[i] as Map);
              final master = Map<String, dynamic>.from((row['master'] as Map?) ?? const {});
              return _PayrollMasterCompactCard(
                row: row,
                master: master,
                cfg: cfg,
                companyPt: companyPt,
                companyAllowsGovernmentPayroll: companyAllowsGov,
                actorUserId: actorId,
                rpc: rpc,
                onSaved: onRefresh,
              );
            },
          );
        },
      ),
    );
  }
}

class _PayrollMasterCompactCard extends StatelessWidget {
  const _PayrollMasterCompactCard({
    required this.row,
    required this.master,
    required this.cfg,
    required this.companyPt,
    required this.companyAllowsGovernmentPayroll,
    required this.actorUserId,
    required this.rpc,
    required this.onSaved,
  });

  final Map<String, dynamic> row;
  final Map<String, dynamic> master;
  final PrivatePayrollConfig cfg;
  final int companyPt;
  final bool companyAllowsGovernmentPayroll;
  final String actorUserId;
  final RpcService rpc;
  final Future<void> Function() onSaved;

  @override
  Widget build(BuildContext context) {
    final name = (row['employeeName'] ?? '—').toString();
    final email = (row['employeeEmail'] ?? '').toString();
    final mode = (master['payroll_mode'] ?? 'private').toString();
    final bank = [
      (row['bankName'] ?? '').toString().trim(),
      (row['bankAccountHolderName'] ?? '').toString().trim(),
      (row['bankAccountNumber'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).join('\n');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                      Text(name, style: Theme.of(context).textTheme.titleMedium),
                      if (email.isNotEmpty) Text(email, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Text(mode == 'government' ? 'Government' : 'Private', style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: actorUserId.isEmpty
                      ? null
                      : () async {
                          final ok = await showPayrollPrivateMasterEditor(
                            context,
                            actorUserId: actorUserId,
                            apiRow: row,
                            cfg: cfg,
                            companyPt: companyPt,
                            companyAllowsGovernmentPayroll: companyAllowsGovernmentPayroll,
                            rpc: rpc,
                          );
                          if (ok && context.mounted) await onSaved();
                        },
                ),
              ],
            ),
            if (bank.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(bank, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            _kvRow('IFSC', row['bankIfsc']),
            const Divider(height: 20),
            _kvRow('Gross', _inr(master['gross_salary'])),
            _kvRow('PF eligible', _boolLabel(master['pf_eligible'])),
            _kvRow('ESIC eligible', _boolLabel(master['esic_eligible'])),
            _kvRow('CTC', _inr(master['ctc'])),
            _kvRow('PF (employee)', _inr(master['pf_employee'])),
            _kvRow('ESIC (employee)', _inr(master['esic_employee'])),
            _kvRow('PF (employer)', _inr(master['pf_employer'])),
            _kvRow('ESIC (employer)', _inr(master['esic_employer'])),
            _kvRow('Adv bonus', _inr(master['advance_bonus'])),
            _kvRow('PT', _inr(master['pt'])),
            _kvRow('TDS', _inr(master['tds'])),
            _kvRow('Take home', _inr(master['take_home'])),
            _kvRow('Applicable from', UiFormatters.indianDate(master['effective_start_date'])),
          ],
        ),
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String t) {
  return Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
  );
}

Widget _kvRow(String label, dynamic value) {
  final v = value == null || '$value'.trim().isEmpty ? '—' : '$value';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
        Expanded(flex: 5, child: Text(v, style: const TextStyle(fontSize: 13), textAlign: TextAlign.end)),
      ],
    ),
  );
}

String _inr(dynamic v) => UiFormatters.inr(v);

String _boolLabel(dynamic v) {
  if (v == true || v == 1 || v == 'true' || v == 't') return 'Yes';
  if (v == false || v == 0 || v == 'false' || v == 'f') return 'No';
  return '—';
}

class _RunSlipsTab extends StatelessWidget {
  const _RunSlipsTab({
    required this.year,
    required this.month,
    required this.onMonthChanged,
    required this.future,
    required this.onRefresh,
    required this.showSlipPreview,
  });

  final int year;
  final int month;
  final void Function(int year, int month) onMonthChanged;
  final Future<Map<String, dynamic>>? future;
  final Future<void> Function() onRefresh;
  final bool showSlipPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: month,
                    decoration: const InputDecoration(labelText: 'Month', isDense: true),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(UiFormatters.monthLongName(i + 1)),
                      ),
                    ),
                    onChanged: (m) {
                      if (m != null) onMonthChanged(year, m);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: year,
                    decoration: const InputDecoration(labelText: 'Year', isDense: true),
                    items: [
                      for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 5; y--)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (y) {
                      if (y != null) onMonthChanged(y, month);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!showSlipPreview)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'Live payroll preview and generating a run use the full engine on web. After payroll is run for a month, totals and payslip rows for that month appear below.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [SizedBox(height: 100), Center(child: CircularProgressIndicator())],
                  );
                }
                if (snap.hasError) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Could not load period.', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(snap.error.toString(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  );
                }
                final data = snap.data ?? const <String, dynamic>{};
                final period = data['period'];
                final payslips = (data['payslips'] as List?) ?? const [];
                final company = data['company'] is Map ? Map<String, dynamic>.from(data['company'] as Map) : null;
                final cfg = data['privatePayrollConfig'];

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    if (period == null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No payroll period for ${UiFormatters.monthLongName(month)} $year yet.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (period['period_name'] ?? 'Period').toString(),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${UiFormatters.indianDate(period['period_start'])} → ${UiFormatters.indianDate(period['period_end'])}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                period['is_locked'] == true ? 'Locked' : 'Open',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: period['is_locked'] == true ? Colors.deepOrange : Colors.green.shade800,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text('${payslips.length} payslip(s)', style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (payslips.isEmpty && period != null)
                      const Text('No payslip rows stored for this period.', style: TextStyle(color: Colors.black54)),
                    for (final raw in payslips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PayslipSummaryCard(
                          slip: Map<String, dynamic>.from(raw as Map),
                          company: company,
                          privatePayrollConfig: cfg is Map<String, dynamic> ? cfg : (cfg is Map ? cfg.map((k, v) => MapEntry(k.toString(), v)) : null),
                          showPreviewButton: showSlipPreview,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PayslipSummaryCard extends StatelessWidget {
  const _PayslipSummaryCard({
    required this.slip,
    required this.company,
    required this.privatePayrollConfig,
    required this.showPreviewButton,
  });

  final Map<String, dynamic> slip;
  final Map<String, dynamic>? company;
  final Map<String, dynamic>? privatePayrollConfig;
  final bool showPreviewButton;

  @override
  Widget build(BuildContext context) {
    final user = slip['user'] is Map ? Map<String, dynamic>.from(slip['user'] as Map) : const <String, dynamic>{};
    final name = (user['name'] ?? slip['employee_user_id'] ?? '—').toString();
    final email = (slip['employee_email'] ?? '').toString();
    final mode = (slip['payroll_mode'] ?? 'private').toString();
    final gov = slip['government_monthly'];

    return Card(
      child: InkWell(
        onTap: showPreviewButton ? () => _openPayslipBottomSheet(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      email.isNotEmpty ? '$name\n$email' : name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (showPreviewButton)
                    Icon(Icons.visibility_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                ],
              ),
              const SizedBox(height: 8),
              Text(mode == 'government' ? 'Government' : 'Private', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              _kvRow('Pay days', slip['pay_days']),
              _kvRow('Gross pay', _inr(slip['gross_pay'])),
              _kvRow('Deductions', _inr(slip['deductions'])),
              _kvRow('Net pay', _inr(slip['net_pay'])),
              _kvRow('CTC', _inr(slip['ctc'])),
              _kvRow('PF (emp / empr)', '${_inr(slip['pf_employee'])} / ${_inr(slip['pf_employer'])}'),
              _kvRow('ESIC (emp / empr)', '${_inr(slip['esic_employee'])} / ${_inr(slip['esic_employer'])}'),
              _kvRow('Professional tax', _inr(slip['professional_tax'])),
              _kvRow('TDS', _inr(slip['tds'])),
              _kvRow('Incentive', _inr(slip['incentive'])),
              _kvRow('PR bonus', _inr(slip['pr_bonus'])),
              _kvRow('Reimbursement', _inr(slip['reimbursement'])),
              _kvRow('Basic', _inr(slip['basic'])),
              _kvRow('HRA', _inr(slip['hra'])),
              _kvRow('Medical', _inr(slip['medical'])),
              _kvRow('Transport', _inr(slip['trans'])),
              _kvRow('LTA', _inr(slip['lta'])),
              _kvRow('Personal', _inr(slip['personal'])),
              _kvRow('Allowances', slip['allowances']),
              _kvRow('Bank', slip['bank_name']),
              _kvRow('Account', slip['bank_account_number']),
              _kvRow('IFSC', slip['bank_ifsc']),
              if (gov is Map && gov.isNotEmpty) ...[
                _sectionTitle(context, 'Government monthly (summary)'),
                _kvRow('Net (gov calc)', _inr(gov['net_salary'])),
                _kvRow('Total earnings', _inr(gov['total_earnings'])),
                _kvRow('Total deductions', _inr(gov['total_deductions'])),
              ],
              if (showPreviewButton)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Tap card for payslip preview', style: Theme.of(context).textTheme.labelSmall),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPayslipBottomSheet(BuildContext context) {
    final ym = _ymFromSlip(slip);
    if (ym == null) return;
    final html = buildPayslipHtml(
      slip: slip,
      company: company,
      user: slip['user'] is Map ? Map<String, dynamic>.from(slip['user'] as Map) : null,
      selectedMonth: ym.$2,
      selectedYear: ym.$1,
      privatePayrollConfig: privatePayrollConfig,
    );
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..loadHtmlString(html, baseUrl: 'https://localhost/');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.88;
        return SizedBox(
          height: h,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Text('Payslip preview'),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: WebViewWidget(controller: ctrl)),
            ],
          ),
        );
      },
    );
  }

  (String, String)? _ymFromSlip(Map<String, dynamic> s) {
    final ps = (s['period_start'] ?? '').toString();
    if (ps.length >= 7) {
      return (ps.substring(0, 4), ps.substring(5, 7));
    }
    return null;
  }
}
