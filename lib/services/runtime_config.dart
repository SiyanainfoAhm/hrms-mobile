import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class RuntimeConfig {
  RuntimeConfig._();

  static final RuntimeConfig instance = RuntimeConfig._();

  String supabaseUrl = '';
  String supabaseAnonKey = '';
  /// Public origin of the **web** HRMS app (no trailing slash), e.g. https://hrms.example.com — used to build `/invite/{token}` URLs for the Edge Function (same as `NEXT_PUBLIC_APP_URL` on web).
  String webAppInviteBaseUrl = '';
  /// Optional override; default `{webAppInviteBaseUrl}/privacy` (public page on web app).
  String privacyPolicyUrl = '';
  /// Optional override; default `{webAppInviteBaseUrl}/terms`.
  String termsUrl = '';
  /// When set, invite links in the mobile HR “Invite” tab use this origin instead of [webAppInviteBaseUrl] (e.g. production web only).
  String inviteWebOnlyBaseUrl = '';
  /// Full URL to `POST /api/webhooks/hrms-transaction-notify` on the deployed web app (triggers Power Automate emails). Optional header: same value as server `HRMS_TRANSACTION_NOTIFY_SECRET` when that env is set; leave empty when the server accepts unsigned webhooks (dev).
  String transactionNotifyUrl = '';
  String transactionNotifySecret = '';
  /// Same as hrms-web `NEXT_PUBLIC_GOOGLE_CLIENT_ID` (Web OAuth client id). Used as `serverClientId` so the ID token matches `/api/auth/google` verification. Leave empty to hide Google on login/signup.
  String googleWebClientId = '';
  /// Google Cloud **iOS** OAuth client id (not the web id). Optional on Android; on iOS you also need `CFBundleURLSchemes` in Info.plist with the reversed client id.
  String googleIosClientId = '';
  /// Google Cloud **Android** OAuth client id (not the web id). Optional; use when you are not using `android/app/google-services.json`. The Android client must still list package `com.siyanainfo.hrms_mobile` and your SHA-1 in Google Cloud Console.
  String googleAndroidClientId = '';
  /// Same as web `NEXT_PUBLIC_AGENT_DOWNLOAD_URL` — HRMS Attendance Agent installer/page (optional).
  String agentDownloadUrl = '';
  /// Same as web `POWER_AUTOMATE_EMAIL_URL` — HTTP trigger URL; mobile POSTs `{toEmail,subject,body}` with `Content-Type: application/json` only (no shared secret header).
  String powerAutomateEmailUrl = '';
  /// Same as web `HRMS_NOTIFY_HR_EMAIL` — recipient for pending leave alerts when using direct Power Automate from mobile.
  String notifyHrEmail = '';
  /// Same as web `NEXT_PUBLIC_SUPABASE_STORAGE_BUCKET` (default `photomedia`). Used for reimbursement receipt uploads from mobile.
  String reimbursementStorageBucket = 'photomedia';

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/config.json').catchError((_) async {
      return rootBundle.loadString('assets/config.template.json');
    });
    final json = jsonDecode(raw) as Map<String, dynamic>;
    supabaseUrl = (json['supabaseUrl'] ?? '').toString().trim();
    supabaseAnonKey = (json['supabaseAnonKey'] ?? '').toString().trim();
    webAppInviteBaseUrl = (json['webAppInviteBaseUrl'] ?? '').toString().trim().replaceAll(RegExp(r'/$'), '');
    privacyPolicyUrl = (json['privacyPolicyUrl'] ?? '').toString().trim();
    termsUrl = (json['termsUrl'] ?? '').toString().trim();
    inviteWebOnlyBaseUrl = (json['inviteWebOnlyBaseUrl'] ?? '').toString().trim().replaceAll(RegExp(r'/$'), '');
    transactionNotifyUrl = (json['transactionNotifyUrl'] ?? '').toString().trim();
    transactionNotifySecret = (json['transactionNotifySecret'] ?? '').toString().trim();
    googleWebClientId = (json['googleWebClientId'] ?? '').toString().trim();
    googleIosClientId = (json['googleIosClientId'] ?? '').toString().trim();
    googleAndroidClientId = (json['googleAndroidClientId'] ?? '').toString().trim();
    agentDownloadUrl = (json['agentDownloadUrl'] ?? '').toString().trim();
    powerAutomateEmailUrl = (json['powerAutomateEmailUrl'] ?? '').toString().trim();
    notifyHrEmail = (json['notifyHrEmail'] ?? '').toString().trim();
    reimbursementStorageBucket = (json['reimbursementStorageBucket'] ?? 'photomedia').toString().trim();
    if (reimbursementStorageBucket.isEmpty) reimbursementStorageBucket = 'photomedia';
  }
}

