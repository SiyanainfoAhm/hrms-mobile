// Live Run payroll preview: ports hrms-web `src/app/api/payroll/run/route.ts`
// (`computeFreshPayrollPreviewFromMasters`, `computePreview`, attendance/leave, PL top-up).

import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'government_payroll_calc.dart';
import 'leave_balance_payroll.dart';
import 'leave_policy_payroll.dart';
import 'private_payroll_calc.dart';

const _minActiveHoursPresent = 8.0;
const _minActiveHoursHalfDay = 0.01;

String _ymd(dynamic v) => '${v ?? ''}'.toString().length >= 10 ? '${v ?? ''}'.toString().substring(0, 10) : '${v ?? ''}'.toString();

int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

String _toYmdUtc(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);

DateTime _utcMidnightFromYmd(String ymd) => DateTime.parse('${_ymd(ymd)}T00:00:00Z');

DateTime _addDaysUtc(DateTime d, int days) => DateTime.utc(d.year, d.month, d.day + days);

int _weekdayUtc(String ymd) => _utcMidnightFromYmd(ymd).weekday % 7;

Iterable<String> _iterateYmdInclusive(String startYmd, String endYmd) sync* {
  var d = _utcMidnightFromYmd(startYmd);
  final end = _utcMidnightFromYmd(endYmd);
  while (!d.isAfter(end)) {
    yield _toYmdUtc(d);
    d = _addDaysUtc(d, 1);
  }
}

int _countCalendarDaysInclusive(String startYmd, String endYmd) {
  if (startYmd.compareTo(endYmd) > 0) return 0;
  final s = _utcMidnightFromYmd(startYmd).millisecondsSinceEpoch;
  final e = _utcMidnightFromYmd(endYmd).millisecondsSinceEpoch;
  return ((e - s) / (24 * 60 * 60 * 1000)).floor() + 1;
}

int _effectiveLunchBreakMinutes({
  required int recordedLunchMinutes,
  required int grossWorkMinutes,
}) {
  final m = recordedLunchMinutes.clamp(0, 24 * 60);
  return math.min(m, math.max(0, grossWorkMinutes));
}

bool _isExplicitlyTrue(dynamic v) =>
    v == true || v == 1 || v == 'true' || v == 't' || v == 'TRUE' || v == '1';

bool _isExplicitlyFalse(dynamic v) =>
    v == false || v == 0 || v == 'false' || v == 'f' || v == 'FALSE' || v == '0';

bool _privatePfEligibleMerged(Map<String, dynamic> m, Map<String, dynamic>? u) {
  if (_isExplicitlyFalse(m['pf_eligible'])) return false;
  if (_isExplicitlyTrue(m['pf_eligible'])) return true;
  if (u != null) {
    if (_isExplicitlyFalse(u['pf_eligible'])) return false;
    if (_isExplicitlyTrue(u['pf_eligible'])) return true;
  }
  return true;
}

bool _privateEsicEligibleMerged(Map<String, dynamic> m, Map<String, dynamic>? u) {
  if (_isExplicitlyTrue(m['esic_eligible'])) return true;
  if (_isExplicitlyFalse(m['esic_eligible'])) return false;
  if (u != null && _isExplicitlyTrue(u['esic_eligible'])) return true;
  return false;
}

Map<String, int> _privateMonthlyComponentsFromMaster(
  Map<String, dynamic> m,
  int grossMonthly,
  PrivatePayrollConfig privateCfg,
) {
  final mb = (m['basic'] as num?)?.round() ?? 0;
  final mh = (m['hra'] as num?)?.round() ?? 0;
  final mm = (m['medical'] as num?)?.round() ?? 0;
  final mt = (m['trans'] as num?)?.round() ?? 0;
  final ml = (m['lta'] as num?)?.round() ?? 0;
  final mp = (m['personal'] as num?)?.round() ?? 0;
  final sum = mb + mh + mm + mt + ml + mp;
  if (sum > 0) {
    return {'mb': mb, 'mh': mh, 'mm': mm, 'mt': mt, 'ml': ml, 'mp': mp};
  }
  final d = defaultSalaryBreakup(grossMonthly, privateCfg);
  return {'mb': d.basic, 'mh': d.hra, 'mm': d.medical, 'mt': d.trans, 'ml': d.lta, 'mp': d.personal};
}

({int pfEmp, int pfEmpr, int esicEmp, int esicEmpr, int ctc}) _privateStatutoryMonthlyFromMaster(
  Map<String, dynamic> m,
  int profTaxMonthlyRounded,
  PrivatePayrollConfig privateCfg,
  Map<String, dynamic>? user,
) {
  final grossMonthly = (m['gross_salary'] as num?)?.round() ?? 0;
  final ctcMonthly = (m['ctc'] as num?)?.round() ?? 0;
  if (grossMonthly <= 0 && ctcMonthly <= 0) {
    return (pfEmp: 0, pfEmpr: 0, esicEmp: 0, esicEmpr: 0, ctc: 0);
  }
  final mb = (m['basic'] as num?)?.round() ?? 0;
  final mh = (m['hra'] as num?)?.round() ?? 0;
  final mm = (m['medical'] as num?)?.round() ?? 0;
  final mt = (m['trans'] as num?)?.round() ?? 0;
  final ml = (m['lta'] as num?)?.round() ?? 0;
  final mp = (m['personal'] as num?)?.round() ?? 0;
  final componentsSum = mb + mh + mm + mt + ml + mp;
  final salaryBreakup = componentsSum > 0
      ? PrivateSalaryBreakupInput(basic: mb, hra: mh, medical: mm, trans: mt, lta: ml, personal: mp)
      : null;
  final pfOk = _privatePfEligibleMerged(m, user);
  final esicOk = _privateEsicEligibleMerged(m, user);
  if (ctcMonthly > 0) {
    final calc = computePayrollFromCtc(ctcMonthly, pfOk, esicOk, profTaxMonthlyRounded, salaryBreakup, privateCfg);
    return (
      pfEmp: calc.pfEmp,
      pfEmpr: calc.pfEmpr,
      esicEmp: calc.esicEmp,
      esicEmpr: calc.esicEmpr,
      ctc: ctcMonthly,
    );
  }
  final calc = computePayrollFromGross(grossMonthly, pfOk, esicOk, profTaxMonthlyRounded, salaryBreakup, privateCfg);
  return (pfEmp: calc.pfEmp, pfEmpr: calc.pfEmpr, esicEmp: calc.esicEmp, esicEmpr: calc.esicEmpr, ctc: calc.ctc);
}

