import 'package:url_launcher/url_launcher.dart';

import 'legal_config.dart';

/// Opens the public web legal page when [LegalConfig] URLs are set; otherwise returns false.
Future<bool> openLegalUrl(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
