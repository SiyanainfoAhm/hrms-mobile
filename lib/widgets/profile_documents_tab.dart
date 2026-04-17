import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/hrms_card.dart';

/// Lists files the user submitted during onboarding (`HRMS_employee_document_submissions`).
class ProfileDocumentsTab extends StatefulWidget {
  const ProfileDocumentsTab({super.key, required this.app});

  final AppState app;

  @override
  State<ProfileDocumentsTab> createState() => _ProfileDocumentsTabState();
}

class _ProfileDocumentsTabState extends State<ProfileDocumentsTab> {
  final _rpc = RpcService();
  bool _loading = true;
  Object? _err;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final list = await _rpc.myDocumentsList(u.id);
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _s(dynamic v) => v?.toString() ?? '';

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid link')));
      }
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(HrmsTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_err', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(HrmsTokens.s6),
          child: Text(
            'No documents on file yet. Complete onboarding invites or uploads from the web app when your HR team requests them.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: HrmsTokens.muted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(HrmsTokens.s4),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final name = _s(r['document_name']);
          final kind = _s(r['kind']);
          final status = _s(r['status']);
          final fileUrl = _s(r['file_url']);
          final sig = _s(r['signature_name']);
          final submitted = _s(r['submitted_at']);
          final signed = _s(r['signed_at']);
          final note = _s(r['review_note']);

          return HrmsCard(
            title: name,
            subtitle: null,
            trailing: fileUrl.isNotEmpty
                ? const Icon(Icons.open_in_new, size: 18, color: HrmsTokens.primary)
                : const Icon(Icons.insert_drive_file_outlined, size: 18, color: HrmsTokens.muted),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(
                      label: Text(kind == 'digital_signature' ? 'E-sign' : 'Upload', style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    Chip(
                      label: Text(status, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                if (submitted.isNotEmpty) Text('Submitted: $submitted', style: Theme.of(context).textTheme.bodySmall),
                if (signed.isNotEmpty) Text('Signed: $signed', style: Theme.of(context).textTheme.bodySmall),
                if (sig.isNotEmpty) Text('Signed as: $sig', style: Theme.of(context).textTheme.bodySmall),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Note: $note', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HrmsTokens.text)),
                  ),
                if (fileUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _openUrl(fileUrl),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open file'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
