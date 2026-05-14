import 'services/runtime_config.dart';

class AppConfig {
  static String get supabaseUrl => RuntimeConfig.instance.supabaseUrl;
  static String get supabaseAnonKey => RuntimeConfig.instance.supabaseAnonKey;
  static String get webAppInviteBaseUrl => RuntimeConfig.instance.webAppInviteBaseUrl;
  static String get inviteWebOnlyBaseUrl => RuntimeConfig.instance.inviteWebOnlyBaseUrl;
  static String get transactionNotifyUrl => RuntimeConfig.instance.transactionNotifyUrl;
  static String get transactionNotifySecret => RuntimeConfig.instance.transactionNotifySecret;
  static String get agentDownloadUrl => RuntimeConfig.instance.agentDownloadUrl;
  static String get powerAutomateEmailUrl => RuntimeConfig.instance.powerAutomateEmailUrl;
  static String get notifyHrEmail => RuntimeConfig.instance.notifyHrEmail;
  static String get reimbursementStorageBucket => RuntimeConfig.instance.reimbursementStorageBucket;

  /// Base URL for `/invite/{token}` (employee completes onboarding in the web app).
  static String get inviteLinkBaseUrl {
    final only = inviteWebOnlyBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (only.isNotEmpty) return only;
    return webAppInviteBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
  }
}

