import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/hrms_ui/quick_action_tile.dart';
import '../widgets/hrms_ui/section_header.dart';

import '../app_config.dart';
import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/formatters.dart';
import '../ui/hrms_card.dart';

/// Matches web `DashboardContent`: only the **employee** role gets self punch-in/out on the dashboard.
bool _isEmployeeDashboard(SessionUser? u) => u != null && u.role == 'employee';

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
  Timer? _pollTimer;
  /// Live clock for attendance only — updated every second **without** rebuilding payslip/holidays [FutureBuilder]s.
  final ValueNotifier<int> _clockTick = ValueNotifier(DateTime.now().millisecondsSinceEpoch);

  Future<Map<String, dynamic>>? _payslipsFuture;
  Future<List<Map<String, dynamic>>>? _holidaysFuture;

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
    _primePayslipAndHolidayFutures();
    if (_isEmployeeDashboard(widget.app.user)) {
      _refreshAttendance();
      _refreshLeaveBalances();
    } else {
      attendanceLoading = false;
      _leaveBalancesLoading = false;
    }
  }

  void _primePayslipAndHolidayFutures() {
    final u = widget.app.user;
    final cid = u?.companyId;
    if (u == null || cid == null || cid.isEmpty) {
      _payslipsFuture = null;
      _holidaysFuture = null;
    } else {
      _payslipsFuture = rpc.payslipsMe(userId: u.id, companyId: cid);
      _holidaysFuture = rpc.holidaysList(cid);
    }
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
    _pollTimer?.cancel();
    _clockTick.dispose();
    super.dispose();
  }

  void _ensurePoll(bool punchedInOpen) {
    if (!punchedInOpen) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) unawaited(_refreshAttendance(silent: true));
    });
  }

  void _ensureTimer(bool shouldRun) {
    if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _clockTick.value = DateTime.now().millisecondsSinceEpoch;
    });
  }

  Future<void> _refreshAttendance({bool silent = false}) async {
    final u = widget.app.user;
    if (u == null) return;
    if (!silent && mounted) setState(() => attendanceLoading = true);
    try {
      final data = await rpc.attendanceTodayWebParity(u.id);
      if (!mounted) return;
      setState(() {
        attendance = data;
        final log = (data['log'] as Map?)?.cast<String, dynamic>();
        final punchedIn = log != null && log['check_in_at'] != null && log['check_out_at'] == null;
        _ensureTimer(punchedIn);
        _ensurePoll(punchedIn);
      });
    } finally {
      if (!silent && mounted) setState(() => attendanceLoading = false);
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

  /// Same titles/messages as web `DashboardContent` confirm dialogs.
  Future<bool> _confirmAttendanceAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _onPunchTap(String action) async {
    if (action == 'out') {
      final ok = await _confirmAttendanceAction(
        title: 'Final punch out now?',
        message: "This will complete today's attendance.",
        confirmLabel: 'Punch out',
      );
      if (!ok || !mounted) return;
    }
    await _punch(action);
  }

  Future<void> _openAgentDownload() async {
    final raw = AppConfig.agentDownloadUrl.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _snack('Invalid download link in config.', err: true);
      return;
    }
    if (!await canLaunchUrl(uri)) {
      _snack('Could not open download link.', err: true);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  /// Whole minutes as "Xh Ym" — matches web dashboard / attendance page.
  String _fmtHoursMin(num? min) {
    if (min == null) return '—';
    if (min is double && !min.isFinite) return '—';
    final total = min.round().clamp(0, 1 << 30);
    final h = total ~/ 60;
    final m = total % 60;
    return '${h}h ${m}m';
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

  Widget _buildAttendanceSection(BuildContext context, int tick) {
    final hasEmployee = (attendance?['has_employee'] == true) || (attendance?['hasEmployee'] == true);
    final rawLog = (attendance?['log'] is Map) ? attendance!['log'] : attendance;
    final log = (rawLog is Map) ? rawLog.cast<String, dynamic>() : <String, dynamic>{};

    final punchedIn = log['check_in_at'] != null && log['check_out_at'] == null;
    final dayComplete = log['check_in_at'] != null && log['check_out_at'] != null;
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

    final agent = (attendance?['agent'] is Map) ? (attendance!['agent'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final agentConnected = agent['connected'] == true;

    final grossMinApi = log['grossMinutes'] != null ? (log['grossMinutes'] as num).round() : null;
    final elapsedMinFallback =
        punchedIn && punchInMs > 0 ? ((tick - punchInMs) / 60000).floor().clamp(0, 1 << 30) : 0;
    final grossMin = grossMinApi ?? elapsedMinFallback;

    final rawActiveMin = log['activeMinutes'] != null
        ? (log['activeMinutes'] as num).round()
        : (punchedIn ? (activeMs / 60000).floor() : 0);
    final activeMin = rawActiveMin > grossMin ? grossMin : rawActiveMin;
    final activeMeetsPresent = activeMin >= 8 * 60;

    return HrmsCard(
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
              dayComplete
                  ? 'Attendance complete for today · In ${_formatTimeIST(log['check_in_at'])} · Out ${_formatTimeIST(log['check_out_at'])}'
                  : punchedIn
                      ? 'Punched in at ${_formatTimeIST(log['check_in_at'])}'
                      : 'Not punched in',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: HrmsTokens.s2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: agentConnected ? const Color(0xFFF0F9FF) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: agentConnected ? const Color(0xFFBAE6FD) : const Color(0xFFFDE68A),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'HRMS Agent',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: agentConnected ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          agentConnected ? 'Connected' : 'Disconnected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: agentConnected ? const Color(0xFF0369A1) : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (agentConnected)
                    Text(
                      'Last seen ${_formatTimeIST(agent['lastSeenAt'])}'
                      '${agent['deviceName'] != null ? ' · ${agent['deviceName']}' : ''}'
                      '${agent['appVersion'] != null ? ' · v${agent['appVersion']}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87),
                    )
                  else ...[
                    Text(
                      'HRMS Agent is not connected. Please open HRMS Attendance Agent on your system.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87),
                    ),
                    if (AppConfig.agentDownloadUrl.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          onPressed: _openAgentDownload,
                          child: const Text('Download Agent'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (punchedIn) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD1FAE5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time on premises (since first in)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF065F46),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtHoursMin(grossMin),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: const Color(0xFF064E3B),
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Active work',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF065F46),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtHoursMin(activeMin),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: const Color(0xFF064E3B),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activeMeetsPresent ? '≥ 8h active — present for payroll' : 'Need 8h active work for payroll present',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: activeMeetsPresent ? const Color(0xFF047857) : const Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Live clock: ${_formatDurationMs(elapsedMs)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.black45),
              ),
            ],
            const SizedBox(height: HrmsTokens.s3),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: punching || !hasEmployee || punchedIn || dayComplete ? null : () => _onPunchTap('in'),
                    icon: const Icon(Icons.login),
                    label: const Text('Punch in'),
                  ),
                ),
                const SizedBox(width: HrmsTokens.s3),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: punching || !punchedIn ? null : () => _onPunchTap('out'),
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
    );
  }

  String _roleWorkflowLabel(String role) {
    if (role.isEmpty) return 'User';
    return role
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  List<Widget> _managerialNavGrid(BuildContext context, SessionUser u) {
    final role = u.role;
    final managerial = u.isManagerial;
    final superA = u.isSuperAdmin;
    final showAttendanceCard = managerial || role == 'manager';
    final canCompanyAttendance = managerial;

    final cards = <Widget>[
      if (showAttendanceCard)
        _ManagerialNavCard(
          icon: Icons.event_available_outlined,
          title: 'Attendance overview',
          description:
              'Employees punch: first in → lunch out → lunch in → final out. Review punches by date from the attendance workspace.',
          primaryLabel: canCompanyAttendance ? 'Company attendance' : 'Open attendance',
          onPrimary: () => context.go('/attendance'),
          primaryFilled: canCompanyAttendance,
        ),
      _ManagerialNavCard(
        icon: Icons.beach_access_outlined,
        title: 'Leaves',
        description: 'See leave balance and requests. HR and managers can review team or company leave.',
        primaryLabel: 'Go to Leave',
        onPrimary: () => context.go('/leave'),
      ),
      _ManagerialNavCard(
        icon: Icons.payments_outlined,
        title: 'Payroll & payslips',
        description: managerial
            ? 'View payslips and run payroll periods for your company.'
            : 'View generated payslips for your payroll periods.',
        primaryLabel: 'View payslips',
        onPrimary: () => context.go('/payslips'),
        secondaryLabel: managerial ? 'Payroll admin' : null,
        onSecondary: managerial ? () => context.push('/payroll') : null,
      ),
      _ManagerialNavCard(
        icon: Icons.celebration_outlined,
        title: 'Holidays',
        description: 'Company holiday calendar configured by Admin / HR.',
        primaryLabel: 'View calendar',
        onPrimary: () => context.push('/holidays'),
        primaryFilled: false,
      ),
      if (managerial)
        _ManagerialNavCard(
          icon: Icons.groups_outlined,
          title: 'Employee hub',
          description: 'Search, view and manage employee records for the entire company.',
          primaryLabel: 'Go to employees',
          onPrimary: () => context.push('/employees'),
        ),
      if (superA)
        _ManagerialNavCard(
          icon: Icons.apartment_outlined,
          title: 'Organization',
          description: 'Company profile, branding and workspace settings.',
          primaryLabel: 'Open settings',
          onPrimary: () => context.push('/settings'),
        ),
    ];

    return [
      Text(
        'You are viewing the ${_roleWorkflowLabel(role)} workflow.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: HrmsTokens.muted),
      ),
      const SizedBox(height: HrmsTokens.s4),
      LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final gap = HrmsTokens.s4;
          final colW = w >= 560 ? (w - gap) / 2 : w;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in cards)
                SizedBox(
                  width: colW,
                  child: c,
                ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _employeeDashboardList(BuildContext context, SessionUser u, String name, String email, String companyId) {
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: HrmsTokens.s4, vertical: HrmsTokens.s5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              HrmsTokens.primary,
              Color.lerp(HrmsTokens.primary, const Color(0xFF4C1D95), 0.35)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: HrmsTokens.rLg(),
          boxShadow: [HrmsTokens.shadowSm()],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
              child: Text(_initials(u.name, email), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            const SizedBox(width: HrmsTokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Employee',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: HrmsTokens.s4),
      const SectionHeader(title: 'Quick actions', subtitle: 'Shortcuts to common tasks'),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: HrmsTokens.s3,
        crossAxisSpacing: HrmsTokens.s3,
        childAspectRatio: 1.12,
        children: [
          QuickActionTile(
            icon: Icons.beach_access_outlined,
            label: 'Apply leave',
            onTap: () => context.go('/leave'),
          ),
          QuickActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'Reimbursement',
            onTap: () => context.push('/reimbursements'),
          ),
          QuickActionTile(
            icon: Icons.payments_outlined,
            label: 'Payslip',
            onTap: () => context.go('/payslips'),
          ),
          QuickActionTile(
            icon: Icons.calendar_month_outlined,
            label: 'My attendance',
            onTap: () => context.go('/attendance'),
          ),
        ],
      ),
      const SizedBox(height: HrmsTokens.s4),
      const SectionHeader(title: 'Today', subtitle: 'Attendance and time on site'),
      ValueListenableBuilder<int>(
        valueListenable: _clockTick,
        builder: (context, tick, _) {
          return _buildAttendanceSection(context, tick);
        },
      ),
      const SizedBox(height: HrmsTokens.s4),
      HrmsCard(
        title: 'Leave balances',
        subtitle: 'Available days per leave policy (PL, SL, etc.)',
        trailing: const Icon(Icons.beach_access_outlined, color: HrmsTokens.primary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (companyId.isEmpty)
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
              for (final row in _leaveBalances!.take(3))
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
                child: FilledButton(
                  onPressed: () => context.go('/leave'),
                  child: const Text('Go to Leave'),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: HrmsTokens.s4),
      HrmsCard(
        title: 'Latest payslip',
        subtitle: 'Your most recent payslip (if generated).',
        trailing: const Icon(Icons.description_outlined, color: HrmsTokens.primary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (companyId.isEmpty)
              const Text('No company assigned.')
            else if (_payslipsFuture == null)
              Text('Loading…', style: Theme.of(context).textTheme.bodySmall)
            else
              FutureBuilder<Map<String, dynamic>>(
                future: _payslipsFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Text('Loading…', style: Theme.of(context).textTheme.bodySmall);
                  }
                  if (snap.hasError) {
                    return Text('Error: ${snap.error}', style: const TextStyle(color: HrmsTokens.danger));
                  }
                  final data = snap.data;
                  final rows = (data?['payslips'] as List?) ?? const [];
                  if (rows.isEmpty) return Text('No payslips found.', style: Theme.of(context).textTheme.bodySmall);
                  final p = Map<String, dynamic>.from(rows.first as Map);
                  final dateLabel = _formatIndianDate(p['generated_at']);
                  final net = num.tryParse((p['net_pay'] ?? '').toString());
                  final netLabel = net != null ? UiFormatters.inr(net) : (p['net_pay'] ?? '—').toString();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Generated', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HrmsTokens.muted)),
                          Text(dateLabel, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Text(
                        'Net: $netLabel',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
      const SizedBox(height: HrmsTokens.s4),
      HrmsCard(
        title: 'Upcoming holidays',
        subtitle: 'Next dates on your company calendar.',
        trailing: const Icon(Icons.celebration_outlined, color: HrmsTokens.primary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (companyId.isEmpty)
              const Text('No company assigned.')
            else if (_holidaysFuture == null)
              Text('Loading…', style: Theme.of(context).textTheme.bodySmall)
            else
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _holidaysFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Text('Loading…', style: Theme.of(context).textTheme.bodySmall);
                  }
                  if (snap.hasError) {
                    return Text('Error: ${snap.error}', style: const TextStyle(color: HrmsTokens.danger));
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
                  if (top.isEmpty) {
                    return Text('No upcoming holidays.', style: Theme.of(context).textTheme.bodySmall);
                  }
                  return Column(
                    children: [
                      for (final h in top)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  (h['name'] ?? '').toString(),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                _formatIndianDate(h['holiday_date']),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HrmsTokens.muted),
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.push('/holidays'),
                          child: const Text('View all'),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _managerialHeaderBanner(BuildContext context, String name, String email, String role) {
    return [
      Material(
        color: HrmsTokens.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: HrmsTokens.rLg(),
          side: const BorderSide(color: HrmsTokens.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HrmsTokens.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: HrmsTokens.primarySoft,
                foregroundColor: HrmsTokens.primary,
                child: Text(
                  _initials(name == 'User' ? null : name, email),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: HrmsTokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HrmsTokens.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: HrmsTokens.text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(email, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HrmsTokens.muted)),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: HrmsTokens.primarySoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _roleWorkflowLabel(role),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: HrmsTokens.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: HrmsTokens.s4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final u = app.user;
    final name = u?.name?.trim().isNotEmpty == true ? u!.name!.trim() : 'User';
    final email = u?.email ?? '';
    final isEmployee = _isEmployeeDashboard(u);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Dashboard'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (mounted) setState(_primePayslipAndHolidayFutures);
          if (!mounted) return;
          if (isEmployee) {
            await Future.wait([_refreshAttendance(), _refreshLeaveBalances()]);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(HrmsTokens.s4),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (u != null && isEmployee) ..._employeeDashboardList(context, u, name, email, u.companyId ?? ''),
              if (u != null && !isEmployee) ...[
                ..._managerialHeaderBanner(context, name, email, u.role),
                ..._managerialNavGrid(context, u),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagerialNavCard extends StatelessWidget {
  const _ManagerialNavCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryFilled = true,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool primaryFilled;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HrmsTokens.surface,
        borderRadius: HrmsTokens.rLg(),
        border: Border.all(color: HrmsTokens.border),
        boxShadow: [HrmsTokens.shadowSm()],
      ),
      child: Padding(
        padding: const EdgeInsets.all(HrmsTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: HrmsTokens.primary, size: 24),
            const SizedBox(height: HrmsTokens.s3),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: HrmsTokens.text,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HrmsTokens.muted,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: HrmsTokens.s4),
            SizedBox(
              width: double.infinity,
              child: primaryFilled
                  ? FilledButton(
                      onPressed: onPrimary,
                      child: Text(primaryLabel),
                    )
                  : OutlinedButton(
                      onPressed: onPrimary,
                      child: Text(primaryLabel),
                    ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: HrmsTokens.s2),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
              ),
            ],
          ],
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
            color: HrmsTokens.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isPaid ? Icons.payments_outlined : Icons.event_busy_outlined,
            color: HrmsTokens.primary,
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
                        color: HrmsTokens.primary,
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
                      color: HrmsTokens.primary,
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

