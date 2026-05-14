import 'dart:convert';

/// Mirrors `hrms-web/src/app/api/attendance/me/route.ts`,
/// `attendanceDisconnectedSeconds.ts`, and `attendancePolicy.ts`.

const int _minCombinedBreakMinutes = 60;
const int _heartbeatGraceSeconds = 60;
const int _postPunchDisconnectGraceSeconds = 300;

int _clampMinutes(num n) {
  final x = n.round();
  if (x < 0) return 0;
  if (x > 24 * 60) return 24 * 60;
  return x;
}

int minutesBetweenIso(String? startIso, String? endIso) {
  if (startIso == null || endIso == null) return 0;
  final start = DateTime.tryParse(startIso)?.millisecondsSinceEpoch;
  final end = DateTime.tryParse(endIso)?.millisecondsSinceEpoch;
  if (start == null || end == null || end <= start) return 0;
  return ((end - start) / 60000).round().clamp(0, 1 << 30);
}

class _BreakWindow {
  _BreakWindow(this.startMs, this.endMs);
  final int startMs;
  int endMs;
}

List<Map<String, String>> _asSegments(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) {
    final out = <Map<String, String>>[];
    for (final x in raw) {
      if (x is! Map) continue;
      final o = x['out']?.toString() ?? '';
      final i = x['in']?.toString() ?? '';
      if (o.isNotEmpty && i.isNotEmpty) out.add({'out': o, 'in': i});
    }
    return out;
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final j = jsonDecode(raw);
      if (j is List) return _asSegments(j);
    } catch (_) {}
  }
  return [];
}

void _addBreakWindow(List<_BreakWindow> windows, String? startIso, String? endIso) {
  if (startIso == null || endIso == null || startIso.isEmpty || endIso.isEmpty) return;
  final startMs = DateTime.tryParse(startIso)?.millisecondsSinceEpoch;
  final endMs = DateTime.tryParse(endIso)?.millisecondsSinceEpoch;
  if (startMs == null || endMs == null || endMs <= startMs) return;
  windows.add(_BreakWindow(startMs, endMs));
}

List<_BreakWindow> _mergeBreakWindows(List<_BreakWindow> windows) {
  final sorted = windows
      .where((w) => w.endMs > w.startMs)
      .toList()
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final merged = <_BreakWindow>[];
  for (final w in sorted) {
    final last = merged.isEmpty ? null : merged.last;
    if (last == null || w.startMs > last.endMs) {
      merged.add(_BreakWindow(w.startMs, w.endMs));
    } else {
      last.endMs = last.endMs > w.endMs ? last.endMs : w.endMs;
    }
  }
  return merged;
}

List<_BreakWindow> _breakWindowsFromLog(Map<String, dynamic> log, int nowMs) {
  final windows = <_BreakWindow>[];
  final nowIso = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true).toIso8601String();

  for (final s in _asSegments(log['lunch_break_segments'])) {
    _addBreakWindow(windows, s['out'], s['in']);
  }
  for (final s in _asSegments(log['tea_break_segments'])) {
    _addBreakWindow(windows, s['out'], s['in']);
  }

  _addBreakWindow(windows, log['lunch_check_out_at']?.toString(), log['lunch_check_in_at']?.toString());
  _addBreakWindow(windows, log['tea_check_out_at']?.toString(), log['tea_check_in_at']?.toString());

  final lbs = log['lunch_break_started_at']?.toString();
  if (lbs != null && lbs.isNotEmpty) {
    _addBreakWindow(windows, lbs, nowIso);
  }
  final tbs = log['tea_break_started_at']?.toString();
  if (tbs != null && tbs.isNotEmpty) {
    _addBreakWindow(windows, tbs, nowIso);
  }

  return _mergeBreakWindows(windows);
}

int _overlapMs(int aStart, int aEnd, int bStart, int bEnd) {
  return (aEnd < bStart || bEnd < aStart) ? 0 : (aEnd < bEnd ? aEnd : bEnd) - (aStart > bStart ? aStart : bStart);
}

int _breakOverlapMs(int startMs, int endMs, List<_BreakWindow> breakWindows) {
  var sum = 0;
  for (final w in breakWindows) {
    sum += _overlapMs(startMs, endMs, w.startMs, w.endMs);
  }
  return sum;
}

