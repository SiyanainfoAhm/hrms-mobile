import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Calls deployed Edge Function `send-hrms-invite-email` with the same JSON as the web app
/// (`userId`, `companyId`, full `link`). The function checks the link matches the pending invite token.
class InviteEdgeService {
  static Future<String?> sendHrmsInviteEmail({
    required String userId,
    required String companyId,
    required String inviteFullUrl,
  }) async {
    try {
      final res = await SupabaseApp.client.functions.invoke(
        'send-hrms-invite-email',
        body: <String, dynamic>{
          'userId': userId,
          'companyId': companyId,
          'link': inviteFullUrl,
        },
      );
      final data = res.data;
      if (data is Map) {
        final ok = data['success'];
        if (ok == false) {
          return (data['message'] ?? 'Invite email failed').toString();
        }
      }
      return null;
    } on FunctionException catch (e) {
      final r = e.reasonPhrase;
      return (r != null && r.isNotEmpty) ? r : e.toString();
    } catch (e) {
      return e.toString();
    }
  }
}
