import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/formatters.dart';
import '../widgets/app_drawer.dart';
import '../widgets/profile_documents_tab.dart';
import '../widgets/profile_pay_tab.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.app});

  final AppState app;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _rpc = RpcService();

  bool _loading = true;
  Object? _err;
  String? _success;
  bool _saving = false;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _designations = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _divisions = [];
  List<Map<String, dynamic>> _shifts = [];

  String? _gender;
  String _employmentStatus = 'preboarding';
  String? _departmentId;
  String? _divisionId;
  String? _shiftId;

  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _employeeCode = TextEditingController();
  late final TextEditingController _phone = TextEditingController();
  late final TextEditingController _designation = TextEditingController();
  late final TextEditingController _aadhaar = TextEditingController();
  late final TextEditingController _pan = TextEditingController();
  late final TextEditingController _uan = TextEditingController();
  late final TextEditingController _pf = TextEditingController();
  late final TextEditingController _esic = TextEditingController();
  late final TextEditingController _dob = TextEditingController();
  late final TextEditingController _doj = TextEditingController();
  late final TextEditingController _ctc = TextEditingController();
  late final TextEditingController _cur1 = TextEditingController();
  late final TextEditingController _cur2 = TextEditingController();
  late final TextEditingController _curCity = TextEditingController();
  late final TextEditingController _curState = TextEditingController();
  late final TextEditingController _curCountry = TextEditingController();
  late final TextEditingController _curPostal = TextEditingController();
  late final TextEditingController _perm1 = TextEditingController();
  late final TextEditingController _perm2 = TextEditingController();
  late final TextEditingController _permCity = TextEditingController();
  late final TextEditingController _permState = TextEditingController();
  late final TextEditingController _permCountry = TextEditingController();
  late final TextEditingController _permPostal = TextEditingController();
  late final TextEditingController _emName = TextEditingController();
  late final TextEditingController _emPhone = TextEditingController();
  late final TextEditingController _bankName = TextEditingController();
  late final TextEditingController _bankAcct = TextEditingController();
  late final TextEditingController _bankIfsc = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _employeeCode.dispose();
    _phone.dispose();
    _designation.dispose();
    _aadhaar.dispose();
    _pan.dispose();
    _uan.dispose();
    _pf.dispose();
    _esic.dispose();
    _dob.dispose();
    _doj.dispose();
    _ctc.dispose();
    _cur1.dispose();
    _cur2.dispose();
    _curCity.dispose();
    _curState.dispose();
    _curCountry.dispose();
    _curPostal.dispose();
    _perm1.dispose();
    _perm2.dispose();
    _permCity.dispose();
    _permState.dispose();
    _permCountry.dispose();
    _permPostal.dispose();
    _emName.dispose();
    _emPhone.dispose();
    _bankName.dispose();
    _bankAcct.dispose();
    _bankIfsc.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _str(dynamic v) => v?.toString() ?? '';

  String _dateStr(dynamic v) {
    final s = _str(v);
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  bool get _isSuper => widget.app.user?.role == 'super_admin';

  bool get _canEditEmployment {
    final r = widget.app.user?.role ?? '';
    return r == 'super_admin' || r == 'admin' || r == 'hr';
  }

  bool get _isEmployee => widget.app.user?.role == 'employee';

  /// Matches web: org fields editable only for super_admin/admin/hr.
  bool get _canEditOrgFields {
    final r = widget.app.user?.role ?? '';
    return r == 'super_admin' || r == 'admin' || r == 'hr';
  }

  Future<void> _load() async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() {
      _loading = true;
      _err = null;
      _success = null;
    });
    try {
      final p = await _rpc.profileFullGet(u.id);
      if (p == null) throw Exception('Profile not found');
      if (!_isSuper && u.companyId != null && u.companyId!.isNotEmpty) {
        final cid = u.companyId!;
        final results = await Future.wait([
          _rpc.settingsDesignations(cid),
          _rpc.settingsDepartments(cid),
          _rpc.settingsDivisions(cid),
          _rpc.settingsShifts(cid),
        ]);
        _designations = results[0];
        _departments = results[1];
        _divisions = results[2];
        _shifts = results[3];
      }
      _applyProfile(p);
      setState(() => _profile = p);
    } catch (e) {
      setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyProfile(Map<String, dynamic> p) {
    _name.text = _str(p['name']);
    _employeeCode.text = _str(p['employee_code']);
    _phone.text = _str(p['phone']);
    _designation.text = _str(p['designation']);
    _aadhaar.text = _str(p['aadhaar']);
    _pan.text = _str(p['pan']);
    _uan.text = _str(p['uan_number']);
    _pf.text = _str(p['pf_number']);
    _esic.text = _str(p['esic_number']);
    _dob.text = UiFormatters.fmtDmy(_dateStr(p['date_of_birth']));
    _doj.text = UiFormatters.fmtDmy(_dateStr(p['date_of_joining']));
    final ctc = p['ctc'];
    _ctc.text = ctc == null ? '' : ctc.toString();
    _cur1.text = _str(p['current_address_line1']);
    _cur2.text = _str(p['current_address_line2']);
    _curCity.text = _str(p['current_city']);
    _curState.text = _str(p['current_state']);
    _curCountry.text = _str(p['current_country']);
    _curPostal.text = _str(p['current_postal_code']);
    _perm1.text = _str(p['permanent_address_line1']);
    _perm2.text = _str(p['permanent_address_line2']);
    _permCity.text = _str(p['permanent_city']);
    _permState.text = _str(p['permanent_state']);
    _permCountry.text = _str(p['permanent_country']);
    _permPostal.text = _str(p['permanent_postal_code']);
    _emName.text = _str(p['emergency_contact_name']);
    _emPhone.text = _str(p['emergency_contact_phone']);
    _bankName.text = _str(p['bank_name']);
    _bankAcct.text = _str(p['bank_account_number']);
    _bankIfsc.text = _str(p['bank_ifsc']);

    final g = _str(p['gender']);
    _gender = const ['male', 'female', 'other'].contains(g) ? g : null;
    final es = _str(p['employment_status']);
    _employmentStatus = const ['preboarding', 'current', 'past'].contains(es) ? es : 'preboarding';
    final did = p['department_id']?.toString();
    _departmentId = did != null && did.isNotEmpty ? did : null;
    final vid = p['division_id']?.toString();
    _divisionId = vid != null && vid.isNotEmpty ? vid : null;
    final sid = p['shift_id']?.toString();
    _shiftId = sid != null && sid.isNotEmpty ? sid : null;
  }

  String _designationIdForSave() {
    final t = _designation.text.trim();
    if (t.isEmpty) return '';
    for (final d in _designations) {
      if (_str(d['title']).toLowerCase() == t.toLowerCase()) {
        return d['id']?.toString() ?? '';
      }
    }
    return '';
  }

  Map<String, dynamic> _buildPatch() {
    if (_isSuper) {
      return {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'gender': _gender ?? '',
      };
    }
    final dobYmd = UiFormatters.ymdFromDmy(_dob.text);
    final dojYmd = UiFormatters.ymdFromDmy(_doj.text);
    final patch = <String, dynamic>{
      'name': _name.text.trim(),
      if (_canEditOrgFields) 'employee_code': _employeeCode.text.trim(),
      'phone': _phone.text.trim(),
      'gender': _gender ?? '',
      'aadhaar': _aadhaar.text.trim(),
      'pan': _pan.text.trim(),
      'date_of_birth': dobYmd,
      if (_canEditOrgFields) 'date_of_joining': dojYmd,
      'current_address_line1': _cur1.text.trim(),
      'current_address_line2': _cur2.text.trim(),
      'current_city': _curCity.text.trim(),
      'current_state': _curState.text.trim(),
      'current_country': _curCountry.text.trim(),
      'current_postal_code': _curPostal.text.trim(),
      'permanent_address_line1': _perm1.text.trim(),
      'permanent_address_line2': _perm2.text.trim(),
      'permanent_city': _permCity.text.trim(),
      'permanent_state': _permState.text.trim(),
      'permanent_country': _permCountry.text.trim(),
      'permanent_postal_code': _permPostal.text.trim(),
      'emergency_contact_name': _emName.text.trim(),
      'emergency_contact_phone': _emPhone.text.trim(),
      'bank_name': _bankName.text.trim(),
      'bank_account_number': _bankAcct.text.trim(),
      'bank_ifsc': _bankIfsc.text.trim(),
    };
    if (_canEditOrgFields) {
      patch['designation'] = _designation.text.trim();
      patch['designation_id'] = _designationIdForSave();
      patch['department_id'] = _departmentId ?? '';
      patch['division_id'] = _divisionId ?? '';
      patch['shift_id'] = _shiftId ?? '';
    }
    if (_canEditOrgFields) {
      patch['pf_number'] = _pf.text.trim();
      patch['esic_number'] = _esic.text.trim();
    }
    if (_canEditEmployment) {
      patch['employment_status'] = _employmentStatus;
      patch['ctc'] = _ctc.text.trim();
      patch['uan_number'] = _uan.text.trim();
    }
    return patch;
  }

  Future<void> _save() async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() {
      _saving = true;
      _err = null;
      _success = null;
    });
    try {
      final updated = await _rpc.profileFullSave(
        userId: u.id,
        actorRole: u.role,
        patch: _buildPatch(),
      );
      await widget.app.applyProfileRow(updated);
      _applyProfile(updated);
      if (mounted) {
        setState(() {
          _profile = updated;
          _success = 'Saved';
        });
      }
    } catch (e) {
      setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: HrmsTokens.text)),
    );
  }

  Widget _fieldGap() => const SizedBox(height: 14);

  Widget _labeledField(String label, Widget field, {String? helperText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        field,
        if (helperText != null && helperText.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(helperText, style: const TextStyle(fontSize: 12, color: HrmsTokens.muted)),
        ],
      ],
    );
  }

  Future<void> _pickDateInto(TextEditingController c) async {
    final now = DateTime.now();
    final parsed = UiFormatters.ymdFromDmy(c.text);
    final init = DateTime.tryParse(parsed.isNotEmpty ? parsed : '') ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final ymd =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() => c.text = UiFormatters.fmtDmy(ymd));
  }

  Widget _genderField() {
    return _labeledField(
      'Gender',
      DropdownButtonFormField<String?>(
        value: _gender,
        decoration: const InputDecoration(),
        items: const [
          DropdownMenuItem<String?>(value: null, child: Text('Select')),
          DropdownMenuItem<String?>(value: 'male', child: Text('Male')),
          DropdownMenuItem<String?>(value: 'female', child: Text('Female')),
          DropdownMenuItem<String?>(value: 'other', child: Text('Other')),
        ],
        onChanged: (v) => setState(() => _gender = v),
      ),
      helperText: 'Used for avatar display on dashboard.',
    );
  }

  Widget _profileFormBody() {
    final u = widget.app.user!;
    final auth = _str(_profile?['auth_provider'] == null ? u.authProvider : _profile!['auth_provider']);

    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (_err != null && _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_err', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_err != null) Text('$_err', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_success != null) Text(_success!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        if (u.isManagerial) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Organization settings'),
            subtitle: const Text('Company, shifts, roles, org structure'),
            onTap: () => context.go('/settings'),
          ),
          const Divider(),
        ],
        if (_isSuper) ...[
          Text(
            'You are the master admin. Manage companies from Settings; only basic account fields apply here.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(u.email, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Email (read only)'),
          ),
          _fieldGap(),
          _labeledField('Full name', TextField(controller: _name, decoration: const InputDecoration())),
          _fieldGap(),
          _labeledField('Phone', TextField(controller: _phone, decoration: const InputDecoration())),
          _fieldGap(),
          _genderField(),
        ] else ...[
          Text(
            'Personal, bank, and emergency details are stored in HRMS_users.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          _labeledField('Full name', TextField(controller: _name, decoration: const InputDecoration())),
          _fieldGap(),
          _labeledField(
            'Employee code',
            TextField(
              controller: _employeeCode,
              readOnly: !_canEditOrgFields,
              decoration: const InputDecoration(),
            ),
            helperText: _canEditOrgFields ? null : 'View only. Admin/HR can edit in Employees.',
          ),
          _fieldGap(),
          _labeledField('Phone', TextField(controller: _phone, decoration: const InputDecoration())),
          _fieldGap(),
          _genderField(),
          _fieldGap(),
          _labeledField(
            'Designation',
            TextField(
              controller: _designation,
              readOnly: !_canEditOrgFields,
              decoration: const InputDecoration(),
            ),
            helperText: _canEditOrgFields ? 'Edit from master list (Settings → Designations).' : 'View only. Admin/HR can edit in Employees.',
          ),
          if (u.companyId != null && u.companyId!.isNotEmpty) ...[
            _fieldGap(),
            _labeledField(
              'Department',
              DropdownButtonFormField<String?>(
                value: _departmentId,
                decoration: const InputDecoration(),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  ..._departments.map(
                    (d) => DropdownMenuItem<String?>(
                      value: d['id']?.toString(),
                      child: Text(_str(d['name'])),
                    ),
                  ),
                ],
                onChanged: _canEditOrgFields ? (v) => setState(() => _departmentId = v) : null,
              ),
              helperText: _canEditOrgFields ? null : 'View only. Admin/HR can edit in Employees.',
            ),
            _fieldGap(),
            _labeledField(
              'Division',
              DropdownButtonFormField<String?>(
                value: _divisionId,
                decoration: const InputDecoration(),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  ..._divisions.map(
                    (d) => DropdownMenuItem<String?>(
                      value: d['id']?.toString(),
                      child: Text(_str(d['name'])),
                    ),
                  ),
                ],
                onChanged: _canEditOrgFields ? (v) => setState(() => _divisionId = v) : null,
              ),
              helperText: _canEditOrgFields ? null : 'View only. Admin/HR can edit in Employees.',
            ),
            _fieldGap(),
            _labeledField(
              'Shift',
              DropdownButtonFormField<String?>(
                value: _shiftId,
                decoration: const InputDecoration(),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  ..._shifts.map(
                    (s) => DropdownMenuItem<String?>(
                      value: s['id']?.toString(),
                      child: Text(_str(s['name'])),
                    ),
                  ),
                ],
                onChanged: _canEditOrgFields ? (v) => setState(() => _shiftId = v) : null,
              ),
              helperText: _canEditOrgFields ? null : 'View only. Admin/HR can edit in Employees.',
            ),
          ],
          _fieldGap(),
          _labeledField('Aadhaar', TextField(controller: _aadhaar, decoration: const InputDecoration())),
          _fieldGap(),
          _labeledField('PAN', TextField(controller: _pan, decoration: const InputDecoration())),
          _fieldGap(),
          _labeledField(
            'UAN number',
            TextField(
              controller: _uan,
              readOnly: !_canEditEmployment,
              decoration: const InputDecoration(),
            ),
            helperText: _canEditEmployment ? null : 'View only. Admin/HR can edit in Employees.',
          ),
          _fieldGap(),
          _labeledField(
            'PF number',
            TextField(
              controller: _pf,
              readOnly: !_canEditOrgFields,
              decoration: const InputDecoration(),
            ),
            helperText: _canEditOrgFields ? null : 'View only. Admin/HR can edit in Employees.',
          ),
          _fieldGap(),
          _labeledField(
            'ESIC number',
            TextField(
              controller: _esic,
              readOnly: !_canEditOrgFields,
              decoration: const InputDecoration(),
            ),
            helperText: _canEditOrgFields ? null : 'View only. Admin/HR can edit in Employees.',
          ),
          _fieldGap(),
          _labeledField(
            'Date of birth',
            TextField(
              controller: _dob,
              readOnly: true,
              decoration: const InputDecoration(hintText: 'DD-MM-YYYY', suffixIcon: Icon(Icons.calendar_month_outlined)),
              onTap: () => _pickDateInto(_dob),
            ),
          ),
          _fieldGap(),
          _labeledField(
            'Date of joining',
            TextField(
              controller: _doj,
              readOnly: true,
              decoration: const InputDecoration(hintText: 'DD-MM-YYYY', suffixIcon: Icon(Icons.calendar_month_outlined)),
              onTap: !_canEditOrgFields ? null : () => _pickDateInto(_doj),
            ),
            helperText: _canEditOrgFields ? null : 'View only. Admin/HR can edit in Employees.',
          ),
          _fieldGap(),
          _labeledField(
            'CTC (monthly)',
            TextField(
              controller: _ctc,
              readOnly: !_canEditEmployment,
              decoration: const InputDecoration(),
              keyboardType: TextInputType.number,
            ),
            helperText: _canEditEmployment ? null : 'View only. Admin/HR can edit in Employees.',
          ),
          _fieldGap(),
          _labeledField(
            'Employment status',
            DropdownButtonFormField<String>(
              value: _employmentStatus,
              decoration: const InputDecoration(),
              items: const [
                DropdownMenuItem(value: 'preboarding', child: Text('Preboarding')),
                DropdownMenuItem(value: 'current', child: Text('Current')),
                DropdownMenuItem(value: 'past', child: Text('Past')),
              ],
              onChanged: _canEditEmployment ? (v) => setState(() => _employmentStatus = v ?? 'preboarding') : null,
            ),
            helperText: _canEditEmployment ? null : 'Only Admin/HR can change status.',
          ),
          if (_isEmployee || !_canEditEmployment)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _isEmployee
                    ? 'Designation, department, division, shift, UAN, PF, and ESIC are view only. Only Admin/HR can change status and CTC.'
                    : 'Only Admin/HR can change status, UAN, and CTC.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ),
          ExpansionTile(
            title: const Text('Current address'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    _labeledField('Address line 1', TextField(controller: _cur1, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Address line 2', TextField(controller: _cur2, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('City', TextField(controller: _curCity, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('State', TextField(controller: _curState, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Country', TextField(controller: _curCountry, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Postal code', TextField(controller: _curPostal, decoration: const InputDecoration())),
                  ],
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('Permanent address'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    _labeledField('Address line 1', TextField(controller: _perm1, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Address line 2', TextField(controller: _perm2, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('City', TextField(controller: _permCity, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('State', TextField(controller: _permState, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Country', TextField(controller: _permCountry, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Postal code', TextField(controller: _permPostal, decoration: const InputDecoration())),
                  ],
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('Bank'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    _labeledField('Bank name', TextField(controller: _bankName, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Account number', TextField(controller: _bankAcct, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('IFSC', TextField(controller: _bankIfsc, decoration: const InputDecoration())),
                  ],
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('Emergency contact'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    _labeledField('Name', TextField(controller: _emName, decoration: const InputDecoration())),
                    _fieldGap(),
                    _labeledField('Phone', TextField(controller: _emPhone, decoration: const InputDecoration())),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (auth != 'google')
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              subtitle: const Text('Update your password.'),
              onTap: () => context.push('/profile/change-password'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    if (u == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_isSuper) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: [
            if (!_loading && _profile != null)
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
              ),
          ],
        ),
        drawer: AppDrawer(app: widget.app),
        body: _profileFormBody(),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: [
            if (!_loading && _profile != null)
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Profile'),
              Tab(text: 'My Pay'),
              Tab(text: 'Documents'),
            ],
          ),
        ),
        drawer: AppDrawer(app: widget.app),
        body: TabBarView(
          children: [
            _profileFormBody(),
            ProfilePayTab(app: widget.app),
            ProfileDocumentsTab(app: widget.app),
          ],
        ),
      ),
    );
  }
}
