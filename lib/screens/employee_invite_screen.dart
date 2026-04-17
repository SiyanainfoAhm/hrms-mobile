import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';
import '../services/invite_edge_service.dart';
import '../services/rpc_service.dart';
import '../state/app_state.dart';

/// Preboarding: company documents, issue/resend invite link, send email via Edge Function (same as web).
class EmployeeInviteScreen extends StatefulWidget {
  const EmployeeInviteScreen({super.key, required this.app, required this.targetUserId});

  final AppState app;
  final String targetUserId;

  @override
  State<EmployeeInviteScreen> createState() => _EmployeeInviteScreenState();
}

class _EmployeeInviteScreenState extends State<EmployeeInviteScreen> {
  final _rpc = RpcService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _onboarding;
  List<Map<String, dynamic>> _companyDocs = [];

  final _newDocName = TextEditingController();
  final _newDocContent = TextEditingController();
  String _newDocKind = 'upload';
  bool _newDocMandatory = true;
  bool _creatingDoc = false;

  @override
  void dispose() {
    _newDocName.dispose();
    _newDocContent.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final actor = widget.app.user;
    if (actor == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ob = await _rpc.employeeOnboardingForManager(
        actorUserId: actor.id,
        targetUserId: widget.targetUserId,
      );
      final docs = await _rpc.companyDocumentsList(actor.id);
      if (!mounted) return;
      setState(() {
        _onboarding = ob;
        _companyDocs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _invite {
    final inv = _onboarding?['invite'];
    if (inv is Map) return Map<String, dynamic>.from(inv);
    return null;
  }

  Map<String, dynamic>? get _employee {
    final e = _onboarding?['employee'];
    if (e is Map) return Map<String, dynamic>.from(e);
    return null;
  }

  String? _inviteUrlForToken(String? token) {
    if (token == null || token.isEmpty) return null;
    final base = AppConfig.webAppInviteBaseUrl.trim();
    if (base.isEmpty) return null;
    return '$base/invite/$token';
  }

  bool _isInviteSendable(Map<String, dynamic>? inv) {
    if (inv == null || inv['status'] != 'pending') return false;
    final ex = inv['expires_at']?.toString();
    if (ex == null || ex.isEmpty) return true;
    final t = DateTime.tryParse(ex);
    if (t == null) return true;
    return t.isAfter(DateTime.now());
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red.shade800 : null),
    );
  }

  Future<void> _sendInviteEmail() async {
    final actor = widget.app.user;
    final companyId = actor?.companyId;
    if (actor == null || companyId == null || companyId.isEmpty) return;
    final inv = _invite;
    final token = inv?['token']?.toString();
    final url = _inviteUrlForToken(token);
    if (url == null) {
      _snack(
        'Set webAppInviteBaseUrl in assets/config.json (your deployed web HRMS URL, same as NEXT_PUBLIC_APP_URL).',
        err: true,
      );
      return;
    }
    if (!_isInviteSendable(inv)) {
      _snack('No active invite. Use “New link / resend” first.', err: true);
      return;
    }
    final err = await InviteEdgeService.sendHrmsInviteEmail(
      userId: widget.targetUserId,
      companyId: companyId,
      inviteFullUrl: url,
    );
    if (!mounted) return;
    if (err != null) {
      _snack(err, err: true);
    } else {
      _snack('Invite email sent');
    }
  }

  Future<void> _copyInviteLink() async {
    final token = _invite?['token']?.toString();
    final url = _inviteUrlForToken(token);
    if (url == null) {
      _snack('Set webAppInviteBaseUrl in config, or create an invite first.', err: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _snack('Invite link copied');
  }

  Future<void> _showResendDialog() async {
    final actor = widget.app.user;
    if (actor == null) return;
    final emp = _employee;
    final email = emp?['email']?.toString() ?? '';
    if (email.isEmpty) {
      _snack('Employee email missing', err: true);
      return;
    }

    final selected = <String>{..._defaultRequestedDocIds()};
    var sendEmail = true;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Send documents again'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Link valid 48 hours. Email: $email', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                if (_companyDocs.isEmpty)
                  const Text('No company documents. Add one below first.', style: TextStyle(color: Colors.orange))
                else
                  ..._companyDocs.map((d) {
                    final id = d['id']?.toString() ?? '';
                    final name = d['name']?.toString() ?? id;
                    final kind = d['kind']?.toString() ?? '';
                    final man = d['is_mandatory'] == true;
                    return CheckboxListTile(
                      dense: true,
                      title: Text(name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text('$kind${man ? ", mandatory" : ""}', style: const TextStyle(fontSize: 11)),
                      value: selected.contains(id),
                      onChanged: id.isEmpty
                          ? null
                          : (v) {
                              setDlg(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              });
                            },
                    );
                  }),
                SwitchListTile(
                  title: const Text('Send invite email'),
                  value: sendEmail,
                  onChanged: busy
                      ? null
                      : (v) => setDlg(() => sendEmail = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDlg(() => busy = true);
                      try {
                        final ids = selected.toList();
                        final data = await _rpc.employeeInviteIssue(
                          actorUserId: actor.id,
                          email: email,
                          targetUserId: widget.targetUserId,
                          requestedDocumentIds: ids.isEmpty ? null : ids,
                        );
                        final invMap = data['invite'];
                        final token = invMap is Map ? invMap['token']?.toString() : null;
                        final url = _inviteUrlForToken(token);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _load();
                        if (!mounted) return;
                        if (sendEmail && url != null && actor.companyId != null) {
                          final mailErr = await InviteEdgeService.sendHrmsInviteEmail(
                            userId: widget.targetUserId,
                            companyId: actor.companyId!,
                            inviteFullUrl: url,
                          );
                          if (mailErr != null) {
                            await Clipboard.setData(ClipboardData(text: url));
                            _snack('Email failed ($mailErr). Link copied.');
                          } else {
                            _snack('New invite emailed (48h)');
                          }
                        } else if (url != null) {
                          await Clipboard.setData(ClipboardData(text: url));
                          _snack(sendEmail ? 'Set webAppInviteBaseUrl to send email. Link copied.' : 'Link copied.');
                        } else {
                          _snack('Invite created. Set webAppInviteBaseUrl to copy/send link.', err: true);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDlg(() => busy = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(e is PostgrestException ? e.message : e.toString())),
                          );
                        }
                      }
                    },
              child: const Text('Issue link'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _defaultRequestedDocIds() {
    return _companyDocs.where((d) => d['is_mandatory'] == true).map((d) => d['id']?.toString()).whereType<String>().toList();
  }

  Future<void> _createCompanyDocument() async {
    final actor = widget.app.user;
    if (actor == null) return;
    final name = _newDocName.text.trim();
    if (name.isEmpty) {
      _snack('Document name required', err: true);
      return;
    }
    setState(() => _creatingDoc = true);
    try {
      await _rpc.companyDocumentCreate(
        actorUserId: actor.id,
        name: name,
        kind: _newDocKind,
        isMandatory: _newDocMandatory,
        contentText: _newDocKind == 'digital_signature' ? _newDocContent.text.trim() : null,
      );
      _newDocName.clear();
      _newDocContent.clear();
      if (!mounted) return;
      _snack('Document added');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(e is PostgrestException ? e.message : e.toString(), err: true);
    } finally {
      if (mounted) setState(() => _creatingDoc = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = _employee;
    final namePart = emp?['name']?.toString().trim();
    final title =
        (namePart != null && namePart.isNotEmpty) ? namePart : (emp?['email'] ?? 'Employee').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Invite', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Status: ${_invite?['status'] ?? "—"}', style: const TextStyle(fontSize: 14)),
                      Text(
                        'Expires: ${_invite?['expires_at'] ?? "—"}',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _isInviteSendable(_invite) ? _sendInviteEmail : null,
                            child: const Text('Send invite email'),
                          ),
                          OutlinedButton(onPressed: _copyInviteLink, child: const Text('Copy link')),
                          OutlinedButton(onPressed: _showResendDialog, child: const Text('New link / resend')),
                        ],
                      ),
                      if (!_isInviteSendable(_invite))
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'No active pending invite (or expired). Use “New link / resend”.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text('Add company document', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _newDocName,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _newDocKind,
                        decoration: const InputDecoration(labelText: 'Kind'),
                        items: const [
                          DropdownMenuItem(value: 'upload', child: Text('upload')),
                          DropdownMenuItem(value: 'digital_signature', child: Text('digital_signature')),
                        ],
                        onChanged: (v) => setState(() => _newDocKind = v ?? 'upload'),
                      ),
                      SwitchListTile(
                        title: const Text('Mandatory'),
                        value: _newDocMandatory,
                        onChanged: (v) => setState(() => _newDocMandatory = v),
                      ),
                      if (_newDocKind == 'digital_signature')
                        TextField(
                          controller: _newDocContent,
                          decoration: const InputDecoration(labelText: 'Content / template (optional)'),
                          maxLines: 3,
                        ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _creatingDoc ? null : _createCompanyDocument,
                        child: Text(_creatingDoc ? 'Saving…' : 'Create document'),
                      ),
                      const SizedBox(height: 24),
                      Text('Requested documents & status', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _DocumentsTable(
                        documents: _docListFromOnboarding(),
                        submissions: _subListFromOnboarding(),
                      ),
                    ],
                  ),
                ),
    );
  }

  List<Map<String, dynamic>> _docListFromOnboarding() {
    final d = _onboarding?['documents'];
    if (d is! List) return [];
    return d.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> _subListFromOnboarding() {
    final s = _onboarding?['submissions'];
    if (s is! List) return [];
    return s.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}

class _DocumentsTable extends StatelessWidget {
  const _DocumentsTable({required this.documents, required this.submissions});

  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> submissions;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return const Text('No documents on this invite yet.', style: TextStyle(color: Colors.black54));
    }
    return Table(
      border: TableBorder.all(color: Colors.black12),
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            Padding(padding: EdgeInsets.all(8), child: Text('Name', style: TextStyle(fontWeight: FontWeight.w600))),
            Padding(padding: EdgeInsets.all(8), child: Text('Type', style: TextStyle(fontWeight: FontWeight.w600))),
            Padding(padding: EdgeInsets.all(8), child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        ...documents.map((d) {
          final did = d['id']?.toString();
          Map<String, dynamic>? sub;
          for (final s in submissions) {
            if (s['document_id']?.toString() == did) {
              sub = s;
              break;
            }
          }
          return TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(d['name']?.toString() ?? '—', style: const TextStyle(fontSize: 13))),
              Padding(padding: const EdgeInsets.all(8), child: Text(d['kind']?.toString() ?? '—', style: const TextStyle(fontSize: 13))),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(sub?['status']?.toString() ?? 'pending', style: const TextStyle(fontSize: 13)),
              ),
            ],
          );
        }),
      ],
    );
  }
}
