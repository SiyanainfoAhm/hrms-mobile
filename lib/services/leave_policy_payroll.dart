// Subset of hrms-web `leavePolicy.ts` for payroll run (leave windows + balances).

import 'dart:math' as math;

class ApprovedLeave {
  const ApprovedLeave({
    required this.leaveTypeId,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
  });

  final String leaveTypeId;
  final String startDate;
  final String endDate;
  final num totalDays;
}

class LeavePolicy {
  const LeavePolicy({
    required this.leaveTypeId,
    required this.accrualMethod,
    required this.monthlyAccrualRate,
    required this.annualQuota,
    required this.prorateOnJoin,
    required this.resetMonth,
    required this.resetDay,
    required this.allowCarryover,
    required this.carryoverLimit,
  });

  final String leaveTypeId;
  final String accrualMethod;
  final double? monthlyAccrualRate;
  final double? annualQuota;
  final bool prorateOnJoin;
  final int resetMonth;
  final int resetDay;
  final bool allowCarryover;
  final double? carryoverLimit;
}

DateTime _utcMidnight(String ymd) {
  final s = ymd.length >= 10 ? ymd.substring(0, 10) : ymd;
  return DateTime.parse('${s}T00:00:00Z');
}

int _clampInt(int n, int min, int max) => n < min ? min : (n > max ? max : n);

DateTime leaveYearStart(DateTime asOf, int resetMonth, int resetDay) {
  final m = _clampInt(resetMonth, 1, 12) - 1;
  final day = _clampInt(resetDay, 1, 31);
  final candidateThisYear = DateTime.utc(asOf.year, m + 1, day);
  if (asOf.millisecondsSinceEpoch >= candidateThisYear.millisecondsSinceEpoch) return candidateThisYear;
  return DateTime.utc(asOf.year - 1, m + 1, day);
}

int monthsInclusive(DateTime from, DateTime to) {
  final fromY = from.year;
  final fromM = from.month - 1;
  final toY = to.year;
  final toM = to.month - 1;
  final diff = (toY * 12 + toM) - (fromY * 12 + fromM);
  return diff >= 0 ? diff + 1 : 0;
}

int overlapDaysInclusive(DateTime start, DateTime end, DateTime windowStart, DateTime windowEndExclusive) {
  final s = math.max(start.millisecondsSinceEpoch, windowStart.millisecondsSinceEpoch);
  final e = math.min(end.millisecondsSinceEpoch, windowEndExclusive.millisecondsSinceEpoch - 1);
  if (e < s) return 0;
  return ((e - s) / (24 * 60 * 60 * 1000)).floor() + 1;
}

int calendarSpanInclusiveYmd(String startYmd, String endYmd) {
  final sy = startYmd.length >= 10 ? startYmd.substring(0, 10) : startYmd;
  final ey = endYmd.length >= 10 ? endYmd.substring(0, 10) : endYmd;
  final s = _utcMidnight(sy).millisecondsSinceEpoch;
  final e = _utcMidnight(ey).millisecondsSinceEpoch;
  if (e < s) return 0;
  return ((e - s) / (24 * 60 * 60 * 1000)).floor() + 1;
}

({int overlapCalendarDays, double unitsInWindow}) leaveUnitsInWindow(
  String startYmd,
  String endYmd,
  num? totalDays,
  DateTime windowStart,
  DateTime windowEndExclusive,
) {
  final sy = startYmd.length >= 10 ? startYmd.substring(0, 10) : startYmd;
  final ey = endYmd.length >= 10 ? endYmd.substring(0, 10) : endYmd;
  final start = _utcMidnight(sy);
  final end = _utcMidnight(ey);
  final overlapCalendarDays = overlapDaysInclusive(start, end, windowStart, windowEndExclusive);
  if (overlapCalendarDays <= 0) return (overlapCalendarDays: 0, unitsInWindow: 0);
  final spanCal = calendarSpanInclusiveYmd(sy, ey);
  final spanSafe = math.max(1, spanCal);
  final totalRaw = totalDays;
  final totalSafe = totalRaw != null && totalRaw > 0 ? totalRaw.toDouble() : spanSafe.toDouble();
  return (overlapCalendarDays: overlapCalendarDays, unitsInWindow: totalSafe * (overlapCalendarDays / spanSafe));
}

double? computeEntitled(LeavePolicy policy, DateTime? joinDate, DateTime asOf) {
  final method = policy.accrualMethod;
  if (method == 'none') return null;

  final yearStart = leaveYearStart(asOf, policy.resetMonth, policy.resetDay);
  final eligibleStart = policy.prorateOnJoin && joinDate != null
      ? (joinDate.millisecondsSinceEpoch > yearStart.millisecondsSinceEpoch ? joinDate : yearStart)
      : yearStart;
  if (asOf.millisecondsSinceEpoch < eligibleStart.millisecondsSinceEpoch) return 0;

  if (method == 'monthly') {
    final rate = policy.monthlyAccrualRate ?? 0;
    final m = monthsInclusive(eligibleStart, asOf);
    final entitled = m * rate;
    final capped = policy.annualQuota == null ? entitled : math.min(entitled, policy.annualQuota!);
    return math.max(0, capped);
  }

  final q = policy.annualQuota == null ? 0.0 : policy.annualQuota!;
  return math.max(0, q);
}

double computeUsedDaysForYear(
  List<ApprovedLeave> leaves,
  String leaveTypeId,
  DateTime yearStart,
  DateTime yearEndExclusive,
) {
  var used = 0.0;
  for (final r in leaves) {
    if (r.leaveTypeId != leaveTypeId) continue;
    final sy = r.startDate.length >= 10 ? r.startDate.substring(0, 10) : r.startDate;
    final ey = r.endDate.length >= 10 ? r.endDate.substring(0, 10) : r.endDate;
    used += leaveUnitsInWindow(sy, ey, r.totalDays, yearStart, yearEndExclusive).unitsInWindow;
  }
  return used;
}
