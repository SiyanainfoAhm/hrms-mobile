import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../app_config.dart';
import 'supabase_client.dart';

/// Same cap as web `REIMB_MAX_BYTES` in ApprovalsContent.
const int reimbursementAttachmentMaxBytes = 8 * 1024 * 1024;

/// Same sanitization as web `/api/reimbursements/upload` (`safeName`).
String reimbursementSafeFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  if (safe.isEmpty) return 'attachment';
  return safe.length > 120 ? safe.substring(0, 120) : safe;
}

String reimbursementGuessContentType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'application/octet-stream';
}

Future<Uint8List> reimbursementReadPickedBytes(PlatformFile picked) async {
  if (picked.bytes != null && picked.bytes!.isNotEmpty) {
    return picked.bytes!;
  }
  throw StateError('Could not read file contents. Pick the file again if prompted.');
}

/// Upload path mirrors web `POST /api/reimbursements/upload`: `HRMS/{companyId}/reimbursements/{uuid}_{safeName}`.
Future<String> uploadReimbursementReceiptToStorage({
  required String companyId,
  required PlatformFile picked,
}) async {
  final bytes = await reimbursementReadPickedBytes(picked);
  if (bytes.isEmpty) {
    throw StateError('Choose a valid attachment file');
  }
  if (bytes.length > reimbursementAttachmentMaxBytes) {
    throw StateError('Attachment must be 8 MB or smaller');
  }
  final safe = reimbursementSafeFileName(picked.name);
  final id = Uuid().v4();
  final objectPath = 'HRMS/$companyId/reimbursements/${id}_$safe';
  final bucket = AppConfig.reimbursementStorageBucket;
  final client = SupabaseApp.client;
  try {
    await client.storage.from(bucket).uploadBinary(
      objectPath,
      bytes,
      fileOptions: FileOptions(
        contentType: reimbursementGuessContentType(picked.name),
        upsert: false,
      ),
    );
  } on StorageException catch (e) {
    throw StateError(e.message.isNotEmpty ? e.message : 'Upload failed');
  }
  final url = client.storage.from(bucket).getPublicUrl(objectPath);
  if (url.isEmpty) {
    throw StateError('Upload did not return a file URL');
  }
  return url;
}
