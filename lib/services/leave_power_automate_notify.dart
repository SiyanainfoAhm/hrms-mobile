import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'supabase_client.dart';

/// Same JSON body as web `sendPowerAutomateEmail` (`src/lib/powerAutomateEmail.ts`); no shared-secret header.
/// HTML matches web `buildLeaveEmailHtml` (`src/lib/leaveEmail.ts`).
class LeavePowerAutomateNotify {
  LeavePowerAutomateNotify._();

  static String _hrEmail() {
    final o = AppConfig.notifyHrEmail.trim();
    if (o.isNotEmpty) return o;
    return 'hr@siyanainfo.com';
  }

  static String _publicAppUrl() {
    return AppConfig.webAppInviteBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
  }

  static String escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String buildLeaveEmailHtml({
    required String title,
    String? companyName,
    String? employeeName,
    String? employeeEmail,
    String? leaveTypeName,
    required String startDate,
    required String endDate,
    required num totalDays,
    num? paidDays,
    num? unpaidDays,
    String? reason,
    String? status,
    String? rejectionReason,
  }) {
    final org = (companyName?.trim().isNotEmpty == true)
        ? '<strong>${escapeHtml(companyName!.trim())}</strong>'
        : 'HRMS';
    final empName = (employeeName?.trim().isNotEmpty == true) ? escapeHtml(employeeName!.trim()) : 'Employee';
    final empEmail = (employeeEmail?.trim().isNotEmpty == true) ? escapeHtml(employeeEmail!.trim()) : '';
    final lt = (leaveTypeName?.trim().isNotEmpty == true) ? escapeHtml(leaveTypeName!.trim()) : 'Leave';
    final reasonEsc = (reason?.trim().isNotEmpty == true) ? escapeHtml(reason!.trim()) : '—';
    final statusEsc = (status?.trim().isNotEmpty == true) ? escapeHtml(status!.trim()) : '';
    final rej = (rejectionReason?.trim().isNotEmpty == true) ? escapeHtml(rejectionReason!.trim()) : '';

    final paid = paidDays;
    final unpaid = unpaidDays;
    final appUrl = escapeHtml(_publicAppUrl());

    final paidUnpaidRow = (paid != null || unpaid != null)
        ? '''<tr>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;"><strong>Paid / Unpaid</strong></td>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;text-align:right;">${paid != null ? escapeHtml('$paid') : '—'} / ${unpaid != null ? escapeHtml('$unpaid') : '—'}</td>
            </tr>'''
        : '';

    final rejRow = rej.isNotEmpty
        ? '''<tr>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;"><strong>Rejection reason</strong></td>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;text-align:right;">$rej</td>
            </tr>'''
        : '';

    final statusBlock = statusEsc.isNotEmpty
        ? '<div style="font-size:13px;color:#334155;margin-bottom:14px;">Status: <strong>$statusEsc</strong></div>'
        : '';

    return '''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;line-height:1.55;color:#0f172a;background:#f1f5f9;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:24px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:#ffffff;border-radius:14px;border:1px solid #e2e8f0;box-shadow:0 10px 40px rgba(15,23,42,0.06);">
        <tr><td style="padding:28px 24px 20px;">
          <div style="font-size:12px;color:#64748b;margin-bottom:10px;">$org</div>
          <div style="font-size:18px;font-weight:700;margin-bottom:8px;">${escapeHtml(title)}</div>
          $statusBlock
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;">
            <tr>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;"><strong>Employee</strong></td>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;text-align:right;">$empName${empEmail.isNotEmpty ? ' &lt;$empEmail&gt;' : ''}</td>
            </tr>
            <tr>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;"><strong>Leave type</strong></td>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;text-align:right;">$lt</td>
            </tr>
            <tr>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;"><strong>Dates</strong></td>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;text-align:right;">${escapeHtml(startDate)} → ${escapeHtml(endDate)}</td>
            </tr>
            <tr>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;"><strong>Total days</strong></td>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;text-align:right;">${escapeHtml('$totalDays')}</td>
            </tr>
            $paidUnpaidRow
            <tr>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;"><strong>Reason</strong></td>
              <td style="padding:10px 0;border-top:1px solid #e2e8f0;text-align:right;">$reasonEsc</td>
            </tr>
            $rejRow
          </table>
          <div style="margin-top:20px;text-align:center;">
            <a href="$appUrl" style="display:inline-block;background:#047857;color:#ffffff !important;text-decoration:none;padding:12px 22px;border-radius:10px;font-weight:700;font-size:14px;">Open HRMS Web</a>
          </div>
          <div style="margin-top:10px;font-size:12px;color:#64748b;text-align:center;">If the button doesn’t work, open: <span style="color:#0f766e;word-break:break-all;">$appUrl</span></div>
          <div style="margin-top:18px;font-size:12px;color:#94a3b8;">This is an automated message from HRMS.</div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>''';
  }

