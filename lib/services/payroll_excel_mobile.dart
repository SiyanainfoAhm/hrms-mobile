// Ported from hrms-web `payrollExcelExport.ts` + XLSX export for mobile share/download.

import 'dart:typed_data';

import 'package:excel/excel.dart';

const payrollExcelHeader = <String>[
  'EmployeeName',
  'AccountNumber',
  'BankName',
  'IFSC',
  'PayDays',
  'Gross',
  'Net',
  'PF',
  'PFEmployer',
  'ESIC',
  'ESICEmployer',
  'PT',
  'Bonus',
  'Incentive',
  'Reimbursement',
  'TDS',
  'Deductions',
  'TakeHome',
  'CTC',
];

int _n(dynamic v) {
  final x = num.tryParse('$v');
  return x != null && x.isFinite ? x.round() : 0;
}

double roundPayDaysToHalfStep(dynamic raw) {
  final x = (raw as num?)?.toDouble() ?? double.nan;
  if (!x.isFinite) return 0;
  return (x * 2).round() / 2.0;
}

double normalizePayDaysHalfStepAndClamp(dynamic raw, int max) {
  if (!max.isFinite || max < 0) return roundPayDaysToHalfStep(raw);
  final half = roundPayDaysToHalfStep(raw);
  if (half < 0) return 0;
  return half > max ? max.toDouble() : half;
}

Map<String, Object> buildPayrollExcelRow(Map<String, dynamic> p, String userName) {
  final accountNum = p['bank_account_number'] != null ? '${p['bank_account_number']}' : '';
  final bankName = p['bank_name'] != null ? '${p['bank_name']}' : '';
  final ifsc = p['bank_ifsc'] != null ? '${p['bank_ifsc']}' : '';
  final takeHome = _n(p['net_pay']);
  final tds = _n(p['tds']);
  final inc = _n(p['incentive']);
  final bonus = _n(p['pr_bonus']);
  final reimb = _n(p['reimbursement']);
  final net = (takeHome + tds - inc - bonus - reimb).round();
  return {
    'EmployeeName': userName,
    'AccountNumber': accountNum,
    'BankName': bankName,
    'IFSC': ifsc,
    'PayDays': roundPayDaysToHalfStep(p['pay_days']),
    'Gross': _n(p['gross_pay']),
    'Net': net,
    'PF': _n(p['pf_employee']),
    'PFEmployer': _n(p['pf_employer']),
    'ESIC': _n(p['esic_employee']),
    'ESICEmployer': _n(p['esic_employer']),
    'PT': _n(p['professional_tax']),
    'Bonus': bonus,
    'Incentive': inc,
    'Reimbursement': reimb,
    'TDS': tds,
    'Deductions': _n(p['deductions']),
    'TakeHome': takeHome,
    'CTC': _n(p['ctc']),
  };
}

CellValue _cell(Object v) {
  if (v is String) return TextCellValue(v);
  if (v is int) return IntCellValue(v);
  if (v is double) {
    if (v == v.roundToDouble()) return IntCellValue(v.round());
    return TextCellValue(v.toString());
  }
  return TextCellValue('$v');
}

/// One sheet "Payroll" matching web column order.
Uint8List? buildPayrollExcelBytes(List<Map<String, dynamic>> payslips, Map<String, String> userNameById) {
  if (payslips.isEmpty) return null;
  final excel = Excel.createExcel();
  excel.delete('Sheet1');
  final sheet = excel['Payroll'];

  for (var c = 0; c < payrollExcelHeader.length; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value = TextCellValue(payrollExcelHeader[c]);
  }

  for (var r = 0; r < payslips.length; r++) {
    final p = payslips[r];
    final uid = '${p['employee_user_id'] ?? ''}';
    final name = userNameById[uid] ?? '';
    final row = buildPayrollExcelRow(p, name);
    for (var c = 0; c < payrollExcelHeader.length; c++) {
      final key = payrollExcelHeader[c];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = _cell(row[key]!);
    }
  }

  final out = excel.encode();
  if (out == null) return null;
  return Uint8List.fromList(out);
}