int _resolvePrivatePayrollMasterProfTax(
  Map<String, dynamic> m,
  PrivatePayrollConfig privateCfg,
  int ptFixedCompany,
) {
  final grossMonthly = (m['gross_salary'] as num?)?.round() ?? 0;
  final fromConfig = computeProfessionalTaxMonthly(grossMonthly, privateCfg, ptFixedCompany.toDouble());
  final mode = privateCfg.ptMode;
  if (mode != 'fixed') return fromConfig;
  final masterPt = m['pt'];
  final mp = num.tryParse('$masterPt');
  if (mp != null && mp.isFinite && mp >= 0) return mp.round();
  return fromConfig;
}

Future<PrivatePayrollConfig> _fetchCompanyPrivatePayrollConfig(SupabaseClient sb, String companyId) async {
  try {
    final cfgRow = await sb.from('HRMS_company_payroll_config').select('private_config').eq('company_id', companyId).maybeSingle();
    return normalizePrivatePayrollConfig(cfgRow?['private_config']);
  } catch (_) {
    return normalizePrivatePayrollConfig(null);
  }
}

Future<List<Map<String, dynamic>>> _fetchApplicablePayrollMasters(
  SupabaseClient sb,
  String companyId,
  String periodStart,
  String periodEnd,
) async {
  final start = _ymd(periodStart);
  final end = _ymd(periodEnd);
  final raw = await sb
      .from('HRMS_payroll_master')
      .select(
        'id, employee_user_id, payroll_mode, gross_salary, gross_basic, ctc, pf_employee, pf_employer, esic_employee, esic_employer, pf_eligible, esic_eligible, basic, hra, medical, trans, lta, personal, pt, tds, advance_bonus, da_percent, hra_percent, medical_fixed, transport_da_percent, income_tax_default, pt_default, lic_default, cpf_default, da_cpf_default, vpf_default, pf_loan_default, post_office_default, credit_society_default, std_licence_fee_default, electricity_default, water_default, mess_default, horticulture_default, welfare_default, veh_charge_default, other_deduction_default, effective_start_date, effective_end_date',
      )
      .eq('company_id', companyId)
      .or('effective_end_date.is.null,effective_end_date.gte.$start');

  final rows = (raw as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .where((r) {
        final s = _ymd(r['effective_start_date'] ?? '0000-01-01');
        final e = r['effective_end_date'] != null ? _ymd(r['effective_end_date']) : null;
        if (s.compareTo(end) > 0) return false;
        if (e != null && e.compareTo(start) < 0) return false;
        return true;
      })
      .toList();

  final byUser = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final uid = '${r['employee_user_id'] ?? ''}';
    if (uid.isEmpty) continue;
    final prev = byUser[uid];
    final curStart = _ymd(r['effective_start_date'] ?? '0000-01-01');
    final prevStart = prev != null ? _ymd(prev['effective_start_date'] ?? '0000-01-01') : '';
    if (prev == null || curStart.compareTo(prevStart) > 0) byUser[uid] = r;
  }
  return byUser.values.toList();
}

Future<Map<String, double>> _fetchApprovedReimbursementTotalsByUser(
  SupabaseClient sb,
  String companyId,
  int year,
  int month,
) async {
  final data = await sb
      .from('HRMS_reimbursements')
      .select('employee_user_id, amount, claim_date')
      .eq('company_id', companyId)
      .eq('status', 'approved')
      .filter('included_in_payroll_period_id', 'is', null);
  final map = <String, double>{};
  for (final rAny in (data as List)) {
    final r = Map<String, dynamic>.from(rAny as Map);
    final cd = _ymd(r['claim_date']);
    final m = RegExp(r'^(\d{4})-(\d{2})-\d{2}').firstMatch(cd);
    if (m == null) continue;
    if (int.parse(m.group(1)!) != year || int.parse(m.group(2)!) != month) continue;
    final uid = '${r['employee_user_id'] ?? ''}';
    if (uid.isEmpty) continue;
    final amt = (r['amount'] as num?)?.toDouble() ?? 0;
    map[uid] = (map[uid] ?? 0) + amt;
  }
  return map;
}

({int overlapDays, double paidDays, double unpaidDays, Set<String> leaveDays}) _computeLeavePaidUnpaidInWindow(
  Map<String, dynamic> leave,
  String windowStartYmd,
  DateTime windowEndExclusive,
) {
  final leaveDays = <String>{};
  final startYmd = _ymd(leave['start_date']);
  final endYmd = _ymd(leave['end_date']);
  final windowStart = _utcMidnightFromYmd(windowStartYmd);
  final win = leaveUnitsInWindow(startYmd, endYmd, leave['total_days'] as num?, windowStart, windowEndExclusive);
  if (win.overlapCalendarDays <= 0) {
    return (overlapDays: 0, paidDays: 0, unpaidDays: 0, leaveDays: leaveDays);
  }

  final start = _utcMidnightFromYmd(startYmd);
  final overlapStart = start.millisecondsSinceEpoch > windowStart.millisecondsSinceEpoch ? _toYmdUtc(start) : windowStartYmd;
  final overlapEndInclusive = _toYmdUtc(DateTime.fromMillisecondsSinceEpoch(windowEndExclusive.millisecondsSinceEpoch - 24 * 60 * 60 * 1000, isUtc: true));
  final end = _utcMidnightFromYmd(endYmd);
  final endStr = _toYmdUtc(end);
  final effectiveEndInclusive = _utcMidnightFromYmd(endStr).millisecondsSinceEpoch < _utcMidnightFromYmd(overlapEndInclusive).millisecondsSinceEpoch ? endStr : overlapEndInclusive;

  for (final y in _iterateYmdInclusive(overlapStart, effectiveEndInclusive)) {
    leaveDays.add(y);
  }

  final ltRaw = leave['HRMS_leave_types'];
  Map<String, dynamic>? ltObj;
  if (ltRaw is Map) ltObj = Map<String, dynamic>.from(ltRaw);
  if (ltRaw is List && ltRaw.isNotEmpty && ltRaw.first is Map) ltObj = Map<String, dynamic>.from(ltRaw.first as Map);
  final isPaidType = ltObj?['is_paid'] != false;

  final totalRow = (leave['total_days'] as num?)?.toDouble();
  final totalForSplit = (totalRow != null && totalRow > 0) ? totalRow : win.overlapCalendarDays.toDouble();
  final unpaidTotal = (leave['unpaid_days'] as num?)?.toDouble();
  final unpaidSafe = (unpaidTotal != null && unpaidTotal >= 0) ? unpaidTotal : 0.0;
  final unpaidInOverlap = isPaidType
      ? (totalForSplit > 0 ? win.unitsInWindow * (unpaidSafe / totalForSplit) : 0.0)
      : win.unitsInWindow;
  final paidInOverlap = isPaidType ? math.max(0.0, win.unitsInWindow - unpaidInOverlap) : 0.0;
  return (overlapDays: win.overlapCalendarDays, paidDays: paidInOverlap, unpaidDays: unpaidInOverlap, leaveDays: leaveDays);
}

