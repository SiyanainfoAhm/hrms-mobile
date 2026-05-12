import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors web `ensureEmployeeMirrorForUser` (`src/lib/ensureEmployeeMirror.ts`).

({String firstName, String? lastName}) _splitName(String? raw, String? email) {
  final fbRaw = email?.split('@').first ?? 'Employee';
  final fallbackFirst = fbRaw.length > 100 ? fbRaw.substring(0, 100) : fbRaw;
  final parts = (raw ?? '').trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  final first = (parts.isNotEmpty ? parts.first : fallbackFirst);
  final firstName = first.length > 100 ? first.substring(0, 100) : first;
  String? lastName;
  if (parts.length > 1) {
    final l = parts.skip(1).join(' ');
    lastName = l.length > 100 ? l.substring(0, 100) : l;
  }
  return (firstName: firstName, lastName: lastName);
}

Future<({bool ok, String? employeeId, String? departmentId, String? error})> ensureEmployeeMirrorForUser(
  SupabaseClient sb, {
  required String companyId,
  required String userId,
}) async {
  final existing = await sb
      .from('HRMS_employees')
      .select('id, department_id')
      .eq('company_id', companyId)
      .eq('user_id', userId)
      .maybeSingle();
  if (existing?['id'] != null) {
    return (
      ok: true,
      employeeId: existing!['id'].toString(),
      departmentId: existing['department_id']?.toString(),
      error: null,
    );
  }

  final u = await sb
      .from('HRMS_users')
      .select(
        'id, company_id, email, name, employee_code, phone, date_of_joining, employment_status, '
        'department_id, division_id, shift_id, designation_id, emergency_contact_name, emergency_contact_phone, '
        'bank_account_number, bank_ifsc',
      )
      .eq('id', userId)
      .maybeSingle();

  if (u == null || (u['company_id']?.toString() ?? '') != companyId) {
    return (ok: false, employeeId: null, departmentId: null, error: 'User not found in this company');
  }

  final email = (u['email'] ?? '').toString().trim();
  if (email.isEmpty) {
    return (ok: false, employeeId: null, departmentId: null, error: 'User email is required to create employee mirror record');
  }

  final names = _splitName(u['name']?.toString(), email);
  final empStatus = (u['employment_status'] ?? '').toString();
  final isActive = empStatus != 'past';

  final payload = <String, dynamic>{
    'user_id': userId,
    'company_id': companyId,
    'employee_code': () {
      final c = u['employee_code']?.toString().trim();
      return (c != null && c.isNotEmpty) ? c : null;
    }(),
    'first_name': names.firstName,
    'last_name': names.lastName,
    'email': email,
    'phone': () {
      final p = u['phone']?.toString().trim();
      return (p != null && p.isNotEmpty) ? p : null;
    }(),
    'date_of_joining': u['date_of_joining'],
    'emergency_contact_name': u['emergency_contact_name'],
    'emergency_contact_phone': u['emergency_contact_phone'],
    'bank_account_number': u['bank_account_number'],
    'bank_ifsc': u['bank_ifsc'],
    'is_active': isActive,
    'designation_id': u['designation_id'],
    'department_id': u['department_id'],
    'division_id': u['division_id'],
    'shift_id': u['shift_id'],
  };

  final ins = await sb.from('HRMS_employees').insert([payload]).select('id, department_id').maybeSingle();
  if (ins?['id'] != null) {
    return (
      ok: true,
      employeeId: ins!['id'].toString(),
      departmentId: ins['department_id']?.toString(),
      error: null,
    );
  }

  final again = await sb
      .from('HRMS_employees')
      .select('id, department_id')
      .eq('company_id', companyId)
      .eq('user_id', userId)
      .maybeSingle();
  if (again?['id'] != null) {
    return (
      ok: true,
      employeeId: again!['id'].toString(),
      departmentId: again['department_id']?.toString(),
      error: null,
    );
  }

  return (ok: false, employeeId: null, departmentId: null, error: 'Failed to create employee mirror record');
}
