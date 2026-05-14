import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'leave_booking_calc.dart';

import 'attendance_dashboard_calc.dart';
import 'attendance_policy.dart';
import 'attendance_timezone.dart';
import 'ensure_employee_mirror.dart';
import 'supabase_client.dart';
import 'transaction_notify_service.dart';

class RpcService {
  SupabaseClient get _sb => SupabaseApp.client;

  static int _clampMinutes(num? n) {
    final x = (n ?? 0).round();
    if (x < 0) return 0;
    if (x > 24 * 60) return 24 * 60;
    return x;
  }

  static int _addAccumulatedMinutes({required int accumMin, required String? startedAtIso, required String nowIso}) {
    final base = _clampMinutes(accumMin);
    if (startedAtIso == null || startedAtIso.trim().isEmpty) return base;
    final s = DateTime.tryParse(startedAtIso)?.millisecondsSinceEpoch;
    final n = DateTime.tryParse(nowIso)?.millisecondsSinceEpoch;
    if (s == null || n == null || n <= s) return base;
    final add = ((n - s) / 60000).round();
    return _clampMinutes(base + add);
  }

  static double _haversineMeters(double aLat, double aLng, double bLat, double bLng) {
    double toRad(double d) => d * 3.141592653589793 / 180.0;
    const R = 6371000.0;
    final dLat = toRad(bLat - aLat);
    final dLng = toRad(bLng - aLng);
    final sLat1 = toRad(aLat);
    final sLat2 = toRad(bLat);
    final x = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(sLat1) * math.cos(sLat2) * math.sin(dLng / 2) * math.sin(dLng / 2));
    final c = 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
    return R * c;
  }

  static List<Map<String, String>> _asSegments(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      final out = <Map<String, String>>[];
      for (final e in raw) {
        if (e is Map) {
          final o = '${e['out'] ?? ''}'.trim();
          final i = '${e['in'] ?? ''}'.trim();
          if (o.isNotEmpty && i.isNotEmpty) out.add({'out': o, 'in': i});
        }
      }
      return out;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        return _asSegments(jsonDecode(raw));
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  Future<({bool ok, String companyId, String employeeId, String? error})> _attendanceEmployeeGate(String userId) async {
    final me = await _sb.from('HRMS_users').select('company_id, employment_status').eq('id', userId).maybeSingle();
    final companyId = (me?['company_id'] ?? '').toString();
    if (companyId.isEmpty) {
      return (ok: false, companyId: '', employeeId: '', error: 'User not linked to company');
    }
    if ((me?['employment_status'] ?? '').toString() != 'current') {
      return (
        ok: false,
        companyId: '',
        employeeId: '',
        error: 'Attendance is available only for active (current) employees linked to your company. Ask HR if your status should be current.',
      );
    }

    final mirror = await ensureEmployeeMirrorForUser(_sb, companyId: companyId, userId: userId);
    if (!mirror.ok || mirror.employeeId == null || mirror.employeeId!.isEmpty) {
      return (ok: false, companyId: '', employeeId: '', error: mirror.error ?? 'No employee profile');
    }

    final emp = await _sb
        .from('HRMS_employees')
        .select('id, is_active')
        .eq('company_id', companyId)
        .eq('id', mirror.employeeId!)
        .maybeSingle();
    if (emp?['id'] == null) {
      return (ok: false, companyId: '', employeeId: '', error: 'Employee record not found');
    }
    if (emp?['is_active'] == false) {
      return (ok: false, companyId: '', employeeId: '', error: 'Employee record not active. Ask HR to activate your employee profile.');
    }

    return (ok: true, companyId: companyId, employeeId: mirror.employeeId!, error: null);
  }

  Future<String> _computeAttendanceWorkDate(String companyId, String attendanceEmployeeId) async {
    ensureAttendanceTimeZonesInitialized();
    final ctx = await getAttendanceContextForUser(sb: _sb, companyId: companyId, attendanceEmployeeId: attendanceEmployeeId);
    return computeWorkDateForNow(
      nowUtc: DateTime.now().toUtc(),
      attendanceTz: ctx.timeZone,
      isNightShift: ctx.isNightShift,
      shiftStartTime: ctx.shiftStartTime,
      shiftEndTime: ctx.shiftEndTime,
    );
  }

  Future<void> _bestEffortUpsertAttendanceState({
    required String companyId,
    required String employeeId,
    required String? attendanceLogId,
    required String workDate,
    required String status,
  }) async {
    try {
      final row = <String, dynamic>{
        'company_id': companyId,
        'employee_id': employeeId,
        'work_date': workDate,
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (attendanceLogId != null && attendanceLogId.isNotEmpty) {
        row['attendance_log_id'] = attendanceLogId;
      }
      await _sb.from('HRMS_attendance_state').upsert(row, onConflict: 'company_id,employee_id');
    } catch (_) {}
  }

  Future<void> _bestEffortCloseActivitySessions({
    required String companyId,
    required String employeeId,
    required String attendanceLogId,
    required String endedAtIso,
  }) async {
    try {
      await _sb
          .from('HRMS_activity_sessions')
          .update({'ended_at': endedAtIso, 'last_heartbeat_at': endedAtIso})
          .eq('company_id', companyId)
          .eq('employee_id', employeeId)
          .eq('attendance_log_id', attendanceLogId)
          .isFilter('ended_at', null);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    // Match hrms-web `findUserByEmail` (trim + lowercase) so mobile login behaves the same.
    final normalizedEmail = email.trim().toLowerCase();
    final res = await _sb.rpc('hrms_login', params: {
      'p_email': normalizedEmail,
      'p_password': password,
    });
    // Supabase rpc returns dynamic; our function returns TABLE so it’s a list.
    final rows = (res as List).cast<dynamic>();
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<Map<String, dynamic>> signup(String email, String password, {String? name}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final res = await _sb.rpc('hrms_signup', params: {
      'p_email': normalizedEmail,
      'p_password': password,
      'p_name': name,
    });
    final rows = (res as List).cast<dynamic>();
    return Map<String, dynamic>.from(rows.first as Map);
  }

  /// Change password for password-based accounts (web parity).
  /// Requires a backend RPC `hrms_change_password(p_user_id, p_current_password, p_new_password)`.
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _sb.rpc('hrms_change_password', params: {
      'p_user_id': userId,
      'p_current_password': currentPassword,
      'p_new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>?> me(String userId) async {
    final res = await _sb.rpc('hrms_me', params: {'p_user_id': userId});
    final rows = (res as List).cast<dynamic>();
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<List<Map<String, dynamic>>> holidaysList(String companyId) async {
    final res = await _sb.rpc('hrms_holidays_list', params: {'p_company_id': companyId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Pending + approved leave rows for overlap checks; includes `employeeDivisionId` for holiday scoping.
  Future<Map<String, dynamic>> leaveOverlapContext({
    required String companyId,
    required String actorUserId,
    required String targetUserId,
  }) async {
    final res = await _sb.rpc('hrms_leave_overlap_context', params: {
      'p_company_id': companyId,
      'p_actor_user_id': actorUserId,
      'p_target_user_id': targetUserId,
    });
    return parseOverlapRpc(res);
  }

  Future<String> holidaysCreate({
    required String companyId,
    required String name,
    required String holidayDateYmd,
    bool isOptional = false,
    String? location,
  }) async {
    final res = await _sb.rpc('hrms_holidays_create', params: {
      'p_company_id': companyId,
      'p_name': name,
      'p_holiday_date': holidayDateYmd,
      'p_is_optional': isOptional,
      'p_location': location,
    });
    return res.toString();
  }

  Future<List<Map<String, dynamic>>> employeesList(String companyId, String tab) async {
    final res = await _sb.rpc('hrms_employees_list', params: {
      'p_company_id': companyId,
      'p_tab': tab,
    });
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Super admin only (server enforces). Permanently deletes target user; cascades remove related rows.
  Future<void> employeeDeleteSuper({
    required String actorUserId,
    required String targetUserId,
  }) async {
    await _sb.rpc('hrms_employee_delete_super', params: {
      'p_actor_user_id': actorUserId,
      'p_target_user_id': targetUserId,
    });
  }

  /// Managerial roles: `convert_current`, `convert_past`, `revoke_notice`. Optional `yyyy-MM-dd` for convert flows.
  Future<Map<String, dynamic>> employeeManagementAction({
    required String actorUserId,
    required String targetUserId,
    required String action,
    String? dateYyyyMmDd,
  }) async {
    final params = <String, dynamic>{
      'p_actor_user_id': actorUserId,
      'p_target_user_id': targetUserId,
      'p_action': action,
    };
    if (dateYyyyMmDd != null && dateYyyyMmDd.isNotEmpty) {
      params['p_date_yyyy_mm_dd'] = dateYyyyMmDd;
    }
    final res = await _sb.rpc('hrms_employee_management_action', params: params);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> payslipsList({
    required String companyId,
    required String employeeUserId,
  }) async {
    final res = await _sb.rpc('hrms_payslips_list', params: {
      'p_company_id': companyId,
      'p_employee_user_id': employeeUserId,
    });
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> payslipsMe({
    required String userId,
    String? companyId,
    int? year,
    int? month,
  }) async {
    final params = <String, dynamic>{
      'p_user_id': userId,
      if (companyId != null && companyId.isNotEmpty) 'p_company_id': companyId,
      if (year != null) 'p_year': year,
      if (month != null) 'p_month': month,
    };
    final res = await _sb.rpc('hrms_payslips_me', params: params);
    return Map<String, dynamic>.from(res as Map);
  }

  /// Managerial only (`hr`, `admin`, `super_admin`). Returns `{ masters: [...] }` aligned with web payroll master GET.
  Future<Map<String, dynamic>> payrollMasterList({required String actorUserId}) async {
    final res = await _sb.rpc('hrms_payroll_master_list', params: {'p_actor_user_id': actorUserId});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> payrollMasterSaveBank({
    required String actorUserId,
    required String targetUserId,
    required String bankName,
    required String bankAccountHolderName,
    required String bankAccountNumber,
    required String bankIfsc,
  }) async {
    await _sb.rpc('hrms_payroll_master_save_bank', params: {
      'p_actor_user_id': actorUserId,
      'p_target_user_id': targetUserId,
      'p_bank_name': bankName,
      'p_bank_account_holder_name': bankAccountHolderName,
      'p_bank_account_number': bankAccountNumber,
      'p_bank_ifsc': bankIfsc,
    });
  }

  Future<void> payrollMasterSavePrivate({
    required String actorUserId,
    required String targetUserId,
    required Map<String, dynamic> payload,
  }) async {
    await _sb.rpc('hrms_payroll_master_save_private', params: {
      'p_actor_user_id': actorUserId,
      'p_target_user_id': targetUserId,
      'p_payload': payload,
    });
  }

  /// Managerial only. Returns `{ period, payslips, company, privatePayrollConfig }` for the calendar month.
  Future<Map<String, dynamic>> payrollPeriodSnapshot({
    required String actorUserId,
    required int year,
    required int month,
  }) async {
    final res = await _sb.rpc('hrms_payroll_period_snapshot', params: {
      'p_actor_user_id': actorUserId,
      'p_year': year,
      'p_month': month,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> leaveTypesList(String companyId) async {
    final res = await _sb.rpc('hrms_leave_types_list', params: {'p_company_id': companyId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> leaveBalances({
    required String companyId,
    required String userId,
    int? year,
    /// Local calendar date `yyyy-MM-dd` (aligns leave-year math with the user’s day).
    String? asOfYmd,
  }) async {
    final params = <String, dynamic>{
      'p_company_id': companyId,
      'p_user_id': userId,
    };
    if (year != null) params['p_year'] = year;
    if (asOfYmd != null && asOfYmd.isNotEmpty) params['p_as_of'] = asOfYmd;
    final res = await _sb.rpc('hrms_leave_balances', params: params);
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> leaveRequestsList({
    required String companyId,
    required String userId,
    required String scope, // me|all
  }) async {
    final res = await _sb.rpc('hrms_leave_requests_list', params: {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_scope': scope,
    });
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<String> leaveRequestCreate({
    required String companyId,
    required String userId,
    required String actorUserId,
    required String leaveTypeId,
    required String startDateYmd,
    required String endDateYmd,
    required num totalDays,
    String? reason,
    bool isHalfDay = false,
  }) async {
    final res = await _sb.rpc('hrms_leave_request_create', params: {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_actor_user_id': actorUserId,
      'p_leave_type_id': leaveTypeId,
      'p_start_date': startDateYmd,
      'p_end_date': endDateYmd,
      'p_total_days': totalDays,
      'p_reason': reason,
      'p_is_half_day': isHalfDay,
    });
    final id = res.toString();
    unawaited(TransactionNotifyService.leaveRequestCreated(id));
    return id;
  }

  Future<bool> leaveRequestCancel({
    required String companyId,
    required String userId,
    required String requestId,
  }) async {
    final res = await _sb.rpc('hrms_leave_request_cancel', params: {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_request_id': requestId,
    });
    return res == true;
  }

  Future<bool> leaveRequestDecide({
    required String companyId,
    required String approverUserId,
    required String requestId,
    required String decision, // approved|rejected
    String? rejectionReason,
  }) async {
    final res = await _sb.rpc('hrms_leave_request_decide', params: {
      'p_company_id': companyId,
      'p_approver_user_id': approverUserId,
      'p_request_id': requestId,
      'p_decision': decision,
      'p_rejection_reason': rejectionReason,
    });
    final ok = res == true;
    if (ok) {
      unawaited(TransactionNotifyService.leaveRequestDecided(requestId));
    }
    return ok;
  }

  Future<List<Map<String, dynamic>>> reimbursementsList({
    required String companyId,
    required String userId,
    required String scope, // me|all
  }) async {
    final res = await _sb.rpc('hrms_reimbursements_list', params: {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_scope': scope,
    });
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<String> reimbursementCreate({
    required String companyId,
    required String userId,
    required String actorUserId,
    required String category,
    required num amount,
    required String claimDateYmd,
    required String description,
    required String attachmentUrl,
  }) async {
    final res = await _sb.rpc('hrms_reimbursement_create', params: {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_actor_user_id': actorUserId,
      'p_category': category,
      'p_amount': amount,
      'p_claim_date': claimDateYmd,
      'p_description': description,
      'p_attachment_url': attachmentUrl,
    });
    final id = res.toString();
    unawaited(TransactionNotifyService.reimbursementCreated(id));
    return id;
  }

  Future<bool> reimbursementDecide({
    required String companyId,
    required String approverUserId,
    required String reimbursementId,
    required String status, // approved|rejected|paid
    String? rejectionReason,
  }) async {
    final res = await _sb.rpc('hrms_reimbursement_decide', params: {
      'p_company_id': companyId,
      'p_approver_user_id': approverUserId,
      'p_reimbursement_id': reimbursementId,
      'p_status': status,
      'p_rejection_reason': rejectionReason,
    });
    final ok = res == true;
    if (ok && (status == 'approved' || status == 'rejected')) {
      unawaited(TransactionNotifyService.reimbursementDecided(reimbursementId));
    }
    return ok;
  }

  Future<Map<String, dynamic>> attendanceGet(String userId) async {
    final res = await _sb.rpc('hrms_attendance_get', params: {'p_user_id': userId});
    // returns TABLE -> list of one row
    if (res == null) return {'has_employee': false};
    if (res is List) {
      if (res.isEmpty) return {'has_employee': false};
      return Map<String, dynamic>.from(res.first as Map);
    }
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'has_employee': false};
  }

  /// Web-parity: today's attendance + log (shift timezone / night-shift work_date).
  /// Merges gross/active/idle/agent-session math like web `/api/attendance/me` and includes `agent` heartbeat.
  /// Returns `{hasEmployee, has_employee, workDate, timeZone, log, agent}`.
  Future<Map<String, dynamic>> attendanceTodayWebParity(String userId) async {
    final gate = await _attendanceEmployeeGate(userId);
    if (!gate.ok) {
      return {
        'hasEmployee': false,
        'has_employee': false,
        'workDate': null,
        'timeZone': null,
        'log': null,
        'agent': null,
      };
    }
    final wd = await _computeAttendanceWorkDate(gate.companyId, gate.employeeId);
    final log = await _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, '
          'lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, '
          'lunch_break_segments, tea_break_segments, status, in_office, office_note, notes, check_in_in_office, '
          'agent_active_minutes, agent_idle_minutes, agent_disconnected_minutes, activity_purged_at',
        )
        .eq('company_id', gate.companyId)
        .eq('employee_id', gate.employeeId)
        .eq('work_date', wd)
        .maybeSingle();

    Map<String, dynamic>? mergedLog;
    if (log != null) {
      final logMap = Map<String, dynamic>.from(log);
      final logId = logMap['id']?.toString();
      var sessions = <Map<String, dynamic>>[];
        if (logId != null && logId.isNotEmpty) {
        final sess = await _sb
            .from('HRMS_activity_sessions')
            .select(
              'attendance_log_id, started_at, ended_at, last_heartbeat_at, active_seconds, idle_seconds, disconnected_seconds',
            )
            .eq('company_id', gate.companyId)
            .eq('employee_id', gate.employeeId)
            .eq('attendance_log_id', logId);
        final list = sess as List<dynamic>?;
        if (list != null) {
          sessions = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      mergedLog = mergeWebDashboardMetrics(
        log: logMap,
        sessions: sessions,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    final hb = await _sb
        .from('HRMS_agent_heartbeat')
        .select('status, last_seen_at, app_version, device_name')
        .eq('company_id', gate.companyId)
        .eq('employee_id', gate.employeeId)
        .maybeSingle();

    Map<String, dynamic>? agentPayload;
    if (hb != null) {
      final last = hb['last_seen_at']?.toString();
      final lastMs = last != null ? DateTime.tryParse(last)?.millisecondsSinceEpoch : null;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final connected = lastMs != null && nowMs - lastMs <= 60000;
      agentPayload = {
        'connected': connected,
        'lastSeenAt': last,
        'appVersion': hb['app_version'],
        'deviceName': hb['device_name'],
      };
    } else {
      agentPayload = {
        'connected': false,
        'lastSeenAt': null,
        'appVersion': null,
        'deviceName': null,
      };
    }

    final ctx = await getAttendanceContextForUser(sb: _sb, companyId: gate.companyId, attendanceEmployeeId: gate.employeeId);
    return {
      'hasEmployee': true,
      'has_employee': true,
      'workDate': wd,
      'timeZone': ctx.timeZone,
      'log': mergedLog,
      'agent': agentPayload,
    };
  }

  /// Web-parity punch (location required), geofence, work_date from shift TZ, mirror + gate.
  Future<Map<String, dynamic>> attendancePunchWebParity({
    required String userId,
    required String action,
    required double lat,
    required double lng,
    int? accuracyM,
    bool allowRepunchOut = false,
  }) async {
    final gate = await _attendanceEmployeeGate(userId);
    if (!gate.ok) {
      throw PostgrestException(message: gate.error ?? 'Attendance not allowed');
    }
    final companyId = gate.companyId;
    final empId = gate.employeeId;

    final company = await _sb.from('HRMS_companies').select('latitude, longitude, office_radius_m').eq('id', companyId).maybeSingle();
    final officeLat = (company?['latitude'] as num?)?.toDouble();
    final officeLng = (company?['longitude'] as num?)?.toDouble();
    final officeRadiusM = ((company?['office_radius_m'] as num?)?.toDouble() ?? 150).clamp(10, 100000);
    if (officeLat == null || officeLng == null) {
      throw PostgrestException(message: 'Company office location is not configured. Ask Super Admin to set it in Settings → Company.');
    }

    final wd = await _computeAttendanceWorkDate(companyId, empId);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final existing = await _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, check_in_at, check_out_at, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, '
          'lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, notes, check_in_in_office, in_office, office_note',
        )
        .eq('company_id', companyId)
        .eq('employee_id', empId)
        .eq('work_date', wd)
        .maybeSingle();

    final distanceM = _haversineMeters(lat, lng, officeLat, officeLng);
    final inOffice = distanceM <= officeRadiusM;

    if (action == 'in') {
      if (existing?['check_in_at'] != null && existing?['check_out_at'] != null) {
        throw PostgrestException(message: "Today's attendance is already complete.");
      }
      if (existing?['check_in_at'] != null && existing?['check_out_at'] == null) {
        throw PostgrestException(message: 'You are already punched in. Punch out to end your shift.');
      }

      final inserted = await _sb
          .from('HRMS_attendance_logs')
          .insert([
            {
              'company_id': companyId,
              'employee_id': empId,
              'work_date': wd,
              'check_in_at': nowIso,
              'check_out_at': null,
              'lunch_break_minutes': 0,
              'tea_break_minutes': 0,
              'lunch_break_started_at': null,
              'tea_break_started_at': null,
              'lunch_check_out_at': null,
              'lunch_check_in_at': null,
              'tea_check_out_at': null,
              'tea_check_in_at': null,
              'lunch_break_segments': <dynamic>[],
              'tea_break_segments': <dynamic>[],
              'total_hours': null,
              'status': 'present',
              'check_in_lat': lat,
              'check_in_lng': lng,
              'check_in_accuracy_m': accuracyM,
              'in_office': inOffice,
              'check_in_in_office': inOffice,
              'office_note': inOffice ? null : 'Punched in from outside office.',
              'notes': 'Punch in: ${inOffice ? "Inside office." : "Outside office."}',
              'updated_at': nowIso,
            }
          ])
          .select(
            'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, '
            'lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, lunch_break_segments, tea_break_segments, status, in_office, office_note, notes',
          )
          .single();
      final row = Map<String, dynamic>.from(inserted as Map);
      await _bestEffortUpsertAttendanceState(
        companyId: companyId,
        employeeId: empId,
        attendanceLogId: row['id']?.toString(),
        workDate: wd,
        status: 'ACTIVE',
      );
      return row;
    }

    // out
    if (existing == null || existing['check_in_at'] == null) {
      throw PostgrestException(message: 'Punch in first before punching out.');
    }
    if (existing['check_out_at'] != null && !allowRepunchOut) {
      await _bestEffortUpsertAttendanceState(
        companyId: companyId,
        employeeId: empId,
        attendanceLogId: existing['id']?.toString(),
        workDate: wd,
        status: 'INACTIVE',
      );
      await _bestEffortCloseActivitySessions(
        companyId: companyId,
        employeeId: empId,
        attendanceLogId: existing['id'].toString(),
        endedAtIso: nowIso,
      );
      throw PostgrestException(message: 'You have already punched out for today. Tracking has been stopped.');
    }
    if (existing['lunch_break_started_at'] != null) {
      throw PostgrestException(message: 'End lunch (check in after lunch) before final check out.');
    }
    if (existing['tea_break_started_at'] != null) {
      throw PostgrestException(message: 'End tea break before final check out.');
    }

    final inMs = DateTime.tryParse(existing['check_in_at'].toString())?.millisecondsSinceEpoch;
    final outMs = DateTime.tryParse(nowIso)?.millisecondsSinceEpoch;
    if (inMs == null || outMs == null || outMs <= inMs) throw PostgrestException(message: 'Invalid punch out time.');

    final lunchMinBase = _clampMinutes(existing['lunch_break_minutes'] as num?);
    final teaMinBase = _clampMinutes(existing['tea_break_minutes'] as num?);
    final finalLunchMin = _addAccumulatedMinutes(accumMin: lunchMinBase, startedAtIso: existing['lunch_break_started_at']?.toString(), nowIso: nowIso);
    final finalTeaMin = _addAccumulatedMinutes(accumMin: teaMinBase, startedAtIso: existing['tea_break_started_at']?.toString(), nowIso: nowIso);

    final grossMinutes = ((outMs - inMs) / 60000).round();
    final totalHours2dp = ((grossMinutes / 60) * 100).round() / 100.0;

    const lunchBreakMinutesBody = 0;
    const teaBreakMinutesBody = 0;
    final actualLunchMinutes = math.max(finalLunchMin, lunchBreakMinutesBody);
    final actualTeaMinutes = math.max(finalTeaMin, teaBreakMinutesBody);
    final effectiveBreak = effectiveCombinedBreakBreakdown(
      lunchMinutes: actualLunchMinutes,
      teaMinutes: actualTeaMinutes,
      grossWorkMinutes: grossMinutes,
    );

    final teaStartedPre = existing['tea_break_started_at']?.toString().trim();
    final teaCheckInAt = (teaStartedPre != null && teaStartedPre.isNotEmpty) ? nowIso : existing['tea_check_in_at'];

    final checkInSide = existing['check_in_in_office'] == true || existing['in_office'] == true;
    final inOfficeStored = checkInSide && inOffice;

    final updated = await _sb
        .from('HRMS_attendance_logs')
        .update({
          'check_out_at': nowIso,
          'lunch_break_minutes': effectiveBreak.lunchBreakMinutes,
          'tea_break_minutes': effectiveBreak.teaBreakMinutes,
          'lunch_break_started_at': null,
          'tea_break_started_at': null,
          'tea_check_in_at': teaCheckInAt,
          'total_hours': totalHours2dp,
          'status': 'present',
          'check_out_lat': lat,
          'check_out_lng': lng,
          'check_out_accuracy_m': accuracyM,
          'check_out_in_office': inOffice,
          'in_office': inOfficeStored,
          'office_note': inOffice
              ? existing['office_note']
              : '${(existing['office_note'] ?? '').toString()} Punched out from outside office.'.trim(),
          'notes': '${(existing['notes'] ?? '').toString()} Punch out: ${inOffice ? "Inside office." : "Outside office."}'.trim(),
          'updated_at': nowIso,
        })
        .eq('id', existing['id'])
        .select(
          'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, '
          'lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, lunch_break_segments, tea_break_segments, status, in_office, office_note, notes',
        )
        .single();

    final outRow = Map<String, dynamic>.from(updated as Map);
    await _bestEffortUpsertAttendanceState(
      companyId: companyId,
      employeeId: empId,
      attendanceLogId: outRow['id']?.toString(),
      workDate: wd,
      status: 'INACTIVE',
    );
    await _bestEffortCloseActivitySessions(
      companyId: companyId,
      employeeId: empId,
      attendanceLogId: existing['id'].toString(),
      endedAtIso: nowIso,
    );
    return outRow;
  }

  /// Web-parity break toggle (lunch/tea) including `*_break_segments` + attendance_state.
  Future<Map<String, dynamic>> attendanceBreakToggleWebParity({
    required String userId,
    required String kind, // lunch|tea
  }) async {
    final gate = await _attendanceEmployeeGate(userId);
    if (!gate.ok) {
      throw PostgrestException(message: gate.error ?? 'Attendance not allowed');
    }
    final companyId = gate.companyId;
    final empId = gate.employeeId;

    final wd = await _computeAttendanceWorkDate(companyId, empId);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final existing = await _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, check_in_at, check_out_at, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, '
          'lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, lunch_break_segments, tea_break_segments',
        )
        .eq('company_id', companyId)
        .eq('employee_id', empId)
        .eq('work_date', wd)
        .maybeSingle();

    if (existing == null || existing['check_in_at'] == null) {
      throw PostgrestException(message: 'Punch in first before starting breaks.');
    }
    if (existing['check_out_at'] != null) throw PostgrestException(message: 'Attendance already completed for today.');

    final isLunch = kind == 'lunch';
    final lunchStarted = existing['lunch_break_started_at']?.toString();
    final teaStarted = existing['tea_break_started_at']?.toString();
    final lunchMinBase = _clampMinutes(existing['lunch_break_minutes'] as num?);
    final teaMinBase = _clampMinutes(existing['tea_break_minutes'] as num?);

    var lunchSeg = List<Map<String, String>>.from(_asSegments(existing['lunch_break_segments']));
    var teaSeg = List<Map<String, String>>.from(_asSegments(existing['tea_break_segments']));

    final isRunning = isLunch ? (lunchStarted != null && lunchStarted.trim().isNotEmpty) : (teaStarted != null && teaStarted.trim().isNotEmpty);

    String? nextLunchStarted = lunchStarted;
    String? nextTeaStarted = teaStarted;
    var nextLunchMin = lunchMinBase;
    var nextTeaMin = teaMinBase;

    String? nextLunchOutAt = existing['lunch_check_out_at']?.toString();
    String? nextLunchInAt = existing['lunch_check_in_at']?.toString();
    String? nextTeaOutAt = existing['tea_check_out_at']?.toString();
    String? nextTeaInAt = existing['tea_check_in_at']?.toString();

    if (isRunning) {
      if (isLunch) {
        nextLunchMin = _addAccumulatedMinutes(accumMin: lunchMinBase, startedAtIso: lunchStarted, nowIso: nowIso);
        nextLunchStarted = null;
        nextLunchInAt = nowIso;
        final ls = lunchStarted?.trim();
        if (ls != null && ls.isNotEmpty) {
          lunchSeg = [...lunchSeg, {'out': ls, 'in': nowIso}];
        }
      } else {
        nextTeaMin = _addAccumulatedMinutes(accumMin: teaMinBase, startedAtIso: teaStarted, nowIso: nowIso);
        nextTeaStarted = null;
        nextTeaInAt = nowIso;
        final ts = teaStarted?.trim();
        if (ts != null && ts.isNotEmpty) {
          teaSeg = [...teaSeg, {'out': ts, 'in': nowIso}];
        }
      }
    } else {
      if (isLunch && teaStarted != null && teaStarted.trim().isNotEmpty) {
        nextTeaMin = _addAccumulatedMinutes(accumMin: teaMinBase, startedAtIso: teaStarted, nowIso: nowIso);
        nextTeaStarted = null;
        nextTeaInAt = nowIso;
        final ts = teaStarted.trim();
        teaSeg = [...teaSeg, {'out': ts, 'in': nowIso}];
      }
      if (!isLunch && lunchStarted != null && lunchStarted.trim().isNotEmpty) {
        nextLunchMin = _addAccumulatedMinutes(accumMin: lunchMinBase, startedAtIso: lunchStarted, nowIso: nowIso);
        nextLunchStarted = null;
        nextLunchInAt = nowIso;
        final ls = lunchStarted.trim();
        lunchSeg = [...lunchSeg, {'out': ls, 'in': nowIso}];
      }
      if (isLunch) {
        nextLunchStarted = nowIso;
        nextLunchOutAt = (nextLunchOutAt == null || nextLunchOutAt.trim().isEmpty) ? nowIso : nextLunchOutAt;
      } else {
        nextTeaStarted = nowIso;
        nextTeaOutAt = (nextTeaOutAt == null || nextTeaOutAt.trim().isEmpty) ? nowIso : nextTeaOutAt;
      }
    }

    final updated = await _sb
        .from('HRMS_attendance_logs')
        .update({
          'lunch_break_minutes': nextLunchMin,
          'tea_break_minutes': nextTeaMin,
          'lunch_break_started_at': nextLunchStarted,
          'tea_break_started_at': nextTeaStarted,
          'lunch_check_out_at': nextLunchOutAt,
          'lunch_check_in_at': nextLunchInAt,
          'tea_check_out_at': nextTeaOutAt,
          'tea_check_in_at': nextTeaInAt,
          'lunch_break_segments': lunchSeg,
          'tea_break_segments': teaSeg,
          'updated_at': nowIso,
        })
        .eq('id', existing['id'])
        .select(
          'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, '
          'lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, lunch_break_segments, tea_break_segments, status, in_office, office_note, notes, check_out_at',
        )
        .single();

    final urow = Map<String, dynamic>.from(updated as Map);
    String st;
    if (urow['check_out_at'] != null) {
      st = 'INACTIVE';
    } else if (urow['lunch_break_started_at'] != null) {
      st = 'LUNCH';
    } else if (urow['tea_break_started_at'] != null) {
      st = 'BREAK';
    } else {
      st = 'ACTIVE';
    }
    await _bestEffortUpsertAttendanceState(
      companyId: companyId,
      employeeId: empId,
      attendanceLogId: urow['id']?.toString(),
      workDate: wd,
      status: st,
    );

    return urow;
  }

  Future<Map<String, dynamic>> attendancePunch({
    required String userId,
    required String action, // 'in'|'out'
    bool allowRepunchOut = false,
    bool allowRepunchIn = false,
  }) async {
    final res = await _sb.rpc('hrms_attendance_punch', params: {
      'p_user_id': userId,
      'p_action': action,
      'p_allow_repunch_out': allowRepunchOut,
      'p_allow_repunch_in': allowRepunchIn,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> attendanceBreakToggle({
    required String userId,
    required String kind, // 'lunch'|'tea'
  }) async {
    final res = await _sb.rpc('hrms_attendance_break_toggle', params: {
      'p_user_id': userId,
      'p_kind': kind,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Attendance history for current user (employee view). Returns `{hasEmployee, rows}`.
  Future<Map<String, dynamic>> attendanceMeRange({
    required String companyId,
    required String userId,
    required String startDateYmd,
    required String endDateYmd,
  }) async {
    final emp = await _sb
        .from('HRMS_employees')
        .select('id')
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .maybeSingle();
    final empId = (emp?['id'] ?? '').toString();
    if (empId.isEmpty) return {'hasEmployee': false, 'rows': <Map<String, dynamic>>[]};

    final res = await _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, employee_id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, status, in_office, notes',
        )
        .eq('company_id', companyId)
        .eq('employee_id', empId)
        .gte('work_date', startDateYmd)
        .lte('work_date', endDateYmd)
        .order('work_date', ascending: false);
    final rows = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return {'hasEmployee': true, 'rows': rows};
  }

  /// Company attendance history (admin/hr/super admin view). Optional `employeeUserId` filters to one employee.
  Future<List<Map<String, dynamic>>> attendanceCompanyRange({
    required String companyId,
    required String startDateYmd,
    required String endDateYmd,
    String? employeeUserId,
  }) async {
    String? filterEmpId;
    if (employeeUserId != null && employeeUserId.trim().isNotEmpty) {
      final emp = await _sb
          .from('HRMS_employees')
          .select('id')
          .eq('company_id', companyId)
          .eq('user_id', employeeUserId.trim())
          .maybeSingle();
      filterEmpId = (emp?['id'] ?? '').toString();
      if (filterEmpId.isEmpty) return <Map<String, dynamic>>[];
    }

    var q = _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, employee_id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, status, in_office, notes',
        )
        .eq('company_id', companyId)
        .gte('work_date', startDateYmd)
        .lte('work_date', endDateYmd);
    if (filterEmpId != null && filterEmpId.isNotEmpty) {
      q = q.eq('employee_id', filterEmpId);
    }
    final logs = await q;
    final logRows = (logs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (logRows.isEmpty) return <Map<String, dynamic>>[];

    final empIds = logRows.map((e) => (e['employee_id'] ?? '').toString()).where((s) => s.isNotEmpty).toSet().toList();
    final emps = await _sb
        .from('HRMS_employees')
        .select('id, user_id, employee_code')
        .eq('company_id', companyId)
        .inFilter('id', empIds);
    final empRows = (emps as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final userIds = empRows.map((e) => (e['user_id'] ?? '').toString()).where((s) => s.isNotEmpty).toSet().toList();
    final users = userIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _sb.from('HRMS_users').select('id, name, email, role').inFilter('id', userIds) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    final empById = {for (final e in empRows) (e['id'] ?? '').toString(): e};
    final userById = {for (final u in users) (u['id'] ?? '').toString(): u};

    final rows = <Map<String, dynamic>>[];
    for (final log in logRows) {
      final emp = empById[(log['employee_id'] ?? '').toString()];
      final userId = (emp?['user_id'] ?? '').toString();
      final u = userId.isEmpty ? null : userById[userId];
      if ((u?['role'] ?? '').toString() == 'super_admin') continue;
      rows.add({
        ...log,
        'employee_code': emp?['employee_code'],
        'employee_user_id': userId,
        'employee_name': u?['name'],
        'employee_email': u?['email'],
      });
    }
    rows.sort((a, b) {
      final da = (a['work_date'] ?? '').toString();
      final db = (b['work_date'] ?? '').toString();
      if (da != db) return db.compareTo(da);
      final na = ((a['employee_name'] ?? a['employee_email']) ?? '').toString();
      final nb = ((b['employee_name'] ?? b['employee_email']) ?? '').toString();
      return na.compareTo(nb);
    });
    return rows;
  }

  /// Full `HRMS_users` row as JSON (no `password_hash`). Null if user missing.
  Future<Map<String, dynamic>?> profileFullGet(String userId) async {
    final res = await _sb.rpc('hrms_profile_full_get', params: {'p_user_id': userId});
    if (res == null) return null;
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  Future<Map<String, dynamic>> profileFullSave({
    required String userId,
    required String actorRole,
    required Map<String, dynamic> patch,
  }) async {
    final res = await _sb.rpc('hrms_profile_full_save', params: {
      'p_user_id': userId,
      'p_actor_role': actorRole,
      'p_patch': patch,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>?> companyGetForUser(String userId) async {
    final res = await _sb.rpc('hrms_company_get_for_user', params: {'p_user_id': userId});
    if (res == null) return null;
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  Future<Map<String, dynamic>> companySave({
    required String userId,
    required Map<String, dynamic> patch,
  }) async {
    final res = await _sb.rpc('hrms_company_save', params: {
      'p_user_id': userId,
      'p_patch': patch,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> settingsShiftsAll(String companyId) async {
    final res = await _sb.rpc('hrms_settings_shifts_all', params: {'p_company_id': companyId});
    return _jsonbList(res);
  }

  Future<List<Map<String, dynamic>>> settingsDivisionsAll(String companyId) async {
    final res = await _sb.rpc('hrms_settings_divisions_all', params: {'p_company_id': companyId});
    return _jsonbList(res);
  }

  Future<List<Map<String, dynamic>>> settingsDepartmentsAll(String companyId) async {
    final res = await _sb.rpc('hrms_settings_departments_all', params: {'p_company_id': companyId});
    return _jsonbList(res);
  }

  Future<List<Map<String, dynamic>>> settingsDesignationsAll(String companyId) async {
    final res = await _sb.rpc('hrms_settings_designations_all', params: {'p_company_id': companyId});
    return _jsonbList(res);
  }

  Future<List<Map<String, dynamic>>> settingsRolesAll(String companyId) async {
    final res = await _sb.rpc('hrms_settings_roles_all', params: {'p_company_id': companyId});
    return _jsonbList(res);
  }

  Future<List<Map<String, dynamic>>> settingsDesignations(String companyId) async {
    final res = await _sb.rpc('hrms_settings_designations', params: {'p_company_id': companyId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> settingsDepartments(String companyId) async {
    final res = await _sb.rpc('hrms_settings_departments', params: {'p_company_id': companyId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> settingsDivisions(String companyId) async {
    final res = await _sb.rpc('hrms_settings_divisions', params: {'p_company_id': companyId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> settingsShifts(String companyId) async {
    final res = await _sb.rpc('hrms_settings_shifts', params: {'p_company_id': companyId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Onboarding / uploaded files linked to `HRMS_employee_document_submissions`.
  Future<List<Map<String, dynamic>>> myDocumentsList(String userId) async {
    final res = await _sb.rpc('hrms_my_documents_list', params: {'p_user_id': userId});
    return _jsonbList(res);
  }

  static List<Map<String, dynamic>> _jsonbList(dynamic res) {
    if (res == null) return [];
    if (res is! List) return [];
    return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> companyDocumentsList(String actorUserId) async {
    final res = await _sb.rpc('hrms_company_documents_list', params: {
      'p_actor_user_id': actorUserId,
    });
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> companyDocumentCreate({
    required String actorUserId,
    required String name,
    required String kind,
    required bool isMandatory,
    String? contentText,
  }) async {
    final res = await _sb.rpc('hrms_company_document_create', params: {
      'p_actor_user_id': actorUserId,
      'p_name': name,
      'p_kind': kind,
      'p_is_mandatory': isMandatory,
      'p_content_text': contentText,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// New invite row + token (revokes prior pending for same email). Email is sent via [InviteEdgeService] using returned token.
  Future<Map<String, dynamic>> employeeInviteIssue({
    required String actorUserId,
    required String email,
    required String targetUserId,
    List<String>? requestedDocumentIds,
  }) async {
    final params = <String, dynamic>{
      'p_actor_user_id': actorUserId,
      'p_email': email.trim().toLowerCase(),
      'p_target_user_id': targetUserId,
    };
    if (requestedDocumentIds != null && requestedDocumentIds.isNotEmpty) {
      params['p_requested_document_ids'] = requestedDocumentIds;
    }
    final res = await _sb.rpc('hrms_employee_invite_issue', params: params);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> employeeOnboardingForManager({
    required String actorUserId,
    required String targetUserId,
  }) async {
    final res = await _sb.rpc('hrms_employee_onboarding_for_manager', params: {
      'p_actor_user_id': actorUserId,
      'p_target_user_id': targetUserId,
    });
    return Map<String, dynamic>.from(res as Map);
  }
}