Future<
    ({
      Map<String, double> presentDaysByUser,
      Map<String, double> paidLeaveDaysByUser,
      Map<String, double> unpaidLeaveDaysByUser,
      Map<String, Set<String>> presentDatesByUser,
      Map<String, Set<String>> leaveDaysByUser,
      Map<String, double> shortHoursUnpaidDaysByUser,
    })> _computeAttendanceDrivenPayDays(
  SupabaseClient sb, {
  required String companyId,
  required List<String> userIds,
  required String periodStartYmd,
  required DateTime periodEndExclusive,
}) async {
  final presentDaysByUser = <String, double>{};
  final paidLeaveDaysByUser = <String, double>{};
  final unpaidLeaveDaysByUser = <String, double>{};
  final presentDatesByUser = <String, Set<String>>{};
  final leaveDaysByUser = <String, Set<String>>{};
  final shortHoursUnpaidDaysByUser = <String, double>{};

  final employees = await sb.from('HRMS_employees').select('id, user_id').eq('company_id', companyId).inFilter('user_id', userIds);
  final employeeIdByUser = <String, String>{};
  for (final eAny in (employees as List)) {
    final e = Map<String, dynamic>.from(eAny as Map);
    final uid = '${e['user_id'] ?? ''}';
    final id = '${e['id'] ?? ''}';
    if (uid.isNotEmpty && id.isNotEmpty) employeeIdByUser[uid] = id;
  }
  final employeeIds = employeeIdByUser.values.toList();

  final leavesRaw = await sb
      .from('HRMS_leave_requests')
      .select('employee_user_id, start_date, end_date, total_days, paid_days, unpaid_days, HRMS_leave_types(is_paid)')
      .eq('company_id', companyId)
      .eq('status', 'approved')
      .inFilter('employee_user_id', userIds);

  for (final lAny in (leavesRaw as List)) {
    final l = Map<String, dynamic>.from(lAny as Map);
    final uid = '${l['employee_user_id'] ?? ''}';
    if (uid.isEmpty) continue;
    final r = _computeLeavePaidUnpaidInWindow(l, periodStartYmd, periodEndExclusive);
    if (r.overlapDays <= 0) continue;
    paidLeaveDaysByUser[uid] = (paidLeaveDaysByUser[uid] ?? 0) + r.paidDays;
    unpaidLeaveDaysByUser[uid] = (unpaidLeaveDaysByUser[uid] ?? 0) + r.unpaidDays;
    final set = leaveDaysByUser.putIfAbsent(uid, () => <String>{});
    set.addAll(r.leaveDays);
  }

  if (employeeIds.isEmpty) {
    return (
      presentDaysByUser: presentDaysByUser,
      paidLeaveDaysByUser: paidLeaveDaysByUser,
      unpaidLeaveDaysByUser: unpaidLeaveDaysByUser,
      presentDatesByUser: presentDatesByUser,
      leaveDaysByUser: leaveDaysByUser,
      shortHoursUnpaidDaysByUser: shortHoursUnpaidDaysByUser,
    );
  }

  final periodEndYmdInclusive = _toYmdUtc(DateTime.fromMillisecondsSinceEpoch(periodEndExclusive.millisecondsSinceEpoch - 24 * 60 * 60 * 1000, isUtc: true));
  final att = await sb
      .from('HRMS_attendance_logs')
      .select(
        'employee_id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_check_out_at, lunch_check_in_at',
      )
      .eq('company_id', companyId)
      .inFilter('employee_id', employeeIds)
      .gte('work_date', periodStartYmd)
      .lte('work_date', periodEndYmdInclusive);

  final userIdByEmployeeId = <String, String>{};
  for (final e in employeeIdByUser.entries) {
    userIdByEmployeeId[e.value] = e.key;
  }

  final nowUtc = DateTime.now().toUtc();
  for (final rowAny in (att as List)) {
    final row = Map<String, dynamic>.from(rowAny as Map);
    final eid = '${row['employee_id'] ?? ''}';
    if (eid.isEmpty) continue;
    final uid = userIdByEmployeeId[eid];
    if (uid == null) continue;

    final workDate = _ymd(row['work_date']);
    if (leaveDaysByUser[uid]?.contains(workDate) == true) continue;

    final teaMin = ((row['tea_break_minutes'] as num?)?.round() ?? 0).clamp(0, 24 * 60);
    int? durationMinutes;
    final inAt = row['check_in_at'] != null ? DateTime.tryParse('${row['check_in_at']}')?.toUtc() : null;
    final outAt = row['check_out_at'] != null ? DateTime.tryParse('${row['check_out_at']}')?.toUtc() : null;
    if (inAt != null && outAt != null) {
      durationMinutes = math.max(0, ((outAt.millisecondsSinceEpoch - inAt.millisecondsSinceEpoch) / 60000).round());
    } else if (inAt != null) {
      durationMinutes = math.max(0, ((nowUtc.millisecondsSinceEpoch - inAt.millisecondsSinceEpoch) / 60000).round());
    } else if (row['total_hours'] != null) {
      final th = (row['total_hours'] as num?)?.toDouble() ?? 0;
      durationMinutes = math.max(0, (th * 60).round());
    }
    if (durationMinutes == null) continue;

    final lunchMin = _effectiveLunchBreakMinutes(
      recordedLunchMinutes: (row['lunch_break_minutes'] as num?)?.round() ?? 0,
      grossWorkMinutes: durationMinutes,
    );
    final breakMin = lunchMin + teaMin;
    final activeMinutes = math.max(0, durationMinutes - breakMin);
    final activeHours = activeMinutes / 60.0;

    if (activeHours >= _minActiveHoursPresent) {
      presentDaysByUser[uid] = (presentDaysByUser[uid] ?? 0) + 1;
      presentDatesByUser.putIfAbsent(uid, () => <String>{}).add(workDate);
    } else if (activeHours >= _minActiveHoursHalfDay) {
      presentDaysByUser[uid] = (presentDaysByUser[uid] ?? 0) + 0.5;
      shortHoursUnpaidDaysByUser[uid] = (shortHoursUnpaidDaysByUser[uid] ?? 0) + 0.5;
      presentDatesByUser.putIfAbsent(uid, () => <String>{}).add(workDate);
    }
  }

  for (final uid in userIds) {
    final qualifying = presentDatesByUser[uid] ?? <String>{};
    var weekendAdded = 0;
    for (final y in _iterateYmdInclusive(periodStartYmd, periodEndYmdInclusive)) {
      final dow = _weekdayUtc(y);
      if (dow != 6 && dow != 0) continue;
      if (qualifying.contains(y)) continue;
      final d = _utcMidnightFromYmd(y);
      final prevFri = _toYmdUtc(_addDaysUtc(d, dow == 6 ? -1 : -2));
      final nextMon = _toYmdUtc(_addDaysUtc(d, dow == 6 ? 2 : 1));
      final friInRange = prevFri.compareTo(periodStartYmd) >= 0 && prevFri.compareTo(periodEndYmdInclusive) <= 0;
      final monInRange = nextMon.compareTo(periodStartYmd) >= 0 && nextMon.compareTo(periodEndYmdInclusive) <= 0;
      final friPresent = friInRange && qualifying.contains(prevFri);
      final monPresent = monInRange && qualifying.contains(nextMon);
      if (friPresent || monPresent) {
        weekendAdded++;
        qualifying.add(y);
      }
    }
    if (weekendAdded > 0) {
      presentDatesByUser[uid] = qualifying;
      presentDaysByUser[uid] = (presentDaysByUser[uid] ?? 0) + weekendAdded;
    }
  }

  return (
    presentDaysByUser: presentDaysByUser,
    paidLeaveDaysByUser: paidLeaveDaysByUser,
    unpaidLeaveDaysByUser: unpaidLeaveDaysByUser,
    presentDatesByUser: presentDatesByUser,
    leaveDaysByUser: leaveDaysByUser,
    shortHoursUnpaidDaysByUser: shortHoursUnpaidDaysByUser,
  );
}

