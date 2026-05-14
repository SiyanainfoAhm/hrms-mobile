import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/leave_booking_calc.dart';
import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/empty_state.dart';
import '../ui/formatters.dart';
import '../ui/hrms_card.dart';
import '../ui/status_chip.dart';
import '../widgets/app_drawer.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, required this.app});

  final AppState app;

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  int _listEpoch = 0;

  Future<void> _openCreate(
    BuildContext context, {
    required String companyId,
    required String actorUserId,
    required List<Map<String, dynamic>> leaveTypes,
    required RpcService svc,
    required List<Map<String, dynamic>> employees,
    required List<Map<String, dynamic>> holidays,
    required bool isAdmin,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateLeaveSheet(
        companyId: companyId,
        svc: svc,
        holidays: holidays,
        isAdmin: isAdmin,
        employees: employees,
        actorUserId: actorUserId,
        leaveTypes: leaveTypes,
        onCreate: (targetUserId, leaveTypeId, startYmd, endYmd, days, reason, isHalfDay) async {
          await svc.leaveRequestCreate(
            companyId: companyId,
            userId: targetUserId,
            actorUserId: actorUserId,
            leaveTypeId: leaveTypeId,
            startDateYmd: startYmd,
            endDateYmd: endYmd,
            totalDays: days,
            reason: reason,
            isHalfDay: isHalfDay,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final companyId = u?.companyId ?? '';
    final userId = u?.id ?? '';
    final isAdmin = u?.isManagerial == true;
    final scope = isAdmin ? 'all' : 'me';

    return Scaffold(
      appBar: AppBar(title: const Text('Leave')),
      drawer: AppDrawer(app: widget.app),
      floatingActionButton: (companyId.isEmpty || userId.isEmpty)
          ? null
          : FloatingActionButton(
              onPressed: () async {
                final svc = RpcService();
                final types = await svc.leaveTypesList(companyId);
                final holidays = await svc.holidaysList(companyId);
                var employees = const <Map<String, dynamic>>[];
                if (isAdmin) {
                  employees = await svc.employeesList(companyId, 'current');
                }
                if (!context.mounted) return;
                await _openCreate(
                  context,
                  companyId: companyId,
                  actorUserId: userId,
                  leaveTypes: types,
                  svc: svc,
                  employees: employees,
                  holidays: holidays,
                  isAdmin: isAdmin,
                );
                if (mounted) setState(() => _listEpoch++);
              },
              child: const Icon(Icons.add),
            ),
      body: Padding(
        padding: const EdgeInsets.all(HrmsTokens.s4),
        child: (companyId.isEmpty || userId.isEmpty)
            ? const EmptyState(
                title: 'No company assigned',
                subtitle: 'Ask your admin to assign you to a company to request leave.',
                icon: Icons.business_outlined,
              )
            : FutureBuilder(
                key: ValueKey(_listEpoch),
                future: RpcService().leaveRequestsList(companyId: companyId, userId: userId, scope: scope),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) {
                    return EmptyState(
                      title: 'Could not load leave requests',
                      subtitle: snap.error.toString(),
                      icon: Icons.error_outline,
                    );
                  }
                  final rows = (snap.data ?? const <Map<String, dynamic>>[]);
                  if (rows.isEmpty) {
                    return EmptyState(
                      title: 'No leave requests yet',
                      subtitle: isAdmin
                          ? 'No employee leave requests found.'
                          : 'Tap + to request your first leave.',
                      icon: Icons.beach_access_outlined,
                    );
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final status = (r['status'] ?? '').toString();
                      final canCancel = !isAdmin && status == 'pending';
                      final canDecide = isAdmin && status == 'pending';
                      final start = UiFormatters.indianDate(r['start_date']);
                      final end = UiFormatters.indianDate(r['end_date']);
                      final days = (r['total_days'] ?? '—').toString();
                      return HrmsCard(
                        title: (r['leave_type_name'] ?? '').toString(),
                        subtitle: isAdmin ? (r['employee_name'] ?? '—').toString() : 'Requested by you',
                        trailing: StatusChip(value: status),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$start → $end', style: Theme.of(context).textTheme.bodySmall),
                                Text('$days day(s)', style: const TextStyle(fontWeight: FontWeight.w900)),
                              ],
                            ),
                            if (r['paid_days'] != null || r['unpaid_days'] != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Paid: ${r['paid_days'] ?? '—'} · Unpaid: ${r['unpaid_days'] ?? '—'}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                              ),
                            ],
                            if ((r['reason'] ?? '').toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text((r['reason'] ?? '').toString(), style: Theme.of(context).textTheme.bodySmall),
                            ],
                            if (canDecide) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        await RpcService().leaveRequestDecide(
                                          companyId: companyId,
                                          approverUserId: userId,
                                          requestId: r['id'].toString(),
                                          decision: 'approved',
                                        );
                                        if (mounted) setState(() => _listEpoch++);
                                      },
                                      child: const Text('Approve'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        await RpcService().leaveRequestDecide(
                                          companyId: companyId,
                                          approverUserId: userId,
                                          requestId: r['id'].toString(),
                                          decision: 'rejected',
                                          rejectionReason: 'Rejected from mobile',
                                        );
                                        if (mounted) setState(() => _listEpoch++);
                                      },
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (canCancel) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await RpcService().leaveRequestCancel(
                                      companyId: companyId,
                                      userId: userId,
                                      requestId: r['id'].toString(),
                                    );
                                    if (mounted) setState(() => _listEpoch++);
                                  },
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: const Text('Cancel request'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _CreateLeaveSheet extends StatefulWidget {
  const _CreateLeaveSheet({
    required this.companyId,
    required this.svc,
    required this.holidays,
    required this.isAdmin,
    required this.employees,
    required this.actorUserId,
    required this.leaveTypes,
    required this.onCreate,
  });

  final String companyId;
  final RpcService svc;
  final List<Map<String, dynamic>> holidays;
  final bool isAdmin;
  final List<Map<String, dynamic>> employees;
  final String actorUserId;
  final List<Map<String, dynamic>> leaveTypes;
  final Future<void> Function(String targetUserId, String leaveTypeId, String startYmd, String endYmd, num days, String? reason, bool isHalfDay) onCreate;

  @override
  State<_CreateLeaveSheet> createState() => _CreateLeaveSheetState();
}

class _CreateLeaveSheetState extends State<_CreateLeaveSheet> {
  final _formKey = GlobalKey<FormState>();
  String? typeId;
  String? targetUserId;
  final start = TextEditingController();
  final end = TextEditingController();
  final reason = TextEditingController();
  bool busy = false;
  /// Single calendar day, non-HL: optional 0.5 day (same rules as web Approvals leave form).
  bool _singleDayHalfDay = false;
  List<Map<String, dynamic>> _overlapRows = [];
  String? _employeeDivisionId;

  String _leaveCode() {
    for (final x in widget.leaveTypes) {
      if (x['id']?.toString() == typeId) return (x['code'] ?? '').toString();
    }
    return '';
  }

  bool _singleDayHalfDayEligible() {
    if (typeId == null) return false;
    final s = start.text.trim();
    final e = end.text.trim();
    if (s.isEmpty || e.isEmpty || s != e) return false;
    return _leaveCode().toUpperCase() != 'HL';
  }

  /// Same rounding as web `fmtDays` in ApprovalsContent (`Math.round(n * 2) / 2`).
  String _fmtDays(num n) {
    if (!n.isFinite) return '0';
    final rounded = (n * 2).round() / 2.0;
    if ((rounded * 2).round() % 2 == 0) return rounded.toInt().toString();
    return rounded.toStringAsFixed(1);
  }

  LeaveBookingSummary _computeSummary() {
    final s = start.text.trim();
    final e = end.text.trim();
    final tid = targetUserId ?? widget.actorUserId;
    if (tid.isEmpty || typeId == null || s.isEmpty || e.isEmpty) {
      return LeaveBookingSummary(
        calendarSpanDays: 0,
        weekendDaysExcluded: 0,
        holidayDaysExcluded: 0,
        workingDaysInRange: 0,
        chargeableDays: 0,
        overlapError: null,
      );
    }
    final code = _leaveCode();
    final half = _singleDayHalfDayEligible() && _singleDayHalfDay && code.toUpperCase() != 'HL';
    return computeLeaveBookingSummary(
      startYmd: s,
      endYmd: e,
      holidays: widget.holidays,
      employeeDivisionId: _employeeDivisionId,
      existingLeaves: _overlapRows,
      leaveTypeCodeUpper: code,
      isHalfDay: half,
    );
  }

  Future<void> _reloadOverlap() async {
    final tid = targetUserId ?? widget.actorUserId;
    if (tid.isEmpty) {
      setState(() {
        _overlapRows = [];
        _employeeDivisionId = null;
      });
      return;
    }
    try {
      final map = await widget.svc.leaveOverlapContext(
        companyId: widget.companyId,
        actorUserId: widget.actorUserId,
        targetUserId: tid,
      );
      if (!mounted) return;
      setState(() {
        _overlapRows = overlapRequestsFromJson(map);
        _employeeDivisionId = employeeDivisionFromOverlapJson(map);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _overlapRows = [];
        _employeeDivisionId = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isAdmin) {
      targetUserId = widget.actorUserId;
    } else if (widget.employees.isNotEmpty) {
      targetUserId = widget.employees.first['id']?.toString();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reloadOverlap();
      if (mounted) setState(() {});
    });
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null) return;
    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    start.text = '$y-$m-$d';
    if (end.text.trim().isEmpty) end.text = start.text;
    if (mounted) {
      setState(() {
        if (!_singleDayHalfDayEligible()) _singleDayHalfDay = false;
      });
    }
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final init = DateTime.tryParse(start.text.trim()) ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: init,
    );
    if (picked == null) return;
    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    end.text = '$y-$m-$d';
    if (mounted) {
      setState(() {
        if (!_singleDayHalfDayEligible()) _singleDayHalfDay = false;
      });
    }
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : null),
    );
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final summary = _computeSummary();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPad),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Request leave', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        onPressed: busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.isAdmin) ...[
                          DropdownButtonFormField<String>(
                            value: targetUserId,
                            items: widget.employees
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e['id']?.toString(),
                                    child: Text((e['name'] ?? e['email'] ?? 'Employee').toString()),
                                  ),
                                )
                                .where((it) => (it.value ?? '').toString().isNotEmpty)
                                .toList(),
                            onChanged: busy
                                ? null
                                : (v) async {
                                    setState(() => targetUserId = v);
                                    await _reloadOverlap();
                                    if (!mounted) return;
                                    setState(() {
                                      if (!_singleDayHalfDayEligible()) _singleDayHalfDay = false;
                                    });
                                  },
                            decoration: const InputDecoration(
                              labelText: 'Employee',
                              prefixIcon: Icon(Icons.person_search_outlined),
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Select an employee' : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        DropdownButtonFormField<String>(
                          value: typeId,
                          items: widget.leaveTypes
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t['id'].toString(),
                                  child: Text((t['name'] ?? '').toString()),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                    typeId = v;
                                    if (!_singleDayHalfDayEligible()) _singleDayHalfDay = false;
                                  }),
                          decoration: const InputDecoration(
                            labelText: 'Leave type',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Select a leave type' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: start,
                          readOnly: true,
                          onTap: busy ? null : _pickStart,
                          decoration: InputDecoration(
                            labelText: 'Start date',
                            hintText: 'YYYY-MM-DD',
                            prefixIcon: const Icon(Icons.event_outlined),
                            suffixText: start.text.trim().isEmpty ? null : UiFormatters.indianDate(start.text.trim()),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Start date is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: end,
                          readOnly: true,
                          onTap: busy ? null : _pickEnd,
                          decoration: InputDecoration(
                            labelText: 'End date',
                            hintText: 'YYYY-MM-DD',
                            prefixIcon: const Icon(Icons.event_available_outlined),
                            suffixText: end.text.trim().isEmpty ? null : UiFormatters.indianDate(end.text.trim()),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return 'End date is required';
                            final s = start.text.trim();
                            final e = (v ?? '').trim();
                            if (s.isNotEmpty && e.compareTo(s) < 0) return 'End must be on or after start';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        if (_singleDayHalfDayEligible()) ...[
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Half day (0.5) — single date only; leave unchecked for a full day'),
                            value: _singleDayHalfDay,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => _singleDayHalfDay = v ?? false),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (start.text.trim().isNotEmpty && end.text.trim().isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Leave calculation',
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Calendar span: ${summary.calendarSpanDays} day(s) · '
                                  'Excludes ${summary.weekendDaysExcluded} weekend · '
                                  '${summary.holidayDaysExcluded} holiday',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Charged leave: ${_fmtDays(summary.chargeableDays)} '
                                  '${summary.chargeableDays == 1 || summary.chargeableDays == 0.5 ? 'day' : 'days'}',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (summary.overlapError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    summary.overlapError!,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red.shade800),
                                  ),
                                ] else if (summary.calendarSpanDays > 0 && summary.workingDaysInRange <= 0) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'No chargeable leave days in this range (weekends and holidays are excluded).',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red.shade800),
                                  ),
                                ] else if (_singleDayHalfDayEligible() && _singleDayHalfDay && summary.workingDaysInRange != 1) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Half day is only available on a single working day (not on a weekend or holiday).',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red.shade800),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: reason,
                          decoration: const InputDecoration(
                            labelText: 'Reason (optional)',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final ok = _formKey.currentState?.validate() ?? false;
                                  if (!ok) return;
                                  final sum = _computeSummary();
                                  if (sum.overlapError != null) {
                                    _snack(sum.overlapError!, err: true);
                                    return;
                                  }
                                  // Same order as web `leaveErrors.booking` (ApprovalsContent).
                                  if (sum.calendarSpanDays > 0 && sum.workingDaysInRange <= 0) {
                                    _snack(
                                      'No chargeable leave days in this range (weekends and holidays are excluded).',
                                      err: true,
                                    );
                                    return;
                                  }
                                  if (_singleDayHalfDayEligible() && _singleDayHalfDay && sum.workingDaysInRange != 1) {
                                    _snack(
                                      'Half day is only available on a single working day (not on a weekend or holiday).',
                                      err: true,
                                    );
                                    return;
                                  }
                                  if (sum.chargeableDays <= 0) {
                                    _snack(
                                      'No chargeable leave days in this range (weekends and holidays are excluded).',
                                      err: true,
                                    );
                                    return;
                                  }
                                  final s = start.text.trim();
                                  final e = end.text.trim();
                                  setState(() => busy = true);
                                  final tid = targetUserId ?? widget.actorUserId;
                                  try {
                                    await widget.onCreate(
                                      tid,
                                      typeId!,
                                      s,
                                      e,
                                      sum.chargeableDays,
                                      reason.text.trim().isEmpty ? null : reason.text.trim(),
                                      _singleDayHalfDayEligible() && _singleDayHalfDay,
                                    );
                                    if (context.mounted) Navigator.pop(context);
                                  } on PostgrestException catch (ex) {
                                    _snack(ex.message.trim().isNotEmpty ? ex.message : 'Request failed', err: true);
                                  } catch (ex) {
                                    _snack(ex.toString(), err: true);
                                  } finally {
                                    if (mounted) setState(() => busy = false);
                                  }
                                },
                          child: Text(busy ? 'Creating…' : 'Create'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
