import '../services/runtime_config.dart';

/// Update these values before publishing to Google Play / Apple App Store.
class LegalConfig {
  LegalConfig._();

  static const String appName = 'HRMS';
  static const String legalEntityName = 'Siyana Info Solution Private Limited';
  static const String contactEmail = 'hr@siyanainfo.com';
  static const String registeredAddress =
      'Office 406/407, Navratna Corporate Park, NR Ashok Vatika, Ambli Road, Ambli, Ahmedabad, Gujarat 380015, India';

  /// Shown at the top of each legal document.
  static const String privacyPolicyEffectiveDate = '15 May 2026';
  static const String termsEffectiveDate = '15 May 2026';

  static const String governingLawRegion = 'India';

  /// Public privacy policy on the web app (Play Store / in-app links). From [RuntimeConfig.webAppInviteBaseUrl].
  static String get privacyPolicyUrl {
    final explicit = RuntimeConfig.instance.privacyPolicyUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    final base = RuntimeConfig.instance.webAppInviteBaseUrl.trim();
    if (base.isEmpty) return '';
    return '$base/privacy';
  }

  /// Public terms on the web app. From [RuntimeConfig.webAppInviteBaseUrl].
  static String get termsUrl {
    final explicit = RuntimeConfig.instance.termsUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    final base = RuntimeConfig.instance.webAppInviteBaseUrl.trim();
    if (base.isEmpty) return '';
    return '$base/terms';
  }
}