Future<Map<String, double>> _loadPaidLeaveRemainingByUser(
  SupabaseClient sb, {
  required String companyId,
  required List<String> userIds,
  required Map<String, String?> joinDateByUserId,
  required String asOfYmd,
}) async {
  final policiesRaw = await sb
      .from('HRMS_leave_policies')
      .select('*, HRMS_leave_types(id, name, is_paid, code, payslip_slot)')
      .eq('company_id', companyId);

  final paidPolicies = <Map<String, dynamic>>[];
  for (final pAny in (policiesRaw as List)) {
    final p = Map<String, dynamic>.from(pAny as Map);
    final t = p['HRMS_leave_types'];
    final tObj = t is List && t.isNotEmpty ? t.first : t;
    if (tObj is Map && tObj['is_paid'] == true) paidPolicies.add(p);
  }
  if (paidPolicies.isEmpty) return {};

  final policyRows = paidPolicies.map((p) {
    final t = p['HRMS_leave_types'];
    final tObj = t is List && t.isNotEmpty
        ? Map<String, dynamic>.from(t.first as Map)
        : (t is Map ? Map<String, dynamic>.from(t) : <String, dynamic>{});
    return LeavePolicyWithTypeRow(
      leaveTypeId: '${p['leave_type_id'] ?? ''}',
      accrualMethod: '${p['accrual_method'] ?? 'none'}',
      monthlyAccrualRate: (p['monthly_accrual_rate'] as num?)?.toDouble(),
      annualQuota: (p['annual_quota'] as num?)?.toDouble(),
      prorateOnJoin: p['prorate_on_join'] == true,
      resetMonth: (p['reset_month'] as num?)?.round(),
      resetDay: (p['reset_day'] as num?)?.round(),
      allowCarryover: p['allow_carryover'] as bool?,
      carryoverLimit: (p['carryover_limit'] as num?)?.toDouble(),
      leaveTypeName: tObj['name']?.toString(),
      payslipSlot: tObj['payslip_slot']?.toString(),
      isPaid: tObj['is_paid'] == true,
    );
  }).toList();

  final paidTypeIds = policyRows.map((p) => p.leaveTypeId).where((id) => id.isNotEmpty).toList();
  if (paidTypeIds.isEmpty) return {};

  final leavesRaw = await sb
      .from('HRMS_leave_requests')
      .select('employee_user_id, leave_type_id, start_date, end_date, total_days')
      .eq('company_id', companyId)
      .eq('status', 'approved')
      .inFilter('employee_user_id', userIds)
      .inFilter('leave_type_id', paidTypeIds);

  final approvedByUser = <String, List<ApprovedLeave>>{};
  for (final rAny in (leavesRaw as List)) {
    final r = Map<String, dynamic>.from(rAny as Map);
    final uid = '${r['employee_user_id'] ?? ''}';
    if (uid.isEmpty) continue;
    approvedByUser.putIfAbsent(uid, () => []).add(
          ApprovedLeave(
            leaveTypeId: '${r['leave_type_id'] ?? ''}',
            startDate: _ymd(r['start_date']),
            endDate: _ymd(r['end_date']),
            totalDays: (r['total_days'] as num?) ?? 0,
          ),
        );
  }

  final remainingByUser = <String, double>{};
  for (final uid in userIds) {
    final join = joinDateByUserId[uid];
    final rows = computeLeaveBalanceRows(policyRows, approvedByUser[uid] ?? [], join, asOfYmd);
    final remaining = rows.fold<double>(0, (sum, r) => sum + (r.remaining ?? 0));
    remainingByUser[uid] = math.max(0, remaining);
  }
  return remainingByUser;
}

