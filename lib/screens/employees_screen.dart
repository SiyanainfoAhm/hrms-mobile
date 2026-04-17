import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../widgets/app_drawer.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.app});

  final AppState app;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  /// Aligns with web: preboarding | current | past (notice rows appear under Past).
  String tab = 'preboarding';
  int _listGen = 0;

  String _todayYmdUtc() {
    final n = DateTime.now().toUtc();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String _dolYmd(Map<String, dynamic> r) {
    final v = r['date_of_leaving'];
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : '';
  }

  String _dojYmd(Map<String, dynamic> r) {
    final v = r['date_of_joining'];
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : '';
  }

  bool _isOnNotice(Map<String, dynamic> r) {
    if ((r['employment_status'] ?? '').toString() != 'current') return false;
    final dol = _dolYmd(r);
    if (dol.isEmpty) return false;
    return dol.compareTo(_todayYmdUtc()) > 0;
  }

  String _pastStatusLabel(Map<String, dynamic> r) {
    final dol = _dolYmd(r);
    if (dol.isEmpty) return 'Past';
    return dol.compareTo(_todayYmdUtc()) > 0 ? 'Notice' : 'Past';
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red.shade800 : null),
    );
  }

  String _errMessage(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final u = widget.app.user;
    if (u == null || !u.isSuperAdmin) return;
    final id = (row['id'] ?? '').toString();
    final name = (row['name'] ?? row['email'] ?? id).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete employee'),
        content: Text('Permanently remove $name? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await RpcService().employeeDeleteSuper(actorUserId: u.id, targetUserId: id);
      if (!mounted) return;
      _snack('Employee deleted');
      setState(() => _listGen++);
    } catch (e) {
      _snack(_errMessage(e), err: true);
    }
  }

  Future<String?> _pickDateYmd(String title, String initialYmd) async {
    final parts = initialYmd.split('-');
    final y = parts.length > 2 ? int.tryParse(parts[0]) ?? DateTime.now().year : DateTime.now().year;
    final m = parts.length > 2 ? int.tryParse(parts[1]) ?? 1 : 1;
    final d = parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1;
    final initial = DateTime.utc(y, m, d);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null) return null;
    final u = picked.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
  }

  Future<void> _convertToCurrent(Map<String, dynamic> row) async {
    final u = widget.app.user;
    if (u == null) return;
    final id = (row['id'] ?? '').toString();
    final initial = _dojYmd(row).isNotEmpty ? _dojYmd(row) : _todayYmdUtc();
    final ymd = await _pickDateYmd('Date of joining', initial);
    if (ymd == null) return;
    try {
      await RpcService().employeeManagementAction(
        actorUserId: u.id,
        targetUserId: id,
        action: 'convert_current',
        dateYyyyMmDd: ymd,
      );
      if (!mounted) return;
      _snack('Moved to Current');
      setState(() => _listGen++);
    } catch (e) {
      _snack(_errMessage(e), err: true);
    }
  }

  Future<void> _convertToPast(Map<String, dynamic> row) async {
    final u = widget.app.user;
    if (u == null) return;
    final id = (row['id'] ?? '').toString();
    final ymd = await _pickDateYmd('Last working date', _todayYmdUtc());
    if (ymd == null) return;
    try {
      await RpcService().employeeManagementAction(
        actorUserId: u.id,
        targetUserId: id,
        action: 'convert_past',
        dateYyyyMmDd: ymd,
      );
      if (!mounted) return;
      _snack('Updated');
      setState(() => _listGen++);
    } catch (e) {
      _snack(_errMessage(e), err: true);
    }
  }

  Future<void> _revokeNotice(Map<String, dynamic> row) async {
    final u = widget.app.user;
    if (u == null) return;
    final id = (row['id'] ?? '').toString();
    try {
      await RpcService().employeeManagementAction(
        actorUserId: u.id,
        targetUserId: id,
        action: 'revoke_notice',
      );
      if (!mounted) return;
      _snack('Notice revoked');
      setState(() => _listGen++);
    } catch (e) {
      _snack(_errMessage(e), err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final companyId = u?.companyId ?? '';
    final canManage = u?.isManagerial == true;
    final superAdmin = u?.isSuperAdmin == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Employees')),
      drawer: AppDrawer(app: widget.app),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: !canManage
            ? const Center(child: Text('Forbidden'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'preboarding', label: Text('Preboarding')),
                      ButtonSegment(value: 'current', label: Text('Current')),
                      ButtonSegment(value: 'past', label: Text('Past')),
                    ],
                    selected: {tab},
                    onSelectionChanged: (s) => setState(() => tab = s.first),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      key: ValueKey('$companyId|$tab|$_listGen'),
                      future: RpcService().employeesList(companyId, tab),
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(child: Text('Loading…'));
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Text(
                              'Error: ${snap.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        final rows = snap.data ?? const <Map<String, dynamic>>[];
                        if (rows.isEmpty) {
                          return const Center(child: Text('No employees.'));
                        }
                        return ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            final phone = (r['phone'] ?? '—').toString();
                            final des = (r['designation'] ?? '').toString();
                            final subtitle = tab == 'past'
                                ? '${r['email']}\n${_pastStatusLabel(r)} · LWD: ${_dolYmd(r).isEmpty ? '—' : _dolYmd(r)}'
                                : '${r['email']}\n${des.isEmpty ? phone : '$des · $phone'}';

                            final uid = (r['id'] ?? '').toString();
                            final trailingW = tab == 'preboarding'
                                ? (superAdmin ? 240.0 : 200.0)
                                : (superAdmin ? 168.0 : 148.0);

                            return ListTile(
                              title: Text((r['name'] ?? '—').toString()),
                              subtitle: Text(subtitle),
                              isThreeLine: true,
                              trailing: SizedBox(
                                width: trailingW,
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    if (tab == 'preboarding')
                                      TextButton(
                                        onPressed: () => _convertToCurrent(r),
                                        child: const Text('Current', style: TextStyle(fontSize: 12)),
                                      ),
                                    if (tab == 'preboarding' && uid.isNotEmpty)
                                      TextButton(
                                        onPressed: () => context.push('/employees/invite/$uid'),
                                        child: const Text('Invite', style: TextStyle(fontSize: 12)),
                                      ),
                                    if (tab == 'current')
                                      TextButton(
                                        onPressed: () => _convertToPast(r),
                                        child: const Text('Past', style: TextStyle(fontSize: 12)),
                                      ),
                                    if (tab == 'past' && _isOnNotice(r))
                                      TextButton(
                                        onPressed: () => _revokeNotice(r),
                                        child: const Text('Revoke', style: TextStyle(fontSize: 12)),
                                      ),
                                    if (superAdmin)
                                      TextButton(
                                        onPressed: () => _confirmDelete(r),
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text('Delete', style: TextStyle(fontSize: 12)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