  static Future<void> _sendPowerAutomateEmail({
    required String toEmail,
    required String subject,
    required String body,
  }) async {
    final url = AppConfig.powerAutomateEmailUrl.trim();
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{'toEmail': toEmail, 'subject': subject, 'body': body}),
        )
        .timeout(const Duration(seconds: 20));
  }

  /// Mirrors web `notifyLeaveRequestCreated` + `sendPowerAutomateEmail`.
  static Future<void> notifyLeaveRequestCreated(String requestId) async {
    if (AppConfig.powerAutomateEmailUrl.trim().isEmpty) return;
    try {
      final client = SupabaseApp.client;
      final row = await client
          .from('HRMS_leave_requests')
          .select('*, HRMS_leave_types(name)')
          .eq('id', requestId)
          .maybeSingle();
      if (row == null) return;

      final companyId = (row['company_id'] ?? '').toString();
      final employeeUserId = (row['employee_user_id'] ?? '').toString();
      final nested = row['HRMS_leave_types'];
      var leaveTypeName = 'Leave';
      if (nested is Map) {
        leaveTypeName = (nested['name'] ?? 'Leave').toString();
      }
      final startDate = (row['start_date'] ?? '').toString();
      final endDate = (row['end_date'] ?? '').toString();
      final totalDays = num.tryParse('${row['total_days'] ?? 0}') ?? 0;
      final paidDays = num.tryParse('${row['paid_days'] ?? 0}');
      final unpaidDays = num.tryParse('${row['unpaid_days'] ?? 0}');
      final reason = row['reason']?.toString();
      final autoApprove = (row['status'] ?? '').toString() == 'approved';

      Map<String, dynamic>? empRow;
      if (employeeUserId.isNotEmpty) {
        empRow = await client.from('HRMS_users').select('name, email').eq('id', employeeUserId).maybeSingle();
      }
      final employeeName = empRow?['name']?.toString();
      final employeeEmail = empRow?['email']?.toString();

      Map<String, dynamic>? companyRow;
      if (companyId.isNotEmpty) {
        companyRow = await client.from('HRMS_companies').select('name').eq('id', companyId).maybeSingle();
      }
      final companyName = companyRow?['name']?.toString();

      if (autoApprove) {
        final to = employeeEmail?.trim();
        if (to == null || to.isEmpty) return;
        final subject = '${companyName != null && companyName.isNotEmpty ? '$companyName — ' : ''}Leave approved: $startDate to $endDate';
        final html = buildLeaveEmailHtml(
          title: 'Your leave has been approved',
          companyName: companyName,
          employeeName: employeeName,
          employeeEmail: employeeEmail,
          leaveTypeName: leaveTypeName,
          startDate: startDate,
          endDate: endDate,
          totalDays: totalDays,
          paidDays: paidDays,
          unpaidDays: unpaidDays,
          reason: reason,
          status: 'approved',
        );
        await _sendPowerAutomateEmail(toEmail: to, subject: subject, body: html);
      } else {
        final to = _hrEmail();
        final subject =
            '${companyName != null && companyName.isNotEmpty ? '$companyName — ' : ''}Leave request: ${employeeName ?? employeeEmail ?? 'Employee'} ($startDate to $endDate)';
        final html = buildLeaveEmailHtml(
          title: 'New leave request',
          companyName: companyName,
          employeeName: employeeName,
          employeeEmail: employeeEmail,
          leaveTypeName: leaveTypeName,
          startDate: startDate,
          endDate: endDate,
          totalDays: totalDays,
          paidDays: paidDays,
          unpaidDays: unpaidDays,
          reason: reason,
          status: 'pending',
        );
        await _sendPowerAutomateEmail(toEmail: to, subject: subject, body: html);
      }
    } catch (_) {
      // best-effort (RLS/network/PA); same as TransactionNotifyService
    }
  }

  /// Mirrors web `notifyLeaveRequestDecided`.
  static Future<void> notifyLeaveRequestDecided(String requestId) async {
    if (AppConfig.powerAutomateEmailUrl.trim().isEmpty) return;
    try {
      final client = SupabaseApp.client;
      final row = await client.from('HRMS_leave_requests').select('*').eq('id', requestId).maybeSingle();
      if (row == null) return;

      final companyId = (row['company_id'] ?? '').toString();
      final employeeUserId = (row['employee_user_id'] ?? '').toString();
      final leaveTypeId = (row['leave_type_id'] ?? '').toString();

      Map<String, dynamic>? empRow;
      if (employeeUserId.isNotEmpty) {
        empRow = await client.from('HRMS_users').select('name, email').eq('id', employeeUserId).maybeSingle();
      }
      final employeeEmail = empRow?['email']?.toString().trim();
      if (employeeEmail == null || employeeEmail.isEmpty) return;
      final employeeName = empRow?['name']?.toString();

      Map<String, dynamic>? companyRow;
      if (companyId.isNotEmpty) {
        companyRow = await client.from('HRMS_companies').select('name').eq('id', companyId).maybeSingle();
      }
      final companyName = companyRow?['name']?.toString();

      String leaveTypeName = 'Leave';
      if (leaveTypeId.isNotEmpty) {
        final lt = await client.from('HRMS_leave_types').select('name').eq('id', leaveTypeId).maybeSingle();
        leaveTypeName = (lt?['name'] ?? 'Leave').toString();
      }

      final startDate = (row['start_date'] ?? '').toString();
      final endDate = (row['end_date'] ?? '').toString();
      final totalDays = num.tryParse('${row['total_days'] ?? 0}') ?? 0;
      final paidDays = num.tryParse('${row['paid_days'] ?? 0}');
      final unpaidDays = num.tryParse('${row['unpaid_days'] ?? 0}');
      final status = (row['status'] ?? '').toString();
      final rejectionReason = row['rejection_reason']?.toString();
      final reason = row['reason']?.toString();

      final isApproved = status == 'approved';
      final subject =
          '${companyName != null && companyName.isNotEmpty ? '$companyName — ' : ''}Leave ${isApproved ? 'approved' : 'rejected'}: $startDate to $endDate';
      final html = buildLeaveEmailHtml(
        title: isApproved ? 'Your leave has been approved' : 'Your leave has been rejected',
        companyName: companyName,
        employeeName: employeeName,
        employeeEmail: employeeEmail,
        leaveTypeName: leaveTypeName,
        startDate: startDate,
        endDate: endDate,
        totalDays: totalDays,
        paidDays: paidDays,
        unpaidDays: unpaidDays,
        reason: reason,
        status: status,
        rejectionReason: rejectionReason,
      );
      await _sendPowerAutomateEmail(toEmail: employeeEmail, subject: subject, body: html);
    } catch (_) {}
  }
}