Map<String, int> _effectiveCombinedBreakBreakdown({
  required int lunchMinutes,
  required int teaMinutes,
  required int grossWorkMinutes,
  int minimumBreakMinutes = _minCombinedBreakMinutes,
}) {
  final lunch = _clampMinutes(lunchMinutes);
  final tea = _clampMinutes(teaMinutes);
  final gross = _clampMinutes(grossWorkMinutes);
  final minimum = _clampMinutes(minimumBreakMinutes);

  final actualBreakMinutes = lunch + tea;
  final top = actualBreakMinutes > minimum ? actualBreakMinutes : minimum;
  final countedBreakMinutes = gross < top ? gross : top;

  final policyShortfallMinutes = (countedBreakMinutes - actualBreakMinutes).clamp(0, 1 << 30);

  return {
    'lunchBreakMinutes': lunch + policyShortfallMinutes,
    'teaBreakMinutes': tea,
    'actualBreakMinutes': actualBreakMinutes,
    'countedBreakMinutes': countedBreakMinutes,
    'policyShortfallMinutes': policyShortfallMinutes,
  };
}

int _disconnectedSecondsFromSessions(
  List<Map<String, dynamic>> rawSessions,
  String? checkInAt,
  String? checkOutAt,
  int nowMs,
  List<_BreakWindow> breakWindows,
) {
  if (checkInAt == null || checkInAt.isEmpty) return 0;

  final heartbeatGraceMs = _heartbeatGraceSeconds * 1000;
  final postPunchGraceMs = _postPunchDisconnectGraceSeconds * 1000;
  final startMs = DateTime.tryParse(checkInAt)?.millisecondsSinceEpoch;
  final endMs = checkOutAt != null && checkOutAt.isNotEmpty
      ? DateTime.tryParse(checkOutAt)?.millisecondsSinceEpoch
      : nowMs;
  if (startMs == null || endMs == null || endMs <= startMs) return 0;

  final sessions = <({int start, int end})>[];
  for (final s in rawSessions) {
    final startedAt = s['started_at']?.toString();
    final endedRaw = s['ended_at'] ?? s['last_heartbeat_at'];
    final endedAt = endedRaw?.toString();
    if (startedAt == null || endedAt == null) continue;
    final st = DateTime.tryParse(startedAt)?.millisecondsSinceEpoch;
    final en = DateTime.tryParse(endedAt)?.millisecondsSinceEpoch;
    if (st == null || en == null) continue;
    sessions.add((start: st, end: en));
  }
  sessions.sort((a, b) => a.start.compareTo(b.start));

  var disconnectedSeconds = 0;
  var cursorMs = startMs;

  for (final s in sessions) {
    final gapGraceMs = cursorMs == startMs ? postPunchGraceMs : heartbeatGraceMs;
    if (s.start > cursorMs + gapGraceMs) {
      final gapStartMs = cursorMs + gapGraceMs;
      final gapEndMs = s.start;
      final gapMs = (gapEndMs - gapStartMs).clamp(0, 1 << 30);
      final breakMs = _breakOverlapMs(gapStartMs, gapEndMs, breakWindows);
      disconnectedSeconds += ((gapMs - breakMs).clamp(0, 1 << 30)) ~/ 1000;
    }
    cursorMs = cursorMs > s.end ? cursorMs : s.end;
  }

  final tailGraceMs = sessions.isEmpty ? postPunchGraceMs : heartbeatGraceMs;
  if (endMs > cursorMs + tailGraceMs) {
    final gapStartMs = cursorMs + tailGraceMs;
    final gapEndMs = endMs;
    final gapMs = (gapEndMs - gapStartMs).clamp(0, 1 << 30);
    final breakMs = _breakOverlapMs(gapStartMs, gapEndMs, breakWindows);
    disconnectedSeconds += ((gapMs - breakMs).clamp(0, 1 << 30)) ~/ 1000;
  }

  return disconnectedSeconds < 0 ? 0 : disconnectedSeconds;
}

