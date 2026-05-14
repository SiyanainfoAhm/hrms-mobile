import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'leave_power_automate_notify.dart';

/// After Supabase leave / reimbursement RPCs: optional **direct** Power Automate (`powerAutomateEmailUrl` in config),
/// else optional web webhook (`transactionNotifyUrl`) — same behaviour as before for reimbursements.
class TransactionNotifyService {
  static Future<void> leaveRequestCreated(String requestId) async {
    if (AppConfig.powerAutomateEmailUrl.trim().isNotEmpty) {
      await LeavePowerAutomateNotify.notifyLeaveRequestCreated(requestId);
      return;
    }
    await _post(<String, dynamic>{'event': 'leave_request_created', 'requestId': requestId});
  }

  static Future<void> leaveRequestDecided(String requestId) async {
    if (AppConfig.powerAutomateEmailUrl.trim().isNotEmpty) {
      await LeavePowerAutomateNotify.notifyLeaveRequestDecided(requestId);
      return;
    }
    await _post(<String, dynamic>{'event': 'leave_request_decided', 'requestId': requestId});
  }

  static Future<void> reimbursementCreated(String reimbursementId) async {
    await _post(<String, dynamic>{'event': 'reimbursement_created', 'reimbursementId': reimbursementId});
  }

  static Future<void> reimbursementDecided(String reimbursementId) async {
    await _post(<String, dynamic>{'event': 'reimbursement_decided', 'reimbursementId': reimbursementId});
  }

  static Future<void> _post(Map<String, dynamic> body) async {
    final url = AppConfig.transactionNotifyUrl.trim();
    final secret = AppConfig.transactionNotifySecret.trim();
    // Web `/api/webhooks/hrms-transaction-notify` only requires the secret header when
    // `HRMS_TRANSACTION_NOTIFY_SECRET` is set on the server. Do not skip the call when the
    // secret is empty — otherwise mobile never triggers Power Automate (same as web).
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (secret.isNotEmpty) {
        headers['x-hrms-transaction-notify-secret'] = secret;
      }
      final res = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 400) {
        // ignore — best-effort; server logs the failure
      }
    } catch (_) {
      // ignore
    }
  }
}