Future<List<Map<String, dynamic>>> _computeFreshPayrollPreviewFromMasters(
  SupabaseClient sb, {
  required String companyId,
  required int year,
  required int month,
  required int runDay,
  required String periodStart,
  required String periodEnd,
  required int daysInMonth,
  required int effectiveRunDay,
}) async {
  final todayYmd = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final isFuturePeriod = periodStart.compareTo(todayYmd) > 0;

  final company = await sb.from('HRMS_companies').select('professional_tax_monthly').eq('id', companyId).single();
  final ptFixed = company['professional_tax_monthly'] != null ? ((company['professional_tax_monthly'] as num).round()) : 200;
  final privateCfg = await _fetchCompanyPrivatePayrollConfig(sb, companyId);

  final monthEnd = DateTime.utc(year, month + 1, 0).toIso8601String().substring(0, 10);
  final masters = await _fetchApplicablePayrollMasters(sb, companyId, periodStart, monthEnd);
  if (masters.isEmpty) return [];

  final userIds = masters.map((m) => '${m['employee_user_id'] ?? ''}').where((id) => id.isNotEmpty).toList();
  final usersRaw = await sb
      .from('HRMS_users')
      .select('id, name, email, date_of_joining, date_of_leaving, role, government_pay_level, pf_eligible, esic_eligible')
      .inFilter('id', userIds);

  final userById = <String, Map<String, dynamic>>{};
  for (final uAny in (usersRaw as List)) {
    final u = Map<String, dynamic>.from(uAny as Map);
    userById['${u['id']}'] = u;
  }

  final periodStartDate = _utcMidnightFromYmd(periodStart);
  final periodEndExclusive = DateTime.utc(year, month, effectiveRunDay + 1);

  final att = await _computeAttendanceDrivenPayDays(
    sb,
    companyId: companyId,
    userIds: userIds,
    periodStartYmd: periodStart,
    periodEndExclusive: periodEndExclusive,
  );

  final reimbByUser = isFuturePeriod ? <String, double>{} : await _fetchApprovedReimbursementTotalsByUser(sb, companyId, year, month);

  final periodEndYmdInclusive = _toYmdUtc(DateTime.fromMillisecondsSinceEpoch(periodEndExclusive.millisecondsSinceEpoch - 24 * 60 * 60 * 1000, isUtc: true));

  final joinDateByUserId = <String, String?>{};
  for (final u in userById.values) {
    final id = '${u['id']}';
    joinDateByUserId[id] = u['date_of_joining'] != null ? _ymd(u['date_of_joining']) : null;
  }

  final plRemainingByUser = isFuturePeriod
      ? <String, double>{}
      : await _loadPaidLeaveRemainingByUser(
          sb,
          companyId: companyId,
          userIds: userIds,
          joinDateByUserId: joinDateByUserId,
          asOfYmd: periodEndYmdInclusive,
        );

  final rows = <Map<String, dynamic>>[];

  for (final m in masters) {
    final uid = '${m['employee_user_id'] ?? ''}';
    final u = userById[uid];
    if (u == null || u['role'] == 'super_admin') continue;

    final doj = u['date_of_joining'] != null ? _utcMidnightFromYmd(_ymd(u['date_of_joining'])) : null;
    final dol = u['date_of_leaving'] != null ? _utcMidnightFromYmd(_ymd(u['date_of_leaving'])) : null;

    if (dol != null && dol.isBefore(periodStartDate)) continue;
    if (doj != null && !doj.isBefore(periodEndExclusive)) continue;

    final employmentStart = (doj != null && doj.isAfter(periodStartDate)) ? doj : periodStartDate;
    final employmentEndInclusive = (dol != null && dol.isBefore(DateTime.fromMillisecondsSinceEpoch(periodEndExclusive.millisecondsSinceEpoch - 1, isUtc: true)))
        ? dol
        : DateTime.fromMillisecondsSinceEpoch(periodEndExclusive.millisecondsSinceEpoch - 1, isUtc: true);
    final eligibleStartYmd = _toYmdUtc(employmentStart);
    final eligibleEndYmd = _toYmdUtc(employmentEndInclusive);
    final eligStartYmd = eligibleStartYmd.compareTo(periodStart) > 0 ? eligibleStartYmd : periodStart;
    final eligEndYmd = eligibleEndYmd.compareTo(periodEndYmdInclusive) < 0 ? eligibleEndYmd : periodEndYmdInclusive;
    final eligibleCalendarDays = _countCalendarDaysInclusive(eligStartYmd, eligEndYmd);

    var unpaidLeaveDays = att.unpaidLeaveDaysByUser[uid] ?? 0.0;

    if (!isFuturePeriod) {
      final plRemaining = plRemainingByUser[uid] ?? 0;
      final plCover = math.min(plRemaining, unpaidLeaveDays);
      if (plCover > 0) unpaidLeaveDays -= plCover;
    }

    // Web `computeFreshPayrollPreviewFromMasters`: calendar employment window minus unpaid leave
    // (after PL top-up). Attendance populates present dates used only for holiday overlap checks.
    final rawPayDaysFromCalendar = math.max(0.0, eligibleCalendarDays.toDouble() - unpaidLeaveDays);

    if ('${m['payroll_mode'] ?? 'private'}' == 'government') {
      final gbMaster = (m['gross_basic'] as num?)?.round() ?? 0;
      final grossBasic = gbMaster != 0 ? gbMaster : ((m['gross_salary'] as num?)?.round() ?? 0);
      if (grossBasic <= 0) continue;
      if (u['government_pay_level'] == null) {
        rows.add({
          'employeeUserId': uid,
          'employeeName': u['name'],
          'employeeEmail': u['email'] ?? '',
          'payrollMode': 'government',
          'error': 'Missing government pay level on employee profile',
        });
        continue;
      }
      final payLevel = (u['government_pay_level'] as num).round();
      final comp = computeGovernmentMonthlyPayroll(
        GovernmentMonthlyInput(
          grossBasic: grossBasic,
          daPercent: (m['da_percent'] as num?)?.toDouble() ?? 53,
          hraPercent: (m['hra_percent'] as num?)?.toDouble() ?? 30,
          medicalFixed: (m['medical_fixed'] as num?)?.round() ?? 3000,
          transportDaPercent: (m['transport_da_percent'] as num?)?.toDouble() ?? 48.06,
          payLevel: payLevel,
          daysInMonth: daysInMonth,
          unpaidDays: math.max(0, daysInMonth - rawPayDaysFromCalendar).toDouble(),
          deductionDefaults: masterRowToDeductionDefaults(m),
        ),
      );
      final paidDaysGov = math.max(0.0, rawPayDaysFromCalendar);
      final reimbursement = (reimbByUser[uid] ?? 0).round();
      final advMonthG = (m['advance_bonus'] as num?)?.round() ?? 0;
      final takeHome = comp.netSalary + advMonthG + reimbursement;
      final cpfStatutory =
          (comp.deductions.cpf + comp.deductions.daCpf + comp.deductions.vpf + comp.deductions.pfLoan).round();
      rows.add({
        'employeeUserId': uid,
        'employeeName': u['name'],
        'employeeEmail': u['email'] ?? '',
        'payrollMode': 'government',
        'payDays': paidDaysGov,
        'rawPayDays': paidDaysGov,
        'unpaidLeaveDays': unpaidLeaveDays,
        'grossMonthly': grossBasic,
        'grossPay': comp.totalEarnings,
        'deductions': comp.totalDeductions,
        'netPay': comp.netSalary,
        'takeHome': takeHome.round(),
        'tds': comp.deductions.incomeTax.round(),
        'incentive': advMonthG,
        'prBonus': 0,
        'reimbursement': reimbursement,
        'profTax': comp.deductions.pt,
        'governmentMonthly': _govMonthlyToJson(comp),
        'govRecalc': {
          'grossBasic': grossBasic,
          'daPercent': (m['da_percent'] as num?)?.toDouble() ?? 53,
          'hraPercent': (m['hra_percent'] as num?)?.toDouble() ?? 30,
          'medicalFixed': (m['medical_fixed'] as num?)?.round() ?? 3000,
          'transportDaPercent': (m['transport_da_percent'] as num?)?.toDouble() ?? 48.06,
          'payLevel': payLevel,
          'deductionDefaults': _deductionDefaultsToJson(masterRowToDeductionDefaults(m)),
        },
        'ctc': ((m['ctc'] as num?)?.round() ?? grossBasic),
        'ctcBase': ((m['ctc'] as num?)?.round() ?? grossBasic),
        'pfEmployee': cpfStatutory,
        'pfEmployer': 0,
        'esicEmployee': 0,
        'esicEmployer': 0,
      });
      continue;
    }

    final payDays = math.max(0.0, rawPayDaysFromCalendar);
    final rawPayDays = payDays;

    final grossMonthly = (m['gross_salary'] as num?)?.round() ?? 0;
    if (grossMonthly <= 0) continue;

    final ratio = payDays / math.max(1, daysInMonth);
    final compM = _privateMonthlyComponentsFromMaster(m, grossMonthly, privateCfg);
    final profTax = _resolvePrivatePayrollMasterProfTax(m, privateCfg, ptFixed);
    final profTaxMonthly = profTax.round();
    final statM = _privateStatutoryMonthlyFromMaster(m, profTaxMonthly, privateCfg, u);
    final pfEmp = statM.pfEmp * (payDays / math.max(1, daysInMonth));
    final pfEmpr = statM.pfEmpr * (payDays / math.max(1, daysInMonth));
    final esicEmp = statM.esicEmp * (payDays / math.max(1, daysInMonth));
    final esicEmpr = statM.esicEmpr * (payDays / math.max(1, daysInMonth));
    final grossPay = payDays > 0 ? ((grossMonthly * payDays) / math.max(1, daysInMonth)).round() : 0;
    final basicPay = (compM['mb']! * ratio).round();
    final hraPay = (compM['mh']! * ratio).round();
    final medicalPay = (compM['mm']! * ratio).round();
    final transPay = (compM['mt']! * ratio).round();
    final ltaPay = (compM['ml']! * ratio).round();
    final personalPay = (compM['mp']! * ratio).round();
    final profTaxApplied = payDays > 0 ? profTaxMonthly : 0;
    final deductions = (pfEmp + esicEmp + profTaxApplied).round();
    final netPay = grossPay - deductions;
    final tdsMonth = (m['tds'] as num?)?.round() ?? 0;
    final advMonth = (m['advance_bonus'] as num?)?.round() ?? 0;
    final incentive = (advMonth * ratio).round();
    final reimbursement = (reimbByUser[uid] ?? 0).round();
    final tds = tdsMonth;
    final takeHome = netPay - tds + incentive + reimbursement;
    final pfEmployerRounded = pfEmpr.round();
    final esicEmployerRounded = esicEmpr.round();
    final ctcBase = (grossPay + pfEmployerRounded + esicEmployerRounded).round();

    rows.add({
      'employeeUserId': uid,
      'employeeName': u['name'],
      'employeeEmail': u['email'] ?? '',
      'payrollMode': 'private',
      'payDays': payDays,
      'rawPayDays': rawPayDays,
      'unpaidLeaveDays': unpaidLeaveDays,
      'grossMonthly': grossMonthly,
      'grossPay': grossPay,
      'basicPay': basicPay,
      'hraPay': hraPay,
      'medicalPay': medicalPay,
      'transPay': transPay,
      'ltaPay': ltaPay,
      'personalPay': personalPay,
      'pfEmployee': pfEmp.round(),
      'pfEmployer': pfEmployerRounded,
      'esicEmployee': esicEmp.round(),
      'esicEmployer': esicEmployerRounded,
      'profTax': profTaxApplied,
      'profTaxMonthly': profTaxMonthly,
      'deductions': deductions,
      'netPay': netPay,
      'incentive': incentive,
      'prBonus': 0,
      'reimbursement': reimbursement,
      'tds': tds,
      'takeHome': takeHome,
      'ctc': ctcBase + incentive,
      'ctcBase': ctcBase,
      'pfEligible': _privatePfEligibleMerged(m, u),
      'esicEligible': _privateEsicEligibleMerged(m, u),
    });
  }

  return rows;
}

