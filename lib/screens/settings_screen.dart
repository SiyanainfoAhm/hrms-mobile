import 'package:flutter/material.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  final _rpc = RpcService();
  late TabController _tabs;

  Map<String, dynamic>? _company;
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _divisions = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _designations = [];
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _deletionRequests = [];

  bool _loading = true;
  bool _deletionBusy = false;
  Object? _err;

  @override
  void initState() {
    super.initState();
    final tabCount = widget.app.user?.role == 'super_admin' ? 6 : 5;
    _tabs = TabController(length: tabCount, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _s(dynamic v) => v?.toString() ?? '';

  bool get _isSuper => widget.app.user?.role == 'super_admin';

  Future<void> _load() async {
    final u = widget.app.user;
    final cid = u?.companyId;
    if (u == null || cid == null || cid.isEmpty) {
      setState(() {
        _loading = false;
        _err = 'No company linked to this account.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final company = await _rpc.companyGetForUser(u.id);
      final futures = <Future<dynamic>>[
        _rpc.settingsShiftsAll(cid),
        _rpc.settingsDivisionsAll(cid),
        _rpc.settingsDepartmentsAll(cid),
        _rpc.settingsDesignationsAll(cid),
        _rpc.settingsRolesAll(cid),
      ];
      if (_isSuper) {
        futures.add(_rpc.accountDeletionRequestsList(u.id));
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _company = company;
        _shifts = results[0] as List<Map<String, dynamic>>;
        _divisions = results[1] as List<Map<String, dynamic>>;
        _departments = results[2] as List<Map<String, dynamic>>;
        _designations = results[3] as List<Map<String, dynamic>>;
        _roles = results[4] as List<Map<String, dynamic>>;
        if (_isSuper && results.length > 5) {
          _deletionRequests = results[5] as List<Map<String, dynamic>>;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCompanyEditor() async {
    final u = widget.app.user;
    final c = _company;
    if (u == null || c == null || !_isSuper) return;

    final name = TextEditingController(text: _s(c['name']));
    final code = TextEditingController(text: _s(c['code']));
    final industry = TextEditingController(text: _s(c['industry']));
    final phone = TextEditingController(text: _s(c['phone']));
    final a1 = TextEditingController(text: _s(c['address_line1']));
    final a2 = TextEditingController(text: _s(c['address_line2']));
    final city = TextEditingController(text: _s(c['city']));
    final state = TextEditingController(text: _s(c['state']));
    final country = TextEditingController(text: _s(c['country']));
    final postal = TextEditingController(text: _s(c['postal_code']));
    final ptAnnual = TextEditingController(text: _s(c['professional_tax_annual']));
    final ptMonthly = TextEditingController(text: _s(c['professional_tax_monthly']));

    final err = ValueNotifier<String?>(null);
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Edit company', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String?>(
                      valueListenable: err,
                      builder: (_, e, __) => e == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ),
                    ),
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Company name *')),
                    const SizedBox(height: 8),
                    TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
                    const SizedBox(height: 8),
                    TextField(controller: industry, decoration: const InputDecoration(labelText: 'Industry')),
                    const SizedBox(height: 8),
                    TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                    const SizedBox(height: 8),
                    TextField(controller: a1, decoration: const InputDecoration(labelText: 'Address line 1')),
                    const SizedBox(height: 8),
                    TextField(controller: a2, decoration: const InputDecoration(labelText: 'Address line 2')),
                    const SizedBox(height: 8),
                    TextField(controller: city, decoration: const InputDecoration(labelText: 'City')),
                    const SizedBox(height: 8),
                    TextField(controller: state, decoration: const InputDecoration(labelText: 'State')),
                    const SizedBox(height: 8),
                    TextField(controller: country, decoration: const InputDecoration(labelText: 'Country')),
                    const SizedBox(height: 8),
                    TextField(controller: postal, decoration: const InputDecoration(labelText: 'Postal code')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ptAnnual,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Professional tax (annual)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ptMonthly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Professional tax (monthly)'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              err.value = null;
                              if (name.text.trim().isEmpty) {
                                err.value = 'Company name is required';
                                return;
                              }
                              saving = true;
                              setModal(() {});
                              try {
                                final patch = <String, dynamic>{
                                  'name': name.text.trim(),
                                  'code': code.text.trim(),
                                  'industry': industry.text.trim(),
                                  'phone': phone.text.trim(),
                                  'address_line1': a1.text.trim(),
                                  'address_line2': a2.text.trim(),
                                  'city': city.text.trim(),
                                  'state': state.text.trim(),
                                  'country': country.text.trim(),
                                  'postal_code': postal.text.trim(),
                                };
                                final pa = ptAnnual.text.trim();
                                if (pa.isNotEmpty) patch['professional_tax_annual'] = pa;
                                final pm = ptMonthly.text.trim();
                                if (pm.isNotEmpty) patch['professional_tax_monthly'] = pm;
                                final updated = await _rpc.companySave(userId: u.id, patch: patch);
                                if (!mounted) return;
                                setState(() => _company = updated);
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                err.value = e.toString();
                              } finally {
                                saving = false;
                                setModal(() {});
                              }
                            },
                      child: saving
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save company'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    name.dispose();
    code.dispose();
    industry.dispose();
    phone.dispose();
    a1.dispose();
    a2.dispose();
    city.dispose();
    state.dispose();
    country.dispose();
    postal.dispose();
    ptAnnual.dispose();
    ptMonthly.dispose();
  }

  Widget _companyTab() {
    if (_company == null) {
      return Center(child: Text(_err?.toString() ?? 'No company data.'));
    }
    final c = _company!;
    final logo = _s(c['logo_url']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isSuper)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _openCompanyEditor,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit company'),
            ),
          ),
        if (!_isSuper)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Company details are read only. Only the super admin can edit organization settings here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (logo.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(logo, height: 64, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 48)),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(_s(c['name']), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _kv('Code', _s(c['code'])),
                _kv('Industry', _s(c['industry'])),
                _kv('Phone', _s(c['phone'])),
                _kv('Address', '${_s(c['address_line1'])}\n${_s(c['address_line2'])}'.trim()),
                _kv('City', _s(c['city'])),
                _kv('State', _s(c['state'])),
                _kv('Country', _s(c['country'])),
                _kv('Postal code', _s(c['postal_code'])),
                _kv('Professional tax (annual)', _s(c['professional_tax_annual'])),
                _kv('Professional tax (monthly)', _s(c['professional_tax_monthly'])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Logo upload and full CRUD for shifts, roles, and org units are available on the web app.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _listTile(String title, String subtitle, {bool? active}) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: active == null
          ? null
          : Chip(
              label: Text(active ? 'Active' : 'Inactive'),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(fontSize: 11, color: active ? Colors.green.shade800 : Colors.black54),
            ),
    );
  }

  Widget _shiftsTab() {
    if (_shifts.isEmpty) {
      return const Center(child: Text('No shifts'));
    }
    return ListView.separated(
      itemCount: _shifts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = _shifts[i];
        final start = _s(s['start_time']);
        final end = _s(s['end_time']);
        final sub = [if (start.isNotEmpty || end.isNotEmpty) '$start — $end', if (_s(s['description']).isNotEmpty) _s(s['description'])]
            .where((e) => e.isNotEmpty)
            .join(' · ');
        return _listTile(_s(s['name']), sub, active: s['is_active'] as bool?);
      },
    );
  }

  Widget _rolesTab() {
    if (_roles.isEmpty) {
      return const Center(child: Text('No roles'));
    }
    return ListView.separated(
      itemCount: _roles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = _roles[i];
        return _listTile(_s(r['name']), _s(r['description']), active: r['is_active'] as bool?);
      },
    );
  }

  Widget _orgTab() {
    String divName(String? id) {
      if (id == null || id.isEmpty) return '';
      for (final d in _divisions) {
        if (_s(d['id']) == id) return _s(d['name']);
      }
      return '';
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Text('Divisions', style: Theme.of(context).textTheme.titleSmall),
        if (_divisions.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No divisions'))
        else
          ..._divisions.map((d) => _listTile(_s(d['name']), _s(d['description']), active: d['is_active'] as bool?)),
        const SizedBox(height: 16),
        Text('Departments', style: Theme.of(context).textTheme.titleSmall),
        if (_departments.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No departments'))
        else
          ..._departments.map((d) {
            final dn = divName(d['division_id']?.toString());
            return _listTile(_s(d['name']), dn.isEmpty ? _s(d['description']) : 'Division: $dn', active: d['is_active'] as bool?);
          }),
      ],
    );
  }

  Widget _designationsTab() {
    if (_designations.isEmpty) {
      return const Center(child: Text('No designations'));
    }
    return ListView.separated(
      itemCount: _designations.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final d = _designations[i];
        return _listTile(_s(d['title']), _s(d['description']), active: d['is_active'] as bool?);
      },
    );
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _updateDeletionRequest(String id, String status) async {
    final u = widget.app.user;
    if (u == null || !_isSuper || _deletionBusy) return;
    final verb = status == 'completed' ? 'permanently delete this user' : 'cancel this deletion request';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'completed' ? 'Delete now?' : 'Cancel request?'),
        content: Text('Are you sure you want to $verb?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deletionBusy = true);
    try {
      await _rpc.accountDeletionRequestSetStatus(
        actorUserId: u.id,
        requestId: id,
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == 'completed' ? 'User deleted' : 'Request cancelled')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _deletionBusy = false);
    }
  }

  Widget _deletionTab() {
    if (_deletionRequests.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No account deletion requests.', textAlign: TextAlign.center),
      ));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _deletionRequests.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = _deletionRequests[i];
        final status = _s(r['status']);
        final pending = status == 'pending';
        final name = _s(r['user_name']).isNotEmpty ? _s(r['user_name']) : _s(r['email']);
        final sub = [
          _s(r['email']),
          if (_s(r['employee_code']).isNotEmpty) _s(r['employee_code']),
          'Requested ${_fmtDate(_s(r['requested_at']))}',
          'Scheduled ${_fmtDate(_s(r['scheduled_deletion_at']))}',
        ].where((e) => e.isNotEmpty).join(' · ');
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(sub, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text('Status: $status', style: Theme.of(context).textTheme.labelSmall),
                if (pending) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _deletionBusy ? null : () => _updateDeletionRequest(_s(r['id']), 'cancelled'),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                        onPressed: _deletionBusy ? null : () => _updateDeletionRequest(_s(r['id']), 'completed'),
                        child: const Text('Delete now'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Company'),
            const Tab(text: 'Shifts'),
            const Tab(text: 'Roles'),
            const Tab(text: 'Org'),
            const Tab(text: 'Designations'),
            if (_isSuper) const Tab(text: 'Deletion'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null && _company == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_err.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _companyTab(),
                    _shiftsTab(),
                    _rolesTab(),
                    _orgTab(),
                    _designationsTab(),
                    if (_isSuper) _deletionTab(),
                  ],
                ),
    );
  }
}