/// Adds `grossMinutes`, `activeMinutes`, `idleMinutes`, agent + disconnected fields (web API shape).
Map<String, dynamic> mergeWebDashboardMetrics({
  required Map<String, dynamic> log,
  required List<Map<String, dynamic>> sessions,
  required int nowMs,
}) {
  final checkInIso = log['check_in_at']?.toString();
  final checkOutIso = log['check_out_at']?.toString();
  final checkInMs = checkInIso != null && checkInIso.isNotEmpty ? DateTime.tryParse(checkInIso)?.millisecondsSinceEpoch : null;
  final checkOutMs = checkOutIso != null && checkOutIso.isNotEmpty
      ? DateTime.tryParse(checkOutIso)?.millisecondsSinceEpoch
      : nowMs;

  int? grossMin;
  if (checkInMs != null && checkOutMs != null && checkOutMs > checkInMs) {
    grossMin = ((checkOutMs - checkInMs) / 60000).round().clamp(0, 1 << 30);
  } else if (log['total_hours'] != null) {
    grossMin = ((num.tryParse(log['total_hours'].toString()) ?? 0) * 60).round().clamp(0, 1 << 30);
  }

  final recordedLunchMin = (num.tryParse(log['lunch_break_minutes']?.toString() ?? '0') ?? 0).round();
  final recordedTeaMin = (num.tryParse(log['tea_break_minutes']?.toString() ?? '0') ?? 0).round();

  final lunchSpanMin = minutesBetweenIso(log['lunch_check_out_at']?.toString(), log['lunch_check_in_at']?.toString());
  final teaSpanMin = minutesBetweenIso(log['tea_check_out_at']?.toString(), log['tea_check_in_at']?.toString());

  final nowIso = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true).toIso8601String();
  final runningLunchMin = log['lunch_break_started_at'] != null
      ? minutesBetweenIso(log['lunch_break_started_at'].toString(), nowIso)
      : 0;
  final runningTeaMin = log['tea_break_started_at'] != null
      ? minutesBetweenIso(log['tea_break_started_at'].toString(), nowIso)
      : 0;

  final lunchIdleMinBase = [recordedLunchMin, lunchSpanMin, runningLunchMin].reduce((a, b) => a > b ? a : b);
  final teaIdleMinBase = [recordedTeaMin, teaSpanMin, runningTeaMin].reduce((a, b) => a > b ? a : b);

  final shouldApplyCombinedBreakPolicy = log['check_out_at'] != null;
  final grossForPolicy = grossMin ?? 0;
  final Map<String, int> effectiveBreak = shouldApplyCombinedBreakPolicy
      ? _effectiveCombinedBreakBreakdown(
          lunchMinutes: lunchIdleMinBase,
          teaMinutes: teaIdleMinBase,
          grossWorkMinutes: grossForPolicy,
        )
      : <String, int>{
          'lunchBreakMinutes': lunchIdleMinBase,
          'teaBreakMinutes': teaIdleMinBase,
          'actualBreakMinutes': lunchIdleMinBase + teaIdleMinBase,
          'countedBreakMinutes': lunchIdleMinBase + teaIdleMinBase,
          'policyShortfallMinutes': 0,
        };

  final manualBreakIdleMinutes = effectiveBreak['countedBreakMinutes']!;

  final isPurged = log['activity_purged_at'] != null;

  var agentActiveSecondsLive = 0;
  var agentIdleSecondsLive = 0;
  var storedDisconnectedSeconds = 0;
  for (final s in sessions) {
    agentActiveSecondsLive += (num.tryParse(s['active_seconds']?.toString() ?? '0') ?? 0).round();
    agentIdleSecondsLive += (num.tryParse(s['idle_seconds']?.toString() ?? '0') ?? 0).round();
    storedDisconnectedSeconds += (num.tryParse(s['disconnected_seconds']?.toString() ?? '0') ?? 0).round();
  }

  final breakWindows = _breakWindowsFromLog(log, nowMs);
  final calculatedDisconnectedSeconds = isPurged
      ? ((num.tryParse(log['agent_disconnected_minutes']?.toString() ?? '0') ?? 0) * 60).round()
      : _disconnectedSecondsFromSessions(sessions, checkInIso, checkOutIso, nowMs, breakWindows);

  final disconnectedSeconds = calculatedDisconnectedSeconds;

  final agentActiveMinutes = isPurged
      ? ((num.tryParse(log['agent_active_minutes']?.toString() ?? '0') ?? 0).round()).clamp(0, 1 << 30)
      : (agentActiveSecondsLive / 60).round().clamp(0, 1 << 30);
  final agentIdleMinutes = isPurged
      ? ((num.tryParse(log['agent_idle_minutes']?.toString() ?? '0') ?? 0).round()).clamp(0, 1 << 30)
      : (agentIdleSecondsLive / 60).round().clamp(0, 1 << 30);

  final disconnectedMinutes = (disconnectedSeconds / 60).floor().clamp(0, 1 << 30);

  final idleMinutes = grossMin != null
      ? (manualBreakIdleMinutes + agentIdleMinutes + disconnectedMinutes).clamp(0, 1 << 30)
      : null;

  final calculatedActiveMinutes =
      grossMin != null && idleMinutes != null ? (grossMin - idleMinutes).clamp(0, 1 << 30) : null;

  final out = Map<String, dynamic>.from(log);
  out['grossMinutes'] = grossMin;
  out['activeMinutes'] = calculatedActiveMinutes;
  out['idleMinutes'] = idleMinutes;
  out['agentActiveMinutes'] = agentActiveMinutes;
  out['agentIdleMinutes'] = agentIdleMinutes;
  out['manualBreakIdleMinutes'] = manualBreakIdleMinutes;
  out['disconnectedMinutes'] = disconnectedMinutes;
  out['storedDisconnectedMinutes'] = (storedDisconnectedSeconds / 60).floor().clamp(0, 1 << 30);
  return out;
}
