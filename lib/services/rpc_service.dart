import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

class RpcService {
  SupabaseClient get _sb => SupabaseApp.client;

  static String _workDateIST() {
    final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

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
    final x = (Math.sin(dLat / 2) * Math.sin(dLat / 2)) +
        (Math.cos(sLat1) * Math.cos(sLat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2));
    final c = 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
    return R * c;
  }

  // Dart's math isn't imported by default; keep helpers local.
  // ignore: non_constant_identifier_names
  static _Math Math = _Math();

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _sb.rpc('hrms_login', params: {
      'p_email': email,
      'p_password': password,
    });
    // Supabase rpc returns dynamic; our function returns TABLE so it’s a list.
    final rows = (res as List).cast<dynamic>();
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<Map<String, dynamic>> signup(String email, String password, {String? name}) async {
    final res = await _sb.rpc('hrms_signup', params: {
      'p_email': email,
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
    final res = await _sb.rpc('hrms_payslips_me', params: {
      'p_user_id': userId,
      'p_company_id': companyId,
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
    required String leaveTypeId,
    required String startDateYmd,
    required String endDateYmd,
    required num totalDays,
    String? reason,
  }) async {
    final res = await _sb.rpc('hrms_leave_request_create', params: {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_leave_type_id': leaveTypeId,
      'p_start_date': startDateYmd,
      'p_end_date': endDateYmd,
      'p_total_days': totalDays,
      'p_reason': reason,
    });
    return res.toString();
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
    return res == true;
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
    required String category,
    required num amount,
    required String claimDateYmd,
    String? description,
    String? attachmentUrl,
  }) async {
    final res = await _sb.rpc('hrms_reimbursement_create', params: {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_category': category,
      'p_amount': amount,
      'p_claim_date': claimDateYmd,
      'p_description': description,
      'p_attachment_url': attachmentUrl,
    });
    return res.toString();
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
    return res == true;
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

  /// Web-parity: today's attendance + log (IST date) with the same DB sources as web.
  /// Returns `{hasEmployee: bool, workDate: yyyy-mm-dd, log: Map?}`.
  Future<Map<String, dynamic>> attendanceTodayWebParity(String userId) async {
    final me = await _sb.from('HRMS_users').select('company_id').eq('id', userId).maybeSingle();
    final companyId = (me?['company_id'] ?? '').toString();
    final wd = _workDateIST();
    if (companyId.isEmpty) return {'hasEmployee': false, 'workDate': wd, 'log': null};

    final emp = await _sb.from('HRMS_employees').select('id').eq('company_id', companyId).eq('user_id', userId).maybeSingle();
    final empId = (emp?['id'] ?? '').toString();
    if (empId.isEmpty) return {'hasEmployee': false, 'workDate': wd, 'log': null};

    final log = await _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, status, in_office, office_note, notes',
        )
        .eq('company_id', companyId)
        .eq('employee_id', empId)
        .eq('work_date', wd)
        .maybeSingle();

    return {'hasEmployee': true, 'workDate': wd, 'log': log == null ? null : Map<String, dynamic>.from(log)};
  }

  static const int _mandatoryLunchMinutesWhenNoLunchPunch = 60;
  static const int _minGrossMinutesForMandatoryLunch = 4 * 60;

  static int _effectiveLunchBreakMinutes({
    required int recordedLunchMinutes,
    required String? lunchCheckOutAt,
    required String? lunchCheckInAt,
    required int grossWorkMinutes,
  }) {
    var m = _clampMinutes(recordedLunchMinutes);
    final noLunchPunch = (lunchCheckOutAt == null || lunchCheckOutAt.trim().isEmpty) && (lunchCheckInAt == null || lunchCheckInAt.trim().isEmpty);
    if (noLunchPunch && grossWorkMinutes >= _minGrossMinutesForMandatoryLunch && m < _mandatoryLunchMinutesWhenNoLunchPunch) {
      m = _mandatoryLunchMinutesWhenNoLunchPunch;
    }
    if (m > grossWorkMinutes) return grossWorkMinutes < 0 ? 0 : grossWorkMinutes;
    return m;
  }

  /// Web-parity punch (location required) and geofence marking.
  /// `action`: 'in' or 'out'. Returns updated attendance log row.
  Future<Map<String, dynamic>> attendancePunchWebParity({
    required String userId,
    required String action,
    required double lat,
    required double lng,
    int? accuracyM,
    bool allowRepunchOut = false,
  }) async {
    final me = await _sb.from('HRMS_users').select('company_id').eq('id', userId).maybeSingle();
    final companyId = (me?['company_id'] ?? '').toString();
    if (companyId.isEmpty) throw PostgrestException(message: 'User not linked to company');

    final company = await _sb.from('HRMS_companies').select('latitude, longitude, office_radius_m').eq('id', companyId).maybeSingle();
    final officeLat = (company?['latitude'] as num?)?.toDouble();
    final officeLng = (company?['longitude'] as num?)?.toDouble();
    final officeRadiusM = ((company?['office_radius_m'] as num?)?.toDouble() ?? 150).clamp(10, 100000);
    if (officeLat == null || officeLng == null) {
      throw PostgrestException(message: 'Company office location is not configured. Ask Super Admin to set it in Settings → Company.');
    }

    final emp = await _sb.from('HRMS_employees').select('id').eq('company_id', companyId).eq('user_id', userId).maybeSingle();
    final empId = (emp?['id'] ?? '').toString();
    if (empId.isEmpty) throw PostgrestException(message: 'No employee profile found. Ask HR to complete your employee record before marking attendance.');

    final wd = _workDateIST();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final existing = await _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, check_in_at, check_out_at, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, notes, check_in_in_office, in_office, office_note',
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
            'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, status, in_office, office_note, notes',
          )
          .single();
      return Map<String, dynamic>.from(inserted as Map);
    }

    // out
    if (existing == null || existing['check_in_at'] == null) {
      throw PostgrestException(message: 'Punch in first before punching out.');
    }
    if (existing['check_out_at'] != null && !allowRepunchOut) {
      throw PostgrestException(message: 'You have already punched out for today. Ask HR/Admin if you need corrections.');
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
    final totalHours = (grossMinutes / 60);
    final totalHours2dp = (totalHours * 100).round() / 100.0;

    final lunchMinutesStored = _effectiveLunchBreakMinutes(
      recordedLunchMinutes: finalLunchMin,
      lunchCheckOutAt: existing['lunch_check_out_at']?.toString(),
      lunchCheckInAt: existing['lunch_check_in_at']?.toString(),
      grossWorkMinutes: grossMinutes,
    );

    final updated = await _sb
        .from('HRMS_attendance_logs')
        .update({
          'check_out_at': nowIso,
          'lunch_break_minutes': lunchMinutesStored,
          'tea_break_minutes': finalTeaMin,
          'lunch_break_started_at': null,
          'tea_break_started_at': null,
          'total_hours': totalHours2dp,
          'status': 'present',
          'check_out_lat': lat,
          'check_out_lng': lng,
          'check_out_accuracy_m': accuracyM,
          'check_out_in_office': inOffice,
          'in_office': (existing['check_in_in_office'] == true || existing['in_office'] == true) && inOffice,
          'office_note': inOffice ? existing['office_note'] : '${(existing['office_note'] ?? '').toString()} Punched out from outside office.'.trim(),
          'notes': '${(existing['notes'] ?? '').toString()} Punch out: ${inOffice ? "Inside office." : "Outside office."}'.trim(),
          'updated_at': nowIso,
        })
        .eq('id', existing['id'])
        .select(
          'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, status, in_office, office_note, notes',
        )
        .single();

    return Map<String, dynamic>.from(updated as Map);
  }

  /// Web-parity break toggle (lunch/tea). Returns updated log row.
  Future<Map<String, dynamic>> attendanceBreakToggleWebParity({
    required String userId,
    required String kind, // lunch|tea
  }) async {
    final me = await _sb.from('HRMS_users').select('company_id').eq('id', userId).maybeSingle();
    final companyId = (me?['company_id'] ?? '').toString();
    if (companyId.isEmpty) throw PostgrestException(message: 'User not linked to company');

    final emp = await _sb.from('HRMS_employees').select('id').eq('company_id', companyId).eq('user_id', userId).maybeSingle();
    final empId = (emp?['id'] ?? '').toString();
    if (empId.isEmpty) throw PostgrestException(message: 'No employee profile found.');

    final wd = _workDateIST();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final existing = await _sb
        .from('HRMS_attendance_logs')
        .select(
          'id, check_in_at, check_out_at, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at',
        )
        .eq('company_id', companyId)
        .eq('employee_id', empId)
        .eq('work_date', wd)
        .maybeSingle();

    if (existing == null || existing['check_in_at'] == null) throw PostgrestException(message: 'Punch in first before starting breaks.');
    if (existing['check_out_at'] != null) throw PostgrestException(message: 'Attendance already completed for today.');

    final isLunch = kind == 'lunch';
    final lunchStarted = existing['lunch_break_started_at']?.toString();
    final teaStarted = existing['tea_break_started_at']?.toString();
    final lunchMinBase = _clampMinutes(existing['lunch_break_minutes'] as num?);
    final teaMinBase = _clampMinutes(existing['tea_break_minutes'] as num?);

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
      // stop this break
      if (isLunch) {
        nextLunchMin = _addAccumulatedMinutes(accumMin: lunchMinBase, startedAtIso: lunchStarted, nowIso: nowIso);
        nextLunchStarted = null;
        nextLunchInAt = nowIso;
      } else {
        nextTeaMin = _addAccumulatedMinutes(accumMin: teaMinBase, startedAtIso: teaStarted, nowIso: nowIso);
        nextTeaStarted = null;
        nextTeaInAt = nowIso;
      }
    } else {
      // stop other break if running
      if (isLunch && teaStarted != null && teaStarted.trim().isNotEmpty) {
        nextTeaMin = _addAccumulatedMinutes(accumMin: teaMinBase, startedAtIso: teaStarted, nowIso: nowIso);
        nextTeaStarted = null;
        nextTeaInAt = nowIso;
      }
      if (!isLunch && lunchStarted != null && lunchStarted.trim().isNotEmpty) {
        nextLunchMin = _addAccumulatedMinutes(accumMin: lunchMinBase, startedAtIso: lunchStarted, nowIso: nowIso);
        nextLunchStarted = null;
        nextLunchInAt = nowIso;
      }
      // start this break
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
          'lunch_check_out_at': nextLunchOutAt ?? null,
          'lunch_check_in_at': nextLunchInAt ?? null,
          'tea_check_out_at': nextTeaOutAt ?? null,
          'tea_check_in_at': nextTeaInAt ?? null,
          'updated_at': nowIso,
        })
        .eq('id', existing['id'])
        .select(
          'id, work_date, check_in_at, check_out_at, total_hours, lunch_break_minutes, tea_break_minutes, lunch_break_started_at, tea_break_started_at, lunch_check_out_at, lunch_check_in_at, tea_check_out_at, tea_check_in_at, status, in_office, office_note, notes',
        )
        .single();

    return Map<String, dynamic>.from(updated as Map);
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

class _Math {
  double sin(double x) => math.sin(x);
  double cos(double x) => math.cos(x);
  double sqrt(double x) => math.sqrt(x);
  double atan2(double y, double x) => math.atan2(y, x);
}


