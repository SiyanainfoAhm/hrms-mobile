import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';

class SupabaseApp {
  static Future<void> init() async {
    if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseAnonKey.isEmpty) {
      throw StateError('Missing Supabase config. Fill apps/hrms_mobile/assets/config.json');
    }
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

