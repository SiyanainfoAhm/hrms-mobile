import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/private_payroll_calc.dart';
import '../services/rpc_service.dart';
import '../ui/formatters.dart';

String _ymdUtc(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseYmdUtc(String? s) {
  if (s == null || s.length < 10) return null;
  final p = s.substring(0, 10).split('-');
  if (p.length != 3) return null;
  return DateTime.utc(int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0, int.tryParse(p[2]) ?? 0);
}

String? _dayBeforeYmd(String ymd) {
  final d = _parseYmdUtc(ymd);
  if (d == null) return null;
  return _ymdUtc(d.subtract(const Duration(days: 1)));
}

String? _dayAfterYmd(String ymd) {
  final d = _parseYmdUtc(ymd);
  if (d == null) return null;
  return _ymdUtc(d.add(const Duration(days: 1)));
}

int _parseInt(String s) => int.tryParse(s.trim()) ?? 0;

double? _parseDoubleOpt(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Full-screen bottom sheet: **Edit Payroll Master** (private + bank) aligned with web dialog.
Future<bool> showPayrollPrivateMasterEditor(
  BuildContext context, {
  required String actorUserId,
  required Map<String, dynamic> apiRow,
  required PrivatePayrollConfig cfg,
  required int companyPt,
  required bool companyAllowsGovernmentPayroll,
  required RpcService rpc,
}) async {
  final r = await showModalBottomSheet<bool?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PayrollPrivateMasterEditorSheet(
      actorUserId: actorUserId,
      apiRow: apiRow,
      cfg: cfg,
      companyPt: companyPt,
      companyAllowsGovernmentPayroll: companyAllowsGovernmentPayroll,
      rpc: rpc,
    ),
  );
  return r == true;
}

class _PayrollPrivateMasterEditorSheet extends StatefulWidget {
  const _PayrollPrivateMasterEditorSheet({
    required this.actorUserId,
    required this.apiRow,
    required this.cfg,
    required this.companyPt,
    required this.companyAllowsGovernmentPayroll,
    required this.rpc,
  });

  final String actorUserId;
  final Map<String, dynamic> apiRow;
  final PrivatePayrollConfig cfg;
  final int companyPt;
  final bool companyAllowsGovernmentPayroll;
  final RpcService rpc;

  @override
  State<_PayrollPrivateMasterEditorSheet> createState() => _PayrollPrivateMasterEditorSheetState();
}

class _PayrollPrivateMasterEditorSheetState extends State<_PayrollPrivateMasterEditorSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _gross = TextEditingController();
  final _basic = TextEditingController();
  final _hra = TextEditingController();
  final _medical = TextEditingController();
  final _trans = TextEditingController();
  final _lta = TextEditingController();
  final _personal = TextEditingController();
  final _pt = TextEditingController();
  final _tds = TextEditingController();
  final _advance = TextEditingController();
  final _reason = TextEditingController(text: 'Payroll master update');
  final _newStart = TextEditingController();
  final _prevEnd = TextEditingController();

  final _bankName = TextEditingController();
  final _bankHolder = TextEditingController();
  final _bankAcct = TextEditingController();
  final _bankIfsc = TextEditingController();

  bool _pfManual = false;
  bool _esicManual = false;
  bool _breakupManual = false;
  int _prevGrossForAuto = 0;

  bool _pfEligible = true;
  bool _esicEligible = false;

  String _payrollMode = 'private';
  bool _saving = false;

  bool get _compactHeads => widget.cfg.payslipEarningsMode == 'basic_hra_advance_special';

  Map<String, dynamic> get _m => Map<String, dynamic>.from((widget.apiRow['master'] as Map?) ?? const {});

  String get _employeeLabel =>
      '${widget.apiRow['employeeName'] ?? ''}${(widget.apiRow['employeeEmail'] ?? '').toString().isEmpty ? '' : ' · ${widget.apiRow['employeeEmail']}'}';

  String get _targetId => (widget.apiRow['employeeUserId'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    final m = _m;
    final gross = (_n(m['gross_salary']) ?? 0).round();
    _prevGrossForAuto = gross;
    _gross.text = gross > 0 ? '$gross' : '';

    final basic = (_n(m['basic']) ?? 0).round();
    final hra = (_n(m['hra']) ?? 0).round();
    final medical = (_n(m['medical']) ?? 0).round();
    final trans = (_n(m['trans']) ?? 0).round();
    final lta = (_n(m['lta']) ?? 0).round();
    final personal = (_n(m['personal']) ?? 0).round();
    final sum = basic + hra + medical + trans + lta + personal;
    PrivateSalaryBreakup split;
    if (gross > 0 && (sum == 0 || (sum - gross).abs() > 2)) {
      split = defaultSalaryBreakup(gross, widget.cfg);
    } else if (sum > 0) {
      split = PrivateSalaryBreakup(basic: basic, hra: hra, medical: medical, trans: trans, lta: lta, personal: personal);
    } else {
      split = defaultSalaryBreakup(gross > 0 ? gross : 0, widget.cfg);
    }
    _basic.text = '${split.basic}';
    _hra.text = '${split.hra}';
    _medical.text = '${split.medical}';
    _trans.text = '${split.trans}';
    _lta.text = '${split.lta}';
    _personal.text = '${split.personal}';

    _pfEligible = m['pf_eligible'] == false ? false : true;
    _esicEligible = m['esic_eligible'] == true;
    _pfManual = false;
    _esicManual = false;
    _breakupManual = false;

    final mpt = _n(m['pt']);
    _pt.text = (mpt != null && mpt >= 0) ? '${mpt.round()}' : '${widget.companyPt}';
    _tds.text = '${(_n(m['tds']) ?? 0).round()}';
    _advance.text = '${(_n(m['advance_bonus']) ?? 0).round()}';

    _payrollMode = (m['payroll_mode'] ?? 'private').toString() == 'government' ? 'government' : 'private';
    if (_payrollMode == 'government' && !widget.companyAllowsGovernmentPayroll) {
      _payrollMode = 'private';
    }

    final curStart = (m['effective_start_date'] ?? '').toString();
    final curYmd = curStart.length >= 10 ? curStart.substring(0, 10) : '';
    if (curYmd.isNotEmpty) {
      final ns = _dayAfterYmd(curYmd) ?? _ymdUtc(DateTime.now().toUtc());
      _newStart.text = ns;
      _prevEnd.text = _dayBeforeYmd(ns) ?? curYmd;
    } else {
      final today = _ymdUtc(DateTime.now().toUtc());
      _newStart.text = today;
      _prevEnd.text = _dayBeforeYmd(today) ?? today;
    }

    _bankName.text = (widget.apiRow['bankName'] ?? '').toString();
    _bankHolder.text = (widget.apiRow['bankAccountHolderName'] ?? '').toString();
    _bankAcct.text = (widget.apiRow['bankAccountNumber'] ?? '').toString();
    _bankIfsc.text = (widget.apiRow['bankIfsc'] ?? '').toString();

    _applyPolicyFlags();
  }

  num? _n(dynamic v) => num.tryParse('${v ?? ''}');

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _gross,
      _basic,
      _hra,
      _medical,
      _trans,
      _lta,
      _personal,
      _pt,
      _tds,
      _advance,
      _reason,
      _newStart,
      _prevEnd,
      _bankName,
      _bankHolder,
      _bankAcct,
      _bankIfsc,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPolicyFlags() {
    final g = _parseInt(_gross.text);
    if (g <= 0) return;
    if (!_pfManual) {
      _pfEligible = isPfStatutorilyMandatory(g, widget.cfg);
    }
    if (!_esicManual) {
      final b = defaultSalaryBreakup(g, widget.cfg).basic;
      _esicEligible = isWithinEsicWageCeiling(b, widget.cfg);
    }
  }

  void _syncPolicyFlagsFromGross() {
    _applyPolicyFlags();
    setState(() {});
  }

  PrivateSalaryBreakupInput? _breakupInput() {
    final b = _parseInt(_basic.text);
    final h = _parseInt(_hra.text);
    final me = _parseInt(_medical.text);
    final t = _compactHeads ? 0 : _parseInt(_trans.text);
    final l = _compactHeads ? 0 : _parseInt(_lta.text);
    final p = _parseInt(_personal.text);
    final sum = b + h + me + t + l + p;
    if (sum <= 0) return null;
    return PrivateSalaryBreakupInput(basic: b, hra: h, medical: me, trans: t, lta: l, personal: p);
  }

  PrivateEditPreview? _preview() {
    final g = _parseInt(_gross.text);
    final tds = _parseInt(_tds.text);
    final adv = _parseInt(_advance.text);
    final ptParsed = _parseDoubleOpt(_pt.text);
    if (g <= 0) return null;
    return computePrivateEditPreview(
      gross: g,
      pfEligible: _pfEligible,
      esicEligible: _esicEligible,
      ptFieldParsed: ptParsed,
      companyPt: widget.companyPt,
      tds: tds,
      advanceBonus: adv,
      salaryBreakup: _breakupInput(),
      cfg: widget.cfg,
    );
  }

  Future<void> _pickDate(TextEditingController c) async {
    final initial = _parseYmdUtc(c.text) ?? DateTime.now().toUtc();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (d != null) setState(() => c.text = _ymdUtc(DateTime.utc(d.year, d.month, d.day)));
  }

  Future<void> _saveBank() async {
    setState(() => _saving = true);
    try {
      await widget.rpc.payrollMasterSaveBank(
        actorUserId: widget.actorUserId,
        targetUserId: _targetId,
        bankName: _bankName.text.trim(),
        bankAccountHolderName: _bankHolder.text.trim(),
        bankAccountNumber: _bankAcct.text.trim(),
        bankIfsc: _bankIfsc.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveStructure() async {
    if (_payrollMode == 'government') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Government payroll master: please use the web app for this update.')),
      );
      return;
    }
    final g0 = _parseInt(_gross.text);
    if (g0 <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gross salary is required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final save = buildPrivateMasterSaveRow(
        grossInput: g0,
        basicIn: _parseInt(_basic.text),
        hraIn: _parseInt(_hra.text),
        medicalIn: _parseInt(_medical.text),
        transIn: _parseInt(_trans.text),
        ltaIn: _parseInt(_lta.text),
        personalIn: _parseInt(_personal.text),
        compactPayslipHeads: _compactHeads,
        pfEligible: _pfEligible,
        esicEligible: _esicEligible,
        ptOverride: _parseDoubleOpt(_pt.text),
        companyPt: widget.companyPt,
        tds: _parseInt(_tds.text),
        advanceBonus: _parseInt(_advance.text),
        cfg: widget.cfg,
      );

      final payload = <String, dynamic>{
        'effective_start_date': _newStart.text.trim().substring(0, 10),
        'previous_effective_end_date': _prevEnd.text.trim().substring(0, 10),
        'reason_for_change': _reason.text.trim(),
        'gross_salary': save.grossSalary,
        'basic': save.basic,
        'hra': save.hra,
        'medical': save.medical,
        'trans': save.trans,
        'lta': save.lta,
        'personal': save.personal,
        'ctc': save.ctc,
        'pf_eligible': save.pfEligible,
        'esic_eligible': save.esicEligible,
        'pf_employee': save.pfEmployee,
        'pf_employer': save.pfEmployer,
        'esic_employee': save.esicEmployee,
        'esic_employer': save.esicEmployer,
        'pt': save.pt,
        'tds': save.tds,
        'advance_bonus': save.advanceBonus,
        'take_home': save.takeHome,
      };

      await widget.rpc.payrollMasterSavePrivate(
        actorUserId: widget.actorUserId,
        targetUserId: _targetId,
        payload: payload,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onGrossChanged(String v) {
    final g = _parseInt(v);
    final prev = _prevGrossForAuto;
    final basic = _parseInt(_basic.text);
    final hra = _parseInt(_hra.text);
    final medical = _parseInt(_medical.text);
    final trans = _parseInt(_trans.text);
    final lta = _parseInt(_lta.text);
    final personal = _parseInt(_personal.text);
    final sum = basic + hra + medical + (_compactHeads ? 0 : trans) + (_compactHeads ? 0 : lta) + personal;
    final empty = sum == 0;
    final wasDefault = prev > 0 && isDefaultSalaryBreakupForGross(prev, basic, hra, medical, trans, lta, personal, widget.cfg);
    if (g > 0 && (empty || wasDefault) && !_breakupManual) {
      final s = defaultSalaryBreakup(g, widget.cfg);
      _basic.text = '${s.basic}';
      _hra.text = '${s.hra}';
      _medical.text = '${s.medical}';
      _trans.text = _compactHeads ? '0' : '${s.trans}';
      _lta.text = _compactHeads ? '0' : '${s.lta}';
      _personal.text = '${s.personal}';
    }
    _prevGrossForAuto = g;
    _syncPolicyFlagsFromGross();
    setState(() {});
  }

  void _onGrossEditingComplete() {
    final g = _parseInt(_gross.text);
    if (g <= 0) return;
    final basic = _parseInt(_basic.text);
    final hra = _parseInt(_hra.text);
    final medical = _parseInt(_medical.text);
    final trans = _parseInt(_trans.text);
    final lta = _parseInt(_lta.text);
    final personal = _parseInt(_personal.text);
    final sum = basic + hra + medical + (_compactHeads ? 0 : trans) + (_compactHeads ? 0 : lta) + personal;
    if ((sum - g).abs() > 2) {
      final s = defaultSalaryBreakup(g, widget.cfg);
      setState(() {
        _basic.text = '${s.basic}';
        _hra.text = '${s.hra}';
        _medical.text = '${s.medical}';
        _trans.text = _compactHeads ? '0' : '${s.trans}';
        _lta.text = _compactHeads ? '0' : '${s.lta}';
        _personal.text = '${s.personal}';
        _breakupManual = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.92;
    final pv = _preview();

    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Edit Payroll Master', style: Theme.of(context).textTheme.titleLarge),
                      Text(_employeeLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
              ],
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Payroll structure'),
                Tab(text: 'Bank information'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Builder(
                        builder: (context) {
                          final modes = <String>['private', if (widget.companyAllowsGovernmentPayroll) 'government'];
                          final effectiveMode = modes.contains(_payrollMode) ? _payrollMode : 'private';
                          return DropdownButtonFormField<String>(
                            value: effectiveMode,
                            decoration: const InputDecoration(labelText: 'Structure'),
                            items: [
                              const DropdownMenuItem(value: 'private', child: Text('Private (CTC / gross)')),
                              if (widget.companyAllowsGovernmentPayroll)
                                const DropdownMenuItem(value: 'government', child: Text('Government (gross basic)')),
                            ],
                            onChanged: widget.companyAllowsGovernmentPayroll
                                ? (v) {
                                    setState(() => _payrollMode = v ?? 'private');
                                  }
                                : null,
                          );
                        },
                      ),
                      if (_payrollMode == 'government')
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Government structure editing is not supported in the mobile app yet. Switch to Private or use web.',
                            style: TextStyle(color: Colors.deepOrange),
                          ),
                        ),
                      if (_payrollMode == 'private') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _gross,
                          decoration: const InputDecoration(labelText: 'Gross salary (monthly) *'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: _onGrossChanged,
                          onEditingComplete: _onGrossEditingComplete,
                        ),
                        const SizedBox(height: 12),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Salary breakdown (optional, for payslip)', style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    SizedBox(
                                      width: 140,
                                      child: TextField(
                                        controller: _basic,
                                        decoration: const InputDecoration(labelText: 'Basic + DA', isDense: true),
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) {
                                          _breakupManual = true;
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: TextField(
                                        controller: _hra,
                                        decoration: const InputDecoration(labelText: 'HRA', isDense: true),
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) {
                                          _breakupManual = true;
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 140,
                                      child: TextField(
                                        controller: _medical,
                                        decoration: const InputDecoration(labelText: 'Advance bonus', isDense: true),
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) {
                                          _breakupManual = true;
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                    if (!_compactHeads) ...[
                                      SizedBox(
                                        width: 100,
                                        child: TextField(
                                          controller: _trans,
                                          decoration: const InputDecoration(labelText: 'Trans', isDense: true),
                                          keyboardType: TextInputType.number,
                                          onChanged: (_) {
                                            _breakupManual = true;
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 100,
                                        child: TextField(
                                          controller: _lta,
                                          decoration: const InputDecoration(labelText: 'LTA', isDense: true),
                                          keyboardType: TextInputType.number,
                                          onChanged: (_) {
                                            _breakupManual = true;
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                    SizedBox(
                                      width: 160,
                                      child: TextField(
                                        controller: _personal,
                                        decoration: const InputDecoration(labelText: 'Special allowance', isDense: true),
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) {
                                          _breakupManual = true;
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Leave breakdown at defaults for auto-split from gross. The Advance bonus in the breakdown is the payslip “medical” column; the separate Advance bonus below adjusts take-home.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (pv != null)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black12),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey.shade100,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Preview (same as server on Save)', style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 8),
                                  Text('CTC ${UiFormatters.inr(pv.calc.ctc)}', style: Theme.of(context).textTheme.bodyMedium),
                                  Text(
                                    'Net Salary / Take Home ${UiFormatters.inr(pv.takeHome)}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'PT ${UiFormatters.inr(pv.ptMonthly)}'
                                    '${pv.calc.pfEmp > 0 ? ' · PF ${UiFormatters.inr(pv.calc.pfEmp)}' : ''}'
                                    '${pv.calc.esicEmp > 0 ? ' · ESIC ${UiFormatters.inr(pv.calc.esicEmp)}' : ''}'
                                    '${pv.tds > 0 ? ' · TDS ${UiFormatters.inr(pv.tds)}' : ''}'
                                    '${pv.advanceBonus > 0 ? ' · Adv +${UiFormatters.inr(pv.advanceBonus)}' : ''}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Checkbox(
                              value: _pfEligible,
                              onChanged: (v) {
                                _pfManual = true;
                                setState(() => _pfEligible = v ?? false);
                              },
                            ),
                            const Text('PF eligible'),
                            const SizedBox(width: 16),
                            Checkbox(
                              value: _esicEligible,
                              onChanged: (v) {
                                _esicManual = true;
                                setState(() => _esicEligible = v ?? false);
                              },
                            ),
                            const Text('ESIC eligible'),
                          ],
                        ),
                        Text(
                          'ESIC follows policy when Basic+DA is within the ceiling; use the checkbox to override.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _pt,
                                decoration: const InputDecoration(labelText: 'PT (monthly)', isDense: true),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _tds,
                                decoration: const InputDecoration(labelText: 'TDS (monthly)', isDense: true),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _advance,
                                decoration: const InputDecoration(labelText: 'Advance bonus', isDense: true),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newStart,
                          decoration: InputDecoration(
                            labelText: 'New master effective start *',
                            suffixIcon: IconButton(icon: const Icon(Icons.calendar_today), onPressed: () => _pickDate(_newStart)),
                          ),
                          onChanged: (s) {
                            if (s.length >= 10) {
                              final pe = _dayBeforeYmd(s.substring(0, 10));
                              if (pe != null) _prevEnd.text = pe;
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _prevEnd,
                          decoration: InputDecoration(
                            labelText: 'Current master effective end *',
                            suffixIcon: IconButton(icon: const Icon(Icons.calendar_today), onPressed: () => _pickDate(_prevEnd)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reason,
                          decoration: const InputDecoration(labelText: 'Reason for change *'),
                        ),
                      ],
                    ],
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Update salary credit details. Saving here does not create a new payroll master row.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: _bankHolder, decoration: const InputDecoration(labelText: 'Account holder name *')),
                      const SizedBox(height: 8),
                      TextField(controller: _bankName, decoration: const InputDecoration(labelText: 'Bank name')),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bankAcct,
                        decoration: const InputDecoration(labelText: 'Account number *'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bankIfsc,
                        decoration: const InputDecoration(labelText: 'IFSC *'),
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 11,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
                const Spacer(),
                if (_tabs.index == 1)
                  FilledButton(onPressed: _saving ? null : _saveBank, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save bank')),
                if (_tabs.index == 0 && _payrollMode == 'private')
                  FilledButton(
                    onPressed: _saving ? null : _saveStructure,
                    child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save payroll'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
