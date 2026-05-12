import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../services/rpc_service.dart';
import '../theme/tokens.dart';
import '../ui/empty_state.dart';
import '../ui/formatters.dart';
import '../ui/hrms_card.dart';
import '../ui/status_chip.dart';
import '../widgets/app_drawer.dart';

class ReimbursementsScreen extends StatefulWidget {
  const ReimbursementsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<ReimbursementsScreen> createState() => _ReimbursementsScreenState();
}

class _ReimbursementsScreenState extends State<ReimbursementsScreen> {
  int _listEpoch = 0;

  Future<void> _openCreate(
    BuildContext context, {
    required String companyId,
    required String actorUserId,
    required bool isAdmin,
    required List<Map<String, dynamic>> employees,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateReimbursementSheet(
        isAdmin: isAdmin,
        employees: employees,
        actorUserId: actorUserId,
        onCreate: (targetUserId, category, amount, claimDateYmd, desc, attachment) async {
          await RpcService().reimbursementCreate(
            companyId: companyId,
            userId: targetUserId,
            actorUserId: actorUserId,
            category: category,
            amount: amount,
            claimDateYmd: claimDateYmd,
            description: desc,
            attachmentUrl: attachment,
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
      appBar: AppBar(title: const Text('Reimbursements')),
      drawer: AppDrawer(app: widget.app),
      floatingActionButton: (companyId.isEmpty || userId.isEmpty)
          ? null
          : FloatingActionButton(
              onPressed: () async {
                var employees = const <Map<String, dynamic>>[];
                if (isAdmin) {
                  employees = await RpcService().employeesList(companyId, 'current');
                }
                if (!context.mounted) return;
                await _openCreate(
                  context,
                  companyId: companyId,
                  actorUserId: userId,
                  isAdmin: isAdmin,
                  employees: employees,
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
                subtitle: 'Ask your admin to assign you to a company to submit reimbursements.',
                icon: Icons.business_outlined,
              )
            : FutureBuilder(
                key: ValueKey(_listEpoch),
                future: RpcService().reimbursementsList(companyId: companyId, userId: userId, scope: scope),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return EmptyState(
                      title: 'Could not load reimbursements',
                      subtitle: snap.error.toString(),
                      icon: Icons.error_outline,
                    );
                  }
                  final rows = (snap.data ?? const <Map<String, dynamic>>[]);
                  if (rows.isEmpty) {
                    return EmptyState(
                      title: 'No reimbursements yet',
                      subtitle: isAdmin
                          ? 'No employee reimbursements found.'
                          : 'Tap + to submit your first reimbursement.',
                      icon: Icons.receipt_long_outlined,
                    );
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final status = (r['status'] ?? '').toString();
                      final canDecide = isAdmin && status == 'pending';
                      final py = r['payroll_year'];
                      final pm = r['payroll_month'];
                      final payrollLabel = (py != null && pm != null) ? 'Payroll: $py-${pm.toString().padLeft(2, '0')}' : null;
                      return HrmsCard(
                        title: (r['category'] ?? '').toString(),
                        subtitle: isAdmin ? (r['employee_name'] ?? '—').toString() : 'Claimed by you',
                        trailing: StatusChip(value: status),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(UiFormatters.indianDate(r['claim_date']), style: Theme.of(context).textTheme.bodySmall),
                                Text(
                                  UiFormatters.inr(r['amount']),
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                ),
                              ],
                            ),
                            if (payrollLabel != null) ...[
                              const SizedBox(height: 6),
                              Text(payrollLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                            ],
                            if ((r['description'] ?? '').toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text((r['description'] ?? '').toString(), style: Theme.of(context).textTheme.bodySmall),
                            ],
                            if (canDecide) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        await RpcService().reimbursementDecide(
                                          companyId: companyId,
                                          approverUserId: userId,
                                          reimbursementId: r['id'].toString(),
                                          status: 'approved',
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
                                        await RpcService().reimbursementDecide(
                                          companyId: companyId,
                                          approverUserId: userId,
                                          reimbursementId: r['id'].toString(),
                                          status: 'rejected',
                                          rejectionReason: 'Rejected from mobile',
                                        );
                                        if (mounted) setState(() => _listEpoch++);
                                      },
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        await RpcService().reimbursementDecide(
                                          companyId: companyId,
                                          approverUserId: userId,
                                          reimbursementId: r['id'].toString(),
                                          status: 'paid',
                                        );
                                        if (mounted) setState(() => _listEpoch++);
                                      },
                                      child: const Text('Paid'),
                                    ),
                                  ),
                                ],
                              )
                            ]
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

class _CreateReimbursementSheet extends StatefulWidget {
  const _CreateReimbursementSheet({
    required this.isAdmin,
    required this.employees,
    required this.actorUserId,
    required this.onCreate,
  });
  final bool isAdmin;
  final List<Map<String, dynamic>> employees;
  final String actorUserId;
  final Future<void> Function(
    String targetUserId,
    String category,
    num amount,
    String claimDateYmd,
    String description,
    String attachmentUrl,
  ) onCreate;

  @override
  State<_CreateReimbursementSheet> createState() => _CreateReimbursementSheetState();
}

class _CreateReimbursementSheetState extends State<_CreateReimbursementSheet> {
  final _formKey = GlobalKey<FormState>();
  String? targetUserId;
  final category = TextEditingController();
  final amount = TextEditingController();
  final claimDate = TextEditingController();
  final desc = TextEditingController();
  final attachment = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isAdmin) {
      targetUserId = widget.actorUserId;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null) return;
    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    claimDate.text = '$y-$m-$d';
  }

  @override
  void dispose() {
    category.dispose();
    amount.dispose();
    claimDate.dispose();
    desc.dispose();
    attachment.dispose();
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
                        child: Text(
                          'New reimbursement',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
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
                        TextFormField(
                          controller: category,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Category is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: amount,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixIcon: Icon(Icons.currency_rupee),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = num.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) return 'Enter a valid amount';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: claimDate,
                          readOnly: true,
                          onTap: busy ? null : _pickDate,
                          decoration: InputDecoration(
                            labelText: 'Claim date',
                            prefixIcon: const Icon(Icons.event_outlined),
                            hintText: 'YYYY-MM-DD',
                            suffixText: claimDate.text.trim().isEmpty ? null : UiFormatters.indianDate(claimDate.text.trim()),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Claim date is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: desc,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                          maxLines: 2,
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Description is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: attachment,
                          decoration: const InputDecoration(
                            labelText: 'Attachment URL',
                            prefixIcon: Icon(Icons.link_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Attachment URL is required' : null,
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
                                  final c = category.text.trim();
                                  final a = num.tryParse(amount.text.trim())!;
                                  final dt = claimDate.text.trim();
                                  final d = desc.text.trim();
                                  final att = attachment.text.trim();
                                  setState(() => busy = true);
                                  final tid = targetUserId ?? widget.actorUserId;
                                  await widget.onCreate(tid, c, a, dt, d, att);
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
