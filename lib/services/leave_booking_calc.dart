import 'dart:convert';

/// Mirrors web `leaveBookingDays.ts`: Mon–Fri (UTC), holidays, overlap with pending/approved.

bool _isYmd(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

/// Monday–Friday in UTC for `yyyy-MM-dd` + `T00:00:00.000Z`.
bool isWeekendYmd(String ymd) {
  if (!_isYmd(ymd)) return false;
  final d = DateTime.parse('${ymd}T00:00:00.000Z');
  final w = d.weekday; // DateTime: Mon=1 .. Sun=7
  return w == DateTime.saturday || w == DateTime.sunday;
}

String _ymdUtc(DateTime d) {
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
}

List<String> eachYmdInRange(String startYmd, String endYmd) {
  if (!_isYmd(startYmd) || !_isYmd(endYmd) || endYmd.compareTo(startYmd) < 0) return [];
  final out = <String>[];
  var cur = DateTime.parse('${startYmd}T00:00:00.000Z');
  final end = DateTime.parse('${endYmd}T00:00:00.000Z');
  while (!cur.isAfter(end)) {
    out.add(_ymdUtc(cur));
    cur = cur.add(const Duration(days: 1));
  }
  return out;
}

Set<String> _expandHolidayToYmdSet(Map<String, dynamic> h, String? employeeDivisionId) {
  final set = <String>{};
  final start = (h['holiday_date'] ?? '').toString().trim().substring(0, 10);
  if (!_isYmd(start)) return set;
  final div = h['division_id']?.toString();
  final empDiv = employeeDivisionId?.trim();
  if (empDiv != null && empDiv.isNotEmpty) {
    if (div != null && div.isNotEmpty && div != empDiv) return set;
  }
  final endRaw = (h['holiday_end_date'] ?? '').toString().trim();
  final end = endRaw.length >= 10 && _isYmd(endRaw.substring(0, 10)) && endRaw.substring(0, 10).compareTo(start) >= 0
      ? endRaw.substring(0, 10)
      : start;
  set.addAll(eachYmdInRange(start, end));
  return set;
}

Set<String> buildHolidayYmdSet(List<Map<String, dynamic>> holidays, String? employeeDivisionId) {
  final acc = <String>{};
  for (final h in holidays) {
    acc.addAll(_expandHolidayToYmdSet(h, employeeDivisionId));
  }
  return acc;
}

bool rangesOverlapYmd(String aStart, String aEnd, String bStart, String bEnd) {
  if (!_isYmd(aStart) || !_isYmd(aEnd) || !_isYmd(bStart) || !_isYmd(bEnd)) return false;
  return !(aEnd.compareTo(bStart) < 0 || aStart.compareTo(bEnd) > 0);
}

Map<String, dynamic>? findBlockingLeaveOverlap(
  List<Map<String, dynamic>> existing,
  String startYmd,
  String endYmd,
) {
  for (final row in existing) {
    final st = (row['status'] ?? row['Status'] ?? '').toString().toLowerCase();
    if (st != 'pending' && st != 'approved') continue;
    final s = (row['startDate'] ?? row['start_date'] ?? '').toString().substring(0, 10);
    final e = (row['endDate'] ?? row['end_date'] ?? '').toString().substring(0, 10);
    if (!_isYmd(s) || !_isYmd(e)) continue;
    if (rangesOverlapYmd(startYmd, endYmd, s, e)) return row;
  }
  return null;
}

class LeaveBookingSummary {
  LeaveBookingSummary({
    required this.calendarSpanDays,
    required this.weekendDaysExcluded,
    required this.holidayDaysExcluded,
    required this.workingDaysInRange,
    required this.chargeableDays,
    this.overlapError,
  });

  final int calendarSpanDays;
  final int weekendDaysExcluded;
  final int holidayDaysExcluded;
  final int workingDaysInRange;
  final num chargeableDays;
  final String? overlapError;
}

LeaveBookingSummary computeLeaveBookingSummary({
  required String startYmd,
  required String endYmd,
  required List<Map<String, dynamic>> holidays,
  String? employeeDivisionId,
  required List<Map<String, dynamic>> existingLeaves,
  required String leaveTypeCodeUpper,
  bool isHalfDay = false,
}) {
  final overlap = findBlockingLeaveOverlap(existingLeaves, startYmd, endYmd);
  if (overlap != null) {
    return LeaveBookingSummary(
      calendarSpanDays: 0,
      weekendDaysExcluded: 0,
      holidayDaysExcluded: 0,
      workingDaysInRange: 0,
      chargeableDays: 0,
      overlapError: 'You already have leave (pending or approved) that overlaps these dates.',
    );
  }

  final days = eachYmdInRange(startYmd, endYmd);
  final holidaySet = buildHolidayYmdSet(holidays, employeeDivisionId);
  var weekendDaysExcluded = 0;
  var holidayDaysExcluded = 0;
  var workingDaysInRange = 0;
  for (final ymd in days) {
    if (isWeekendYmd(ymd)) {
      weekendDaysExcluded++;
      continue;
    }
    if (holidaySet.contains(ymd)) {
      holidayDaysExcluded++;
      continue;
    }
    workingDaysInRange++;
  }

  final code = leaveTypeCodeUpper.toUpperCase();
  final isHl = code == 'HL';
  num chargeable = 0;
  if (isHl) {
    chargeable = workingDaysInRange * 0.5;
  } else if (isHalfDay) {
    chargeable = workingDaysInRange >= 1 ? 0.5 : 0;
  } else {
    chargeable = workingDaysInRange;
  }

  return LeaveBookingSummary(
    calendarSpanDays: days.length,
    weekendDaysExcluded: weekendDaysExcluded,
    holidayDaysExcluded: holidayDaysExcluded,
    workingDaysInRange: workingDaysInRange,
    chargeableDays: chargeable,
    overlapError: null,
  );
}

Map<String, dynamic> parseOverlapRpc(dynamic res) {
  if (res is Map<String, dynamic>) return res;
  if (res is Map) return Map<String, dynamic>.from(res);
  if (res is String) {
    final j = jsonDecode(res);
    if (j is Map<String, dynamic>) return j;
    if (j is Map) return Map<String, dynamic>.from(j);
  }
  return {'employeeDivisionId': null, 'requests': <dynamic>[]};
}

List<Map<String, dynamic>> overlapRequestsFromJson(Map<String, dynamic> j) {
  final raw = j['requests'];
  if (raw is! List) return [];
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

String? employeeDivisionFromOverlapJson(Map<String, dynamic> j) {
  final v = j['employeeDivisionId'];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