Map<String, dynamic> _deductionDefaultsToJson(GovernmentDeductionDefaults d) => {
      'incomeTax': d.incomeTax,
      'pt': d.pt,
      'lic': d.lic,
      'cpf': d.cpf,
      'daCpf': d.daCpf,
      'vpf': d.vpf,
      'pfLoan': d.pfLoan,
      'postOffice': d.postOffice,
      'creditSociety': d.creditSociety,
      'stdLicenceFee': d.stdLicenceFee,
      'electricity': d.electricity,
      'water': d.water,
      'mess': d.mess,
      'horticulture': d.horticulture,
      'welfare': d.welfare,
      'vehCharge': d.vehCharge,
      'other': d.other,
    };

Map<String, dynamic> _govMonthlyToJson(GovernmentMonthlyComputed c) => {
      'net_salary': c.netSalary,
      'total_earnings': c.totalEarnings,
      'total_deductions': c.totalDeductions,
      'basicPaid': c.basicPaid,
      'daPaid': c.daPaid,
      'hraPaid': c.hraPaid,
      'medicalPaid': c.medicalPaid,
      'transportPaid': c.transportPaid,
      'deductions': _deductionDefaultsToJson(c.deductions),
    };

Map<String, dynamic> _mapSavedPayslipToPreviewRow(Map<String, dynamic> p, Map<String, dynamic>? u, Map<String, dynamic>? gov) {
  final net = (p['net_pay'] as num?)?.toDouble() ?? 0;
  final tds = (p['tds'] as num?)?.toDouble() ?? 0;
  final inc = (p['incentive'] as num?)?.toDouble() ?? 0;
  final bonus = (p['pr_bonus'] as num?)?.toDouble() ?? 0;
  final reimb = (p['reimbursement'] as num?)?.toDouble() ?? 0;
  final takeHome = (net - tds + inc + bonus + reimb).round();
  final isGov = p['payroll_mode'] == 'government' || (gov != null && gov.isNotEmpty);
  return {
    'employeeUserId': p['employee_user_id'],
    'employeeName': u?['name'],
    'employeeEmail': u?['email'] ?? '',
    'payDays': (p['pay_days'] as num?)?.toDouble() ?? 0,
    'unpaidLeaveDays': gov != null ? ((gov['unpaid_days'] as num?)?.toDouble() ?? 0) : 0.0,
    'grossPay': ((p['gross_pay'] as num?) ?? 0).round(),
    'pfEmployee': ((p['pf_employee'] as num?) ?? 0).round(),
    'pfEmployer': ((p['pf_employer'] as num?) ?? 0).round(),
    'esicEmployee': ((p['esic_employee'] as num?) ?? 0).round(),
    'esicEmployer': ((p['esic_employer'] as num?) ?? 0).round(),
    'profTax': ((p['professional_tax'] as num?) ?? 0).round(),
    'deductions': ((p['deductions'] as num?) ?? 0).round(),
    'netPay': net.round(),
    'incentive': inc,
    'prBonus': bonus,
    'reimbursement': reimb,
    'tds': tds,
    'takeHome': takeHome,
    'ctc': ((p['ctc'] as num?) ?? 0).round(),
    'payrollMode': isGov ? 'government' : 'private',
    'governmentMonthly': gov,
    'payslipPending': false,
  };
}

