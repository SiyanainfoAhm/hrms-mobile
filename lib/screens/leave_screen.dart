import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../services/rpc_service.dart';
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
    required bool isAdmin,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateLeaveSheet(
        isAdmin: isAdmin,
        employees: employees,
        actorUserId: actorUserId,
        leaveTypes: leaveTypes,
        onCreate: (targetUserId, leaveTypeId, startYmd, endYmd, days, reason) async {
          await svc.leaveRequestCreate(
            companyId: companyId,
            userId: targetUserId,
            actorUserId: actorUserId,
            leaveTypeId: leaveTypeId,
            startDateYmd: startYmd,
            endDateYmd: endYmd,
            totalDays: days,
            reason: reason,
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
    required this.isAdmin,
    required this.employees,
    required this.actorUserId,
    required this.leaveTypes,
    required this.onCreate,
  });
  final bool isAdmin;
  final List<Map<String, dynamic>> employees;
  final String actorUserId;
  final List<Map<String, dynamic>> leaveTypes;
  final Future<void> Function(String targetUserId, String leaveTypeId, String startYmd, String endYmd, num days, String? reason) onCreate;

  @override
  State<_CreateLeaveSheet> createState() => _CreateLeaveSheetState();
}

class _CreateLeaveSheetState extends State<_CreateLeaveSheet> {
  final _formKey = GlobalKey<FormState>();
  String? typeId;
  String? targetUserId;
  final start = TextEditingController();
  final end = TextEditingController();
  final days = TextEditingController(text: '1');
  final reason = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isAdmin) {
      targetUserId = widget.actorUserId;
    }
  }

  int? _calcInclusiveDays() {
    final s = DateTime.tryParse(start.text.trim());
    final e = DateTime.tryParse(end.text.trim());
    if (s == null || e == null) return null;
    final ss = DateTime(s.year, s.month, s.day);
    final ee = DateTime(e.year, e.month, e.day);
    if (ee.isBefore(ss)) return null;
    return ee.difference(ss).inDays + 1;
  }

  void _syncDays() {
    final d = _calcInclusiveDays();
    if (d == null) return;
    days.text = d.toString();
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
    _syncDays();
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
    _syncDays();
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    days.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
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
                      children: [
                        if (widget.isAdmin) ...[
                          DropdownButtonFormField<String>(
                            value: targetUserId,
                            items: widget.employees
                                .map((e) => DropdownMenuItem(
                                      value: e['id']?.toString(),
                                      child: Text((e['name'] ?? e['email'] ?? 'Employee').toString()),
                                    ))
                                .where((it) => (it.value ?? '').toString().isNotEmpty)
                                .toList(),
                            onChanged: busy ? null : (v) => setState(() => targetUserId = v),
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
                              .map((t) => DropdownMenuItem(
                                    value: t['id'].toString(),
                                    child: Text((t['name'] ?? '').toString()),
                                  ))
                              .toList(),
                          onChanged: busy ? null : (v) => setState(() => typeId = v),
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
                          validator: (v) => (v ?? '').trim().isEmpty ? 'End date is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: days,
                          decoration: const InputDecoration(
                            labelText: 'Total days',
                            prefixIcon: Icon(Icons.timelapse_outlined),
                          ),
                          readOnly: true,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final d = num.tryParse((v ?? '').trim());
                            if (d == null || d <= 0) return 'Enter total days';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
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
                                  final s = start.text.trim();
                                  final e = end.text.trim();
                                  final d = num.tryParse(days.text.trim()) ?? 1;
                                  setState(() => busy = true);
                                  final tid = targetUserId ?? widget.actorUserId;
                                  await widget.onCreate(
                                    tid,
                                    typeId!,
                                    s,
                                    e,
                                    d,
                                    reason.text.trim().isEmpty ? null : reason.text.trim(),
                                  );
                                  if (context.mounted) Navigator.pop(context);
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

