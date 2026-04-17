import 'services/runtime_config.dart';

class AppConfig {
  static String get supabaseUrl => RuntimeConfig.instance.supabaseUrl;
  static String get supabaseAnonKey => RuntimeConfig.instance.supabaseAnonKey;
  static String get webAppInviteBaseUrl => RuntimeConfig.instance.webAppInviteBaseUrl;
}