/// Managerial gate + full preview (fresh rows merged with stored payslips when period exists).
Future<Map<String, dynamic>> computePayrollRunPreview(
  SupabaseClient sb, {
  required String actorUserId,
  required int year,
  required int month,
  required int runDay,
}) async {
  final actor = await sb.from('HRMS_users').select('company_id, role').eq('id', actorUserId).maybeSingle();
  if (actor == null) throw StateError('User not found');
  final companyId = '${actor['company_id'] ?? ''}';
  final role = '${actor['role'] ?? ''}';
  if (companyId.isEmpty) {
    return _emptyPreview(year, month, runDay);
  }
  if (!['super_admin', 'admin', 'hr'].contains(role)) {
    throw StateError('Forbidden');
  }

  final daysInMonth = _daysInMonth(year, month);
  final selectedMonthStart = DateTime.utc(year, month, 1).toIso8601String().substring(0, 10);
  final now = DateTime.now().toUtc();
  final currentMonthStart = DateTime.utc(now.year, now.month, 1).toIso8601String().substring(0, 10);
  final isFutureMonth = selectedMonthStart.compareTo(currentMonthStart) > 0;
  final effectiveRunDay = isFutureMonth ? daysInMonth : math.min(math.max(1, runDay), daysInMonth);
  final periodStart = DateTime.utc(year, month, 1).toIso8601String().substring(0, 10);
  final periodEnd = DateTime.utc(year, month, effectiveRunDay).toIso8601String().substring(0, 10);
  const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final periodName = '${monthNames[month]}-${year.toString().substring(2)}';

  final workingDaysInFullMonth = math.max(1, daysInMonth);
  final workingDaysThroughRunDay = math.max(1, effectiveRunDay);

  final existingPeriod = await sb.from('HRMS_payroll_periods').select('id').eq('company_id', companyId).eq('period_start', periodStart).maybeSingle();

  final periodCtx = {
    'periodName': periodName,
    'periodStart': periodStart,
    'periodEnd': periodEnd,
    'daysInMonth': daysInMonth,
    'workingDaysInFullMonth': workingDaysInFullMonth,
    'workingDaysThroughRunDay': workingDaysThroughRunDay,
    'effectiveRunDay': effectiveRunDay,
  };

  final freshRows = await _computeFreshPayrollPreviewFromMasters(
    sb,
    companyId: companyId,
    year: year,
    month: month,
    runDay: runDay,
    periodStart: periodStart,
    periodEnd: periodEnd,
    daysInMonth: daysInMonth,
    effectiveRunDay: effectiveRunDay,
  );

  if (existingPeriod == null || existingPeriod['id'] == null) {
    return {
      ...periodCtx,
      'alreadyRun': false,
      'existingPeriodId': null,
      'payrollComplete': true,
      'missingPayslipCount': 0,
      'rows': freshRows,
    };
  }

  final periodId = '${existingPeriod['id']}';
  final payslipsRaw = await sb
      .from('HRMS_payslips')
      .select(
        'employee_user_id, pay_days, gross_pay, net_pay, pf_employee, pf_employer, esic_employee, esic_employer, professional_tax, incentive, pr_bonus, reimbursement, tds, deductions, ctc, payroll_mode',
      )
      .eq('payroll_period_id', periodId)
      .eq('company_id', companyId);

  final govRaw = await sb.from('HRMS_government_monthly_payroll').select('*').eq('payroll_period_id', periodId).eq('company_id', companyId);
  final govByUser = <String, Map<String, dynamic>>{};
  for (final gAny in (govRaw as List)) {
    final g = Map<String, dynamic>.from(gAny as Map);
    final uid = '${g['employee_user_id'] ?? ''}';
    if (uid.isNotEmpty) govByUser[uid] = g;
  }

  final payslips = (payslipsRaw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (payslips.isEmpty) {
    final rows = freshRows.map((r) => {...r, 'payslipPending': true}).toList();
    return {
      ...periodCtx,
      'alreadyRun': true,
      'existingPeriodId': periodId,
      'payrollComplete': rows.isEmpty,
      'missingPayslipCount': rows.length,
      'rows': rows,
    };
  }

  final slipIds = payslips.map((p) => '${p['employee_user_id']}').where((id) => id.isNotEmpty).toSet();
  final savedByUser = {for (final p in payslips) '${p['employee_user_id']}': p};
  final freshIds = freshRows.map((r) => '${r['employeeUserId']}').where((id) => id.isNotEmpty).toList();
  final nameLookupIds = {...slipIds, ...freshIds}.toList();

  final usersForNames = await sb.from('HRMS_users').select('id, name, email').inFilter('id', nameLookupIds);
  final nameById = <String, Map<String, dynamic>>{};
  for (final uAny in (usersForNames as List)) {
    final u = Map<String, dynamic>.from(uAny as Map);
    nameById['${u['id']}'] = u;
  }

  final merged = <Map<String, dynamic>>[];
  final freshIdSet = freshIds.toSet();
  for (final fr in freshRows) {
    final uid = '${fr['employeeUserId']}';
    if (slipIds.contains(uid)) {
      final p = savedByUser[uid];
      if (p != null) merged.add(_mapSavedPayslipToPreviewRow(p, nameById[uid], govByUser[uid]));
    } else {
      merged.add({...fr, 'payslipPending': true});
    }
  }
  for (final p in payslips) {
    final uid = '${p['employee_user_id']}';
    if (!freshIdSet.contains(uid)) {
      merged.add(_mapSavedPayslipToPreviewRow(p, nameById[uid], govByUser[uid]));
    }
  }

  final missingPayslipCount = merged.where((r) => r['payslipPending'] == true).length;
  return {
    ...periodCtx,
    'alreadyRun': true,
    'existingPeriodId': periodId,
    'payrollComplete': missingPayslipCount == 0,
    'missingPayslipCount': missingPayslipCount,
    'rows': merged,
  };
}

Map<String, dynamic> _emptyPreview(int year, int month, int runDay) {
  final daysInMonth = _daysInMonth(year, month);
  final selectedMonthStart = DateTime.utc(year, month, 1).toIso8601String().substring(0, 10);
  final now = DateTime.now().toUtc();
  final currentMonthStart = DateTime.utc(now.year, now.month, 1).toIso8601String().substring(0, 10);
  final isFutureMonth = selectedMonthStart.compareTo(currentMonthStart) > 0;
  final effectiveRunDay = isFutureMonth ? daysInMonth : math.min(math.max(1, runDay), daysInMonth);
  final periodStart = DateTime.utc(year, month, 1).toIso8601String().substring(0, 10);
  final periodEnd = DateTime.utc(year, month, effectiveRunDay).toIso8601String().substring(0, 10);
  const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return {
    'periodName': '${monthNames[month]}-${year.toString().substring(2)}',
    'periodStart': periodStart,
    'periodEnd': periodEnd,
    'daysInMonth': daysInMonth,
    'workingDaysInFullMonth': math.max(1, daysInMonth),
    'workingDaysThroughRunDay': math.max(1, effectiveRunDay),
    'effectiveRunDay': effectiveRunDay,
    'alreadyRun': false,
    'existingPeriodId': null,
    'payrollComplete': true,
    'missingPayslipCount': 0,
    'rows': <Map<String, dynamic>>[],
  };
}

/// Recalculate a **private** preview row after pay-days change (matches web Run grid).
Map<String, dynamic> recalcPrivateRunRowAfterPayDaysChange({
  required Map<String, dynamic> row,
  required double newPayDaysHalfStep,
  required int payDenom,
  required int companyPt,
  required PrivatePayrollConfig privateCfg,
}) {
  final next = Map<String, dynamic>.from(row);
  final grossMonthly = ((next['grossMonthly'] as num?)?.round() ??
          (((next['grossPay'] as num?) ?? 0) * payDenom / math.max(1.0, ((next['payDays'] as num?) ?? (next['rawPayDays'] as num?) ?? 1).toDouble())))
      .round();
  next['grossMonthly'] = grossMonthly;
  next['payDays'] = newPayDaysHalfStep;
  if (newPayDaysHalfStep > 0) next['payDaysSuppressedMinAttendance'] = false;
  next['grossPay'] = newPayDaysHalfStep == 0 ? 0 : ((grossMonthly * newPayDaysHalfStep) / payDenom).round();
  final profMonth = ((next['profTaxMonthly'] as num?) != null && (next['profTaxMonthly'] as num) >= 0)
      ? (next['profTaxMonthly'] as num).round()
      : companyPt;
  next['profTaxMonthly'] = profMonth;

  final ratioPd = newPayDaysHalfStep / math.max(1, payDenom);
  final calc = computePayrollFromGross(
    grossMonthly,
    next['pfEligible'] != false,
    next['esicEligible'] == true,
    profMonth,
    null,
    privateCfg,
  );
  next['pfEmployee'] = (calc.pfEmp * ratioPd).round();
  next['pfEmployer'] = (calc.pfEmpr * ratioPd).round();
  next['esicEmployee'] = (calc.esicEmp * ratioPd).round();
  next['esicEmployer'] = (calc.esicEmpr * ratioPd).round();
  next['ctcBase'] = calc.ctc.round();
  final profTaxApplied = newPayDaysHalfStep > 0 ? profMonth : 0;
  next['profTax'] = profTaxApplied;
  next['deductions'] = ((next['pfEmployee'] as num?)!.round() + (next['esicEmployee'] as num?)!.round() + profTaxApplied).round();
  final tds = math.max(0, (next['tds'] as num?)?.round() ?? 0);
  next['netPay'] = math.max(0, (next['grossPay'] as num?)!.round() - (next['deductions'] as num?)!.round() - tds);
  final inc = (next['incentive'] as num?)?.round() ?? 0;
  final bonus = (next['prBonus'] as num?)?.round() ?? 0;
  final reimb = (next['reimbursement'] as num?)?.round() ?? 0;
  next['takeHome'] = ((next['netPay'] as num?)!.round() + inc + bonus + reimb);
  final base = (next['ctcBase'] as num?)?.round() ?? (next['ctc'] as num?)?.round() ?? 0;
  next['ctc'] = base + inc + bonus;
  return next;
}
