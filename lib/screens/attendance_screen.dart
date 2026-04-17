import 'package:flutter/material.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/empty_state.dart';
import '../ui/hrms_card.dart';
import '../ui/formatters.dart';
import '../widgets/app_drawer.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.app});
  final AppState app;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _rpc = RpcService();

  late DateTime _start = DateTime.now();
  late DateTime _end = DateTime.now();

  bool _loading = true;
  Object? _err;
  bool _hasEmployee = true;

  // Managerial only: HRMS_users.id filter; empty = all employees.
  String _employeeUserId = '';
  bool _employeesLoading = false;
  List<Map<String, dynamic>> _employees = [];

  List<Map<String, dynamic>> _rows = [];

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadEmployeesIfNeeded();
    _load();
  }

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.user?.role != widget.app.user?.role) {
      _loadEmployeesIfNeeded();
      _load();
    }
  }

  Future<void> _loadEmployeesIfNeeded() async {
    final u = widget.app.user;
    if (u?.isManagerial != true) return;
    final cid = u?.companyId ?? '';
    if (cid.isEmpty) return;
    setState(() => _employeesLoading = true);
    try {
      final rows = await _rpc.employeesList(cid, 'current');
      setState(() => _employees = rows);
    } catch (_) {
      if (mounted) setState(() => _employees = []);
    } finally {
      if (mounted) setState(() => _employeesLoading = false);
    }
  }

  Future<void> _load() async {
    final u = widget.app.user;
    final cid = u?.companyId ?? '';
    if (u == null || cid.isEmpty) {
      setState(() {
        _loading = false;
        _err = null;
        _rows = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final start = _ymd(_start);
      final end = _ymd(_end);
      if (u.isManagerial) {
        final rows = await _rpc.attendanceCompanyRange(
          companyId: cid,
          startDateYmd: start,
          endDateYmd: end,
          employeeUserId: _employeeUserId.isEmpty ? null : _employeeUserId,
        );
        setState(() {
          _rows = rows;
          _hasEmployee = true;
        });
      } else {
        final res = await _rpc.attendanceMeRange(
          companyId: cid,
          userId: u.id,
          startDateYmd: start,
          endDateYmd: end,
        );
        setState(() {
          _rows = (res['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _hasEmployee = res['hasEmployee'] == true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e;
        _rows = [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _start = picked;
      if (_end.isBefore(_start)) _end = picked;
    });
    await _load();
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _end = picked;
      if (_end.isBefore(_start)) _start = picked;
    });
    await _load();
  }

  String _fmtTime(dynamic iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso.toString());
    if (dt == null) return '—';
    final d = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final isManagerial = u?.isManagerial == true;
    final showEmployee = isManagerial && _employeeUserId.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(isManagerial ? 'Company attendance' : 'My attendance'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: AppDrawer(app: widget.app),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(HrmsTokens.s4),
          children: [
            HrmsCard(
              title: 'Filters',
              subtitle: 'Dates use the IST calendar (same as web).',
              trailing: const Icon(Icons.tune, color: HrmsTokens.primary),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _pickStart,
                          child: Text('From: ${UiFormatters.indianDate(_ymd(_start))}'),
                        ),
                      ),
                      const SizedBox(width: HrmsTokens.s3),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _pickEnd,
                          child: Text('To: ${UiFormatters.indianDate(_ymd(_end))}'),
                        ),
                      ),
                    ],
                  ),
                  if (isManagerial) ...[
                    const SizedBox(height: HrmsTokens.s3),
                    DropdownButtonFormField<String>(
                      value: _employeeUserId,
                      decoration: const InputDecoration(labelText: 'Employee'),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_employeesLoading ? 'Loading…' : 'All employees'),
                        ),
                        ..._employees.map((e) {
                          final id = (e['id'] ?? '').toString();
                          final name = (e['name'] ?? '').toString().trim();
                          final email = (e['email'] ?? '').toString();
                          return DropdownMenuItem(
                            value: id,
                            child: Text(name.isNotEmpty ? name : email),
                          );
                        }),
                      ],
                      onChanged: _employeesLoading
                          ? null
                          : (v) async {
                              setState(() => _employeeUserId = v ?? '');
                              await _load();
                            },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: HrmsTokens.s4),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
            else if (_err != null)
              EmptyState(
                title: 'Could not load attendance',
                subtitle: _err.toString(),
                icon: Icons.error_outline,
                action: ElevatedButton(onPressed: _load, child: const Text('Retry')),
              )
            else if (!_hasEmployee)
              const EmptyState(
                title: 'No employee profile linked',
                subtitle: 'Your account is not linked to an employee record yet. Ask HR to complete your profile.',
                icon: Icons.person_off_outlined,
              )
            else if (_rows.isEmpty)
              EmptyState(
                title: 'No attendance records',
                subtitle: isManagerial && _employeeUserId.isNotEmpty
                    ? 'No records for this employee in the selected period.'
                    : 'Try another date range or refresh after employees punch.',
                icon: Icons.event_busy_outlined,
              )
            else
              ..._rows.map((r) {
                final date = (r['work_date'] ?? '').toString();
                final employeeName = (r['employee_name'] ?? '').toString().trim();
                final employeeEmail = (r['employee_email'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: HrmsTokens.s3),
                  child: HrmsCard(
                    title: UiFormatters.indianDate(date),
                    subtitle: showEmployee ? (employeeName.isNotEmpty ? employeeName : employeeEmail) : null,
                    trailing: r['check_out_at'] != null
                        ? const Icon(Icons.check_circle_outline, color: HrmsTokens.success)
                        : const Icon(Icons.timelapse, color: HrmsTokens.warning),
                    child: Column(
                      children: [
                        _kv('1. First in', _fmtTime(r['check_in_at']), '2. Lunch out', _fmtTime(r['lunch_check_out_at'])),
                        const SizedBox(height: HrmsTokens.s2),
                        _kv('3. Lunch in', _fmtTime(r['lunch_check_in_at']), '4. Final out', _fmtTime(r['check_out_at'])),
                        const SizedBox(height: HrmsTokens.s2),
                        _kv('Lunch (min)', '${r['lunch_break_minutes'] ?? 0}', 'Tea (min)', '${r['tea_break_minutes'] ?? 0}'),
                        if ((r['notes'] ?? '').toString().trim().isNotEmpty) ...[
                          const SizedBox(height: HrmsTokens.s2),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              (r['notes'] ?? '').toString(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k1, String v1, String k2, String v2) {
    final t = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _kvItem(k1, v1, t),
        ),
        const SizedBox(width: HrmsTokens.s3),
        Expanded(
          child: _kvItem(k2, v2, t),
        ),
      ],
    );
  }

  Widget _kvItem(String k, String v, ThemeData t) {
    return Container(
      padding: const EdgeInsets.all(HrmsTokens.s3),
      decoration: BoxDecoration(
        color: HrmsTokens.bg,
        borderRadius: HrmsTokens.rMd(),
        border: Border.all(color: HrmsTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: t.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(v, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

