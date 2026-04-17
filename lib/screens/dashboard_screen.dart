import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/hrms_card.dart';
import '../widgets/app_drawer.dart';

const Color _kTeal = Color(0xFF0F766E);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.app});

  final AppState app;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final rpc = RpcService();
  Map<String, dynamic>? attendance; // { has_employee, work_date, log }
  bool attendanceLoading = true;
  bool punching = false;
  Timer? _timer;
  int tick = DateTime.now().millisecondsSinceEpoch;

  List<Map<String, dynamic>>? _leaveBalances;
  bool _leaveBalancesLoading = true;
  Object? _leaveBalancesErr;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _initials(String? name, String email) {
    final n = (name ?? '').trim();
    if (n.isNotEmpty) {
      final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
      return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
    }
    final local = email.split('@').first;
    return local.isNotEmpty ? local.substring(0, 1).toUpperCase() : 'U';
  }

  DateTime? _tryParseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return DateTime.tryParse(s);
  }

  @override
  void initState() {
    super.initState();
    _refreshAttendance();
    _refreshLeaveBalances();
  }

  Future<void> _refreshLeaveBalances() async {
    final u = widget.app.user;
    final cid = u?.companyId;
    if (u == null || cid == null || cid.isEmpty) {
      if (mounted) {
        setState(() {
          _leaveBalancesLoading = false;
          _leaveBalances = null;
          _leaveBalancesErr = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _leaveBalancesLoading = true;
        _leaveBalancesErr = null;
      });
    }
    try {
      final today = DateTime.now();
      final ymd =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final rows = await rpc.leaveBalances(companyId: cid, userId: u.id, asOfYmd: ymd);
      if (mounted) setState(() => _leaveBalances = rows);
    } catch (e) {
      if (mounted) setState(() => _leaveBalancesErr = e);
    } finally {
      if (mounted) setState(() => _leaveBalancesLoading = false);
    }
  }

  String _fmtNum(dynamic v) {
    final n = num.tryParse((v ?? '').toString());
    if (n == null) return '0';
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(n % 1 == 0 ? 0 : 1);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTimer(bool shouldRun) {
    if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => tick = DateTime.now().millisecondsSinceEpoch);
    });
  }

  Future<void> _refreshAttendance() async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() => attendanceLoading = true);
    try {
      final data = await rpc.attendanceTodayWebParity(u.id);
      setState(() => attendance = data);
      final log = (data['log'] as Map?)?.cast<String, dynamic>();
      final punchedIn = log != null && log['check_in_at'] != null && log['check_out_at'] == null;
      _ensureTimer(punchedIn);
    } finally {
      if (mounted) setState(() => attendanceLoading = false);
    }
  }

  Future<Position> _requirePosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw Exception('Please enable device location to punch.');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to punch in/out.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : null),
    );
  }

  String _formatTimeIST(dynamic iso) {
    if (iso == null) return '—';
    final dt = _tryParseDate(iso);
    if (dt == null) return '—';
    // quick IST conversion: add offset +5:30 from UTC if ends with Z; otherwise show local
    final d = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDurationMs(int ms) {
    final x = (ms ~/ 1000).clamp(0, 1 << 30);
    final h = x ~/ 3600;
    final m = (x % 3600) ~/ 60;
    final s = x % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _punch(String action) async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() => punching = true);
    try {
      final pos = await _requirePosition();
      await rpc.attendancePunchWebParity(
        userId: u.id,
        action: action,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracyM: pos.accuracy.round(),
      );
      await _refreshAttendance();
      _snack(action == 'in' ? 'Punched in successfully' : 'Punched out successfully');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), err: true);
    } finally {
      if (mounted) setState(() => punching = false);
    }
  }

  Future<void> _breakToggle(String kind) async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() => punching = true);
    try {
      await rpc.attendanceBreakToggleWebParity(userId: u.id, kind: kind);
      await _refreshAttendance();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), err: true);
    } finally {
      if (mounted) setState(() => punching = false);
    }
  }

  String _formatIndianDate(dynamic v) {
    final dt = _tryParseDate(v);
    if (dt == null) return (v ?? '—').toString();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : dt.month.toString();
    return '${dt.day.toString().padLeft(2, '0')} - $m - ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final u = app.user;
    final name = u?.name?.trim().isNotEmpty == true ? u!.name!.trim() : 'Employee';
    final email = u?.email ?? '';
    final companyId = u?.companyId ?? '';
    final hasEmployee = (attendance?['has_employee'] == true) || (attendance?['hasEmployee'] == true);
    final rawLog = (attendance?['log'] is Map) ? attendance!['log'] : attendance;
    final log = (rawLog is Map) ? rawLog.cast<String, dynamic>() : <String, dynamic>{};

    final punchedIn = log['check_in_at'] != null && log['check_out_at'] == null;
    final lunchRunning = punchedIn && log['lunch_break_started_at'] != null;
    final teaRunning = punchedIn && log['tea_break_started_at'] != null;
    final punchInMs = punchedIn ? _tryParseDate(log['check_in_at'])?.millisecondsSinceEpoch ?? 0 : 0;
    final elapsedMs = punchedIn ? (tick - punchInMs).clamp(0, 1 << 30) : 0;
    final lunchBaseMs = (((log['lunch_break_minutes'] ?? 0) as num).round()) * 60 * 1000;
    final teaBaseMs = (((log['tea_break_minutes'] ?? 0) as num).round()) * 60 * 1000;
    final lunchSince = lunchRunning ? (_tryParseDate(log['lunch_break_started_at'])?.millisecondsSinceEpoch) : null;
    final teaSince = teaRunning ? (_tryParseDate(log['tea_break_started_at'])?.millisecondsSinceEpoch) : null;
    final lunchTotalMs = lunchSince != null ? lunchBaseMs + (tick - lunchSince).clamp(0, 1 << 30) : lunchBaseMs;
    final teaTotalMs = teaSince != null ? teaBaseMs + (tick - teaSince).clamp(0, 1 << 30) : teaBaseMs;
    final activeMs = punchedIn ? (elapsedMs - lunchTotalMs - teaTotalMs).clamp(0, 1 << 30) : 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            onPressed: () async {
              await app.logout();
              if (!context.mounted) return;
              // go_router redirect will handle the rest
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          )
        ],
      ),
      drawer: AppDrawer(app: app),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_refreshAttendance(), _refreshLeaveBalances()]);
        },
        child: Padding(
          padding: const EdgeInsets.all(HrmsTokens.s4),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: HrmsTokens.primary,
                  foregroundColor: Colors.white,
                  child: Text(_initials(u?.name, email)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()},',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black45),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Attendance
            HrmsCard(
              title: 'Attendance',
              subtitle: 'Punch sequence: first in → lunch out → lunch in → final out (IST).',
              trailing: const Icon(Icons.fingerprint, color: HrmsTokens.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (attendanceLoading)
                    Text('Loading…', style: Theme.of(context).textTheme.bodySmall)
                  else if (!hasEmployee)
                    Text('No employee record linked to this user.', style: Theme.of(context).textTheme.bodySmall)
                  else ...[
                    Text(
                      punchedIn ? 'Punched in at ${_formatTimeIST(log['check_in_at'])}' : 'Not punched in',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: HrmsTokens.s2),
                    if (punchedIn)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDurationMs(elapsedMs),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Active: ${_formatDurationMs(activeMs)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                    const SizedBox(height: HrmsTokens.s3),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: punching || !hasEmployee || punchedIn ? null : () => _punch('in'),
                            icon: const Icon(Icons.login),
                            label: const Text('Punch in'),
                          ),
                        ),
                        const SizedBox(width: HrmsTokens.s3),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: punching || !punchedIn ? null : () => _punch('out'),
                            icon: const Icon(Icons.logout),
                            label: const Text('Punch out'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HrmsTokens.s3),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: punching || !punchedIn ? null : () => _breakToggle('lunch'),
                            child: Text(
                              lunchRunning
                                  ? 'End lunch (${_formatDurationMs(lunchTotalMs)})'
                                  : 'Lunch (${_formatDurationMs(lunchTotalMs)})',
                            ),
                          ),
                        ),
                        const SizedBox(width: HrmsTokens.s3),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: punching || !punchedIn ? null : () => _breakToggle('tea'),
                            child: Text(
                              teaRunning
                                  ? 'End tea (${_formatDurationMs(teaTotalMs)})'
                                  : 'Tea (${_formatDurationMs(teaTotalMs)})',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Leave balances (same policy math as web /api/leave/balance)
            const SizedBox(height: HrmsTokens.s4),
            HrmsCard(
              title: 'Leave balances',
              subtitle: 'Available days per leave policy (PL, SL, etc.)',
              trailing: const Icon(Icons.beach_access_outlined, color: HrmsTokens.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    if (companyId.isEmpty || u == null)
                      const Text('No company assigned.')
                    else if (_leaveBalancesLoading)
                      Text('Loading…', style: Theme.of(context).textTheme.bodySmall)
                    else if (_leaveBalancesErr != null)
                      Text('Error: $_leaveBalancesErr', style: const TextStyle(color: HrmsTokens.danger))
                    else if ((_leaveBalances ?? const []).isEmpty)
                      Text(
                        'No leave policies configured. Ask HR to set up leave types and policies.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else ...[
                      for (final row in _leaveBalances!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _LeaveBalanceRow(
                            name: (row['name'] ?? '').toString(),
                            isPaid: row['is_paid'] == true,
                            used: _fmtNum(row['used_days']),
                            remaining: row['remaining_days'],
                          ),
                        ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.push('/leave'),
                          child: const Text('Go to Leave'),
                        ),
                      ),
                    ],
                ],
              ),
            ),

            const SizedBox(height: HrmsTokens.s4),

            // Payslip (wired)
            HrmsCard(
              title: 'Latest payslip',
              subtitle: 'Your most recent payslip (if generated).',
              trailing: const Icon(Icons.description_outlined, color: HrmsTokens.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    if (companyId.isEmpty || u == null)
                      const Text('No company assigned.')
                    else
                      FutureBuilder(
                        future: RpcService().payslipsList(companyId: companyId, employeeUserId: u.id),
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return Text('Loading…', style: Theme.of(context).textTheme.bodySmall);
                          }
                          if (snap.hasError) {
                            return Text('Error: ${snap.error}', style: const TextStyle(color: HrmsTokens.danger));
                          }
                          final rows = (snap.data ?? const <Map<String, dynamic>>[]);
                          if (rows.isEmpty) return Text('No payslips found.', style: Theme.of(context).textTheme.bodySmall);
                          final p = rows.first;
                          final dateLabel = _formatIndianDate(p['generated_at']);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Generated', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                                  Text(dateLabel, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              Text(
                                'Net: ${p['net_pay'] ?? '—'}',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          );
                        },
                      ),
                ],
              ),
            ),

            // Upcoming holidays (wired)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Upcoming holidays', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (companyId.isEmpty)
                      const Text('No company assigned.')
                    else
                      FutureBuilder(
                        future: RpcService().holidaysList(companyId),
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Text('Loading…');
                          }
                          if (snap.hasError) {
                            return Text('Error: ${snap.error}', style: const TextStyle(color: Colors.red));
                          }
                          final today = DateTime.now();
                          final rows = (snap.data ?? const <Map<String, dynamic>>[])
                              .where((h) {
                                final d = _tryParseDate(h['holiday_end_date'] ?? h['holiday_date']);
                                if (d == null) return false;
                                return !d.isBefore(DateTime(today.year, today.month, today.day));
                              })
                              .toList()
                            ..sort((a, b) => (a['holiday_date'] ?? '').toString().compareTo((b['holiday_date'] ?? '').toString()));

                          final top = rows.take(5).toList();
                          if (top.isEmpty) return const Text('No upcoming holidays.');
                          return Column(
                            children: [
                              for (final h in top)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text((h['name'] ?? '').toString()),
                                  subtitle: Text(_formatIndianDate(h['holiday_date'])),
                                )
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaveBalanceRow extends StatelessWidget {
  const _LeaveBalanceRow({
    required this.name,
    required this.isPaid,
    required this.used,
    required this.remaining,
  });

  final String name;
  final bool isPaid;
  final String used;
  final dynamic remaining;

  @override
  Widget build(BuildContext context) {
    final remStr = remaining == null ? '∞' : _fmtRemaining(remaining);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFF8FAFC),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPaid ? Icons.payments_outlined : Icons.event_busy_outlined,
              color: _kTeal,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Leave' : name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _kTeal,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text('Used $used', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black45)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                remStr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _kTeal,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
              ),
              Text('Available', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.black45)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtRemaining(dynamic v) {
    final n = num.tryParse(v.toString());
    if (n == null) return '—';
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(n % 1 == 0 ? 0 : 1);
  }
}

