// Ported from hrms-web `leaveBalancesCompute.ts` (minimal surface for payroll PL top-up).

import 'dart:math' as math;

import 'leave_policy_payroll.dart';

class LeavePolicyWithTypeRow {
  const LeavePolicyWithTypeRow({
    required this.leaveTypeId,
    required this.accrualMethod,
    required this.monthlyAccrualRate,
    required this.annualQuota,
    required this.prorateOnJoin,
    required this.resetMonth,
    required this.resetDay,
    required this.allowCarryover,
    required this.carryoverLimit,
    this.leaveTypeName,
    this.payslipSlot,
    this.isPaid,
  });

  final String leaveTypeId;
  final String accrualMethod;
  final double? monthlyAccrualRate;
  final double? annualQuota;
  final bool prorateOnJoin;
  final int? resetMonth;
  final int? resetDay;
  final bool? allowCarryover;
  final double? carryoverLimit;
  final String? leaveTypeName;
  final String? payslipSlot;
  final bool? isPaid;
}

class LeaveBalanceComputedRow {
  const LeaveBalanceComputedRow({
    required this.leaveTypeId,
    required this.leaveTypeName,
    required this.payslipSlot,
    required this.isPaid,
    required this.entitled,
    required this.used,
    required this.remaining,
  });

  final String leaveTypeId;
  final String leaveTypeName;
  final String? payslipSlot;
  final bool isPaid;
  final double? entitled;
  final double used;
  final double? remaining;
}

List<LeaveBalanceComputedRow> computeLeaveBalanceRows(
  List<LeavePolicyWithTypeRow> policies,
  List<ApprovedLeave> approvedLeaves,
  String? joinDateStr,
  String asOfYmd,
) {
  final asOf = DateTime.parse('${asOfYmd.substring(0, 10)}T00:00:00Z');
  final joinDate = joinDateStr != null && joinDateStr.length >= 10 ? DateTime.parse('${joinDateStr.substring(0, 10)}T00:00:00Z') : null;

  return policies.map((p) {
    final policy = LeavePolicy(
      leaveTypeId: p.leaveTypeId,
      accrualMethod: p.accrualMethod,
      monthlyAccrualRate: p.monthlyAccrualRate,
      annualQuota: p.annualQuota,
      prorateOnJoin: p.prorateOnJoin,
      resetMonth: p.resetMonth ?? 1,
      resetDay: p.resetDay ?? 1,
      allowCarryover: p.allowCarryover ?? false,
      carryoverLimit: p.carryoverLimit,
    );

    final yearStart = leaveYearStart(asOf, policy.resetMonth, policy.resetDay);
    final yearEndExclusive = DateTime.utc(yearStart.year + 1, yearStart.month, yearStart.day);

    final entitled = computeEntitled(policy, joinDate, asOf);
    final used = computeUsedDaysForYear(approvedLeaves, p.leaveTypeId, yearStart, yearEndExclusive);
    final remaining = entitled == null ? null : math.max(0.0, entitled - used);

    return LeaveBalanceComputedRow(
      leaveTypeId: p.leaveTypeId,
      leaveTypeName: p.leaveTypeName ?? '',
      payslipSlot: p.payslipSlot,
      isPaid: p.isPaid ?? false,
      entitled: entitled,
      used: used,
      remaining: remaining,
    );
  }).toList();
}
