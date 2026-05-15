import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../ui/formatters.dart';
import '../ui/payslip_html.dart';

/// Inputs required to render a payslip PDF (matches [buildPayslipHtml]).
class PayslipPdfInput {
  const PayslipPdfInput({
    required this.slip,
    required this.company,
    required this.user,
    required this.selectedMonth,
    required this.selectedYear,
    this.privatePayrollConfig,
  });

  final Map<String, dynamic> slip;
  final Map<String, dynamic>? company;
  final Map<String, dynamic>? user;
  final String selectedMonth;
  final String selectedYear;
  final Map<String, dynamic>? privatePayrollConfig;

  String get html => buildPayslipHtml(
        slip: slip,
        company: company,
        user: user,
        selectedMonth: selectedMonth,
        selectedYear: selectedYear,
        privatePayrollConfig: privatePayrollConfig,
      );
}

/// Mobile-safe payslip PDF generation (real `application/pdf` bytes).
///
/// Native [pdf] layout aligned with [buildPayslipHtml] (web). Uses
/// [PdfGoogleFonts.notoSans*] for rupee / punctuation and loads [company.logo_url]
/// when reachable.
class PayslipPdfService {
  PayslipPdfService._();

  /// Same printable width as web `.payslip-print-area` (`max-width: 190mm`).
  static const double _payslipContentMm = 190;

  /// Content width in PDF points (centered on A4 like web `margin: 0 auto`).
  static double payslipContentWidthPt({
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    double horizontalMarginPt = 28,
  }) {
    final target = _payslipContentMm * PdfPageFormat.mm;
    final available = pageFormat.width - 2 * horizontalMarginPt;
    return target < available ? target : available;
  }

  static pw.Widget _centeredPayslipCard(pw.Widget card) {
    final w = payslipContentWidthPt();
    return pw.Align(
      alignment: pw.Alignment.topCenter,
      child: pw.SizedBox(width: w, child: card),
    );
  }

  static const _cellPad = pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5);
  static const _hdrPad = pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  static const _innerGridBorder = pw.TableBorder(
    horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.8),
    verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.8),
  );

  /// Two rows × two columns; table borders meet cleanly (no gap in vertical divider).
  static pw.Table _privateDetailsGrid({
    required List<pw.Widget> leftRow1,
    required List<pw.Widget> rightRow1,
    required List<pw.Widget> leftRow2,
    required List<pw.Widget> rightRow2,
  }) {
    pw.Widget cell(List<pw.Widget> lines) => pw.Padding(
          padding: _cellPad,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: lines,
          ),
        );
    return pw.Table(
      border: _innerGridBorder,
      columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
      children: [
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.full,
          children: [cell(leftRow1), cell(rightRow1)],
        ),
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.full,
          children: [cell(leftRow2), cell(rightRow2)],
        ),
      ],
    );
  }

  /// Safe file stem: `payslip_<employeeName>_<month>_<year>` (no extension).
  static String buildPdfBaseName({
    required Map<String, dynamic>? user,
    required String selectedMonth,
    required String selectedYear,
  }) {
    final raw = (user?['name'] ?? 'Employee').toString().trim();
    final safe = raw.isEmpty
        ? 'Employee'
        : raw
            .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
            .replaceAll(RegExp(r'\s+'), '_')
            .replaceAll(RegExp(r'_+'), '_');
    final mi = (int.tryParse(selectedMonth) ?? 1).clamp(1, 12);
    final monthLabel = UiFormatters.monthShort(mi);
    return 'payslip_${safe}_${monthLabel}_$selectedYear';
  }

  static bool _isValidPdf(Uint8List bytes) =>
      bytes.length > 8 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;

  static Future<pw.MemoryImage?> _tryLoadLogo(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || (u.scheme != 'https' && u.scheme != 'http')) return null;
    try {
      final resp = await http.get(u).timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300 || resp.bodyBytes.isEmpty) return null;
      return pw.MemoryImage(resp.bodyBytes);
    } catch (e) {
      if (kDebugMode) debugPrint('PayslipPdfService: logo fetch failed: $e');
      return null;
    }
  }

  static Future<pw.ThemeData> _payslipTheme() async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    return pw.ThemeData.withFont(base: base, bold: bold);
  }

  /// Generates PDF bytes (native layout aligned with web [buildPayslipHtml]).
  static Future<Uint8List> generatePayslipPdfBytes(PayslipPdfInput input) async {
    final native = await _generateNativePdfBytes(input);
    if (!_isValidPdf(native)) {
      throw StateError('PDF builder produced invalid output');
    }
    if (kDebugMode) {
      debugPrint('PayslipPdfService: payslip PDF (${native.lengthInBytes} bytes)');
    }
    return native;
  }

  /// Saves PDF via [FileSaver] when the native plugin is linked.
  ///
  /// If [FileSaver] is not registered (e.g. app was hot-reloaded after adding
  /// the plugin), falls back to [Printing.sharePdf] so the user still gets a
  /// real PDF (pick Files / Drive / etc. from the sheet).
  static Future<({bool usedShareFallback, String? savedPath})> downloadPayslipPdf({
    required Uint8List bytes,
    required String baseFileName,
  }) async {
    final filename = '$baseFileName.pdf';
    try {
      final path = await FileSaver.instance.saveFile(
        name: baseFileName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      return (usedShareFallback: false, savedPath: path);
    } on MissingPluginException catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'PayslipPdfService: file_saver not registered ($e). '
          'Do a full restart (stop + flutter run), not hot reload. Using share fallback.\n$st',
        );
      }
      final ok = await Printing.sharePdf(bytes: bytes, filename: filename);
      if (!ok) {
        throw StateError(
          'Could not save PDF (file_saver missing — restart the app) and share sheet did not open.',
        );
      }
      return (usedShareFallback: true, savedPath: null);
    }
  }

  /// Opens the platform share sheet with a real `.pdf` attachment.
  static Future<bool> sharePayslipPdf({
    required Uint8List bytes,
    required String filename,
  }) {
    return Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// In-app PDF preview dialog.
  static Future<void> previewPayslipPdf({
    required BuildContext context,
    required Uint8List bytes,
    required String pdfFileName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 520,
            height: 640,
            child: PdfPreview(
              build: (_) async => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              pdfFileName: pdfFileName,
              allowPrinting: true,
              allowSharing: true,
            ),
          ),
        );
      },
    );
  }

  // --- native PDF (data-driven, mirrors payslip_html.dart logic) ---

  static num _n(dynamic v) => num.tryParse((v ?? 0).toString()) ?? 0;

  static Map<String, dynamic>? _asStrMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  static (String mode, String effYm) _earningsCfg(Map<String, dynamic>? raw) {
    if (raw == null) return ('classic', '');
    final m = raw['payslipEarningsMode']?.toString();
    final mode = m == 'basic_hra_advance_special' ? 'basic_hra_advance_special' : 'classic';
    final ym = raw['payslipEarningsEffectiveFromYm']?.toString().trim() ?? '';
    final eff = RegExp(r'^\d{4}-\d{2}$').hasMatch(ym) ? ym : '';
    return (mode, eff);
  }

  static num _gnum(Map<String, dynamic> gov, String key) => _n(gov[key]);

  static List<(String, num)> _govEarningPairs(Map<String, dynamic> gov) {
    return [
      ('Basic', _gnum(gov, 'basic_paid')),
      ('SP. Pay', _gnum(gov, 'sp_pay_paid')),
      ('DA', _gnum(gov, 'da_paid')),
      ('Transport', _gnum(gov, 'transport_paid')),
      ('HRA', _gnum(gov, 'hra_paid')),
      ('Medical', _gnum(gov, 'medical_paid')),
      ('Extra Work Allowance', _gnum(gov, 'extra_work_allowance_paid')),
      ('Night Allowance', _gnum(gov, 'night_allowance_paid')),
      ('Uniform Allowance', _gnum(gov, 'uniform_allowance_paid')),
      ('Education Allowance', _gnum(gov, 'education_allowance_paid')),
      ('DA Arrears', _gnum(gov, 'da_arrears_paid')),
      ('Transport Arrears', _gnum(gov, 'transport_arrears_paid')),
      ('Encashment', _gnum(gov, 'encashment_paid')),
      ('Encashment DA', _gnum(gov, 'encashment_da_paid')),
    ];
  }

  static List<(String, num)> _govDeductionPairs(Map<String, dynamic> gov) {
    num incomeTaxOrTds = _gnum(gov, 'income_tax_amount');
    if (incomeTaxOrTds == 0) incomeTaxOrTds = _gnum(gov, 'tds');
    if (incomeTaxOrTds == 0) incomeTaxOrTds = _gnum(gov, 'tds_amount');
    num pt = _gnum(gov, 'pt_amount');
    if (pt == 0) pt = _gnum(gov, 'professional_tax');
    num cpf = _gnum(gov, 'cpf_amount');
    if (cpf == 0) cpf = _gnum(gov, 'pf_employee');
    return [
      ('TDS / Income Tax', incomeTaxOrTds),
      ('P.Tax', pt),
      ('LIC', _gnum(gov, 'lic_amount')),
      ('CPF', cpf),
      ('DA CPF', _gnum(gov, 'da_cpf_amount')),
      ('VPF', _gnum(gov, 'vpf_amount')),
      ('PF Loan', _gnum(gov, 'pf_loan_amount')),
      ('Post Office', _gnum(gov, 'post_office_amount')),
      ('Credit Society', _gnum(gov, 'credit_society_amount')),
      ('Std Licence fee', _gnum(gov, 'std_licence_fee_amount')),
      ('Electricity', _gnum(gov, 'electricity_amount')),
      ('Water', _gnum(gov, 'water_amount')),
      ('Mess', _gnum(gov, 'mess_amount')),
      ('Horticulture', _gnum(gov, 'horticulture_amount')),
      ('Welfare', _gnum(gov, 'welfare_amount')),
      ('Veh Charge', _gnum(gov, 'veh_charge_amount')),
      ('Other', _gnum(gov, 'other_deduction_amount')),
    ];
  }

  static Future<Uint8List> _generateNativePdfBytes(PayslipPdfInput input) async {
    final theme = await _payslipTheme();
    final logoUrl = (input.company?['logo_url'] ?? '').toString().trim();
    final logo = await _tryLoadLogo(logoUrl);

    final gov = _asStrMap(input.slip['government_monthly']);
    final doc = pw.Document(theme: theme);
    const pageMargin = pw.EdgeInsets.fromLTRB(12, 8, 12, 8);
    if (gov != null && gov.isNotEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pageMargin,
          build: (ctx) => _centeredPayslipCard(_governmentPayslipCard(input, gov, logo)),
        ),
      );
    } else {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pageMargin,
          build: (ctx) => _centeredPayslipCard(_privatePayslipCard(input, logo)),
        ),
      );
    }
    return doc.save();
  }

  static pw.TextStyle _t(double size, {bool bold = false}) => pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

  static pw.Widget _finCell(String text, {bool bold = false, bool right = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Align(
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  static String _emDash(String v) => v.trim().isEmpty ? '—' : v.trim();

  static pw.Widget _privateHdrLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(fontSize: 10, height: 1.3),
          children: [
            pw.TextSpan(text: '$label: ', style: pw.TextStyle(color: PdfColors.grey700)),
            pw.TextSpan(text: value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
          ],
        ),
      ),
    );
  }

  static pw.Table _privateFinancialSevenCol({
    required List<(String, num)> earningsRows,
    required String Function(num) fmt,
    required num professionalTax,
    required num pfEmployee,
    required num esicEmployee,
    required num incentive,
    required num prBonus,
    required num reimbursement,
    required num grossPay,
    required num totalEmployeeDeductions,
    required num totalPerf,
    required int takeHome,
  }) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _finCell('Earnings', bold: true),
          _finCell('Actual', bold: true, right: true),
          _finCell('Paid', bold: true, right: true),
          _finCell('Employee Deductions', bold: true),
          _finCell('Amount', bold: true, right: true),
          _finCell('Performance Earnings', bold: true),
          _finCell('Amount', bold: true, right: true),
        ],
      ),
    ];

    for (var idx = 0; idx < earningsRows.length; idx++) {
      final label = earningsRows[idx].$1;
      final val = earningsRows[idx].$2;
      var dLabel = '';
      var dAmt = '';
      var pLabel = '';
      var pAmt = '';
      if (idx == 0) {
        dLabel = 'Professional Tax';
        dAmt = fmt(professionalTax);
        pLabel = 'Bonus';
        pAmt = fmt(prBonus);
      } else if (idx == 1) {
        dLabel = 'PF';
        dAmt = fmt(pfEmployee);
        pLabel = 'Incentive';
        pAmt = fmt(incentive);
      } else if (idx == 2) {
        dLabel = 'ESIC';
        dAmt = fmt(esicEmployee);
        pLabel = 'Reimbursement';
        pAmt = fmt(reimbursement);
      }
      rows.add(
        pw.TableRow(
          children: [
            _finCell(label),
            _finCell(fmt(val), right: true),
            _finCell(fmt(val), right: true),
            _finCell(dLabel),
            _finCell(dAmt, right: true),
            _finCell(pLabel),
            _finCell(pAmt, right: true),
          ],
        ),
      );
    }

    rows.addAll([
      pw.TableRow(
        children: [
          _finCell('GROSS', bold: true),
          _finCell(fmt(grossPay), right: true, bold: true),
          _finCell(fmt(grossPay), right: true, bold: true),
          _finCell('Total Deduction', bold: true),
          _finCell(fmt(totalEmployeeDeductions), right: true, bold: true),
          _finCell('Total', bold: true),
          _finCell(fmt(totalPerf), right: true, bold: true),
        ],
      ),
      pw.TableRow(
        children: [
          _finCell('Net Payable Salary', bold: true),
          _finCell(fmt(takeHome), right: true, bold: true),
          _finCell(fmt(takeHome), right: true, bold: true),
          _finCell(''),
          _finCell('', right: true),
          _finCell(''),
          _finCell('', right: true),
        ],
      ),
      pw.TableRow(
        children: [
          _finCell('Net Pay', bold: true),
          _finCell('', right: true),
          _finCell('', right: true),
          _finCell('', right: true),
          _finCell('', right: true),
          _finCell('', right: true),
          _finCell(fmt(takeHome), right: true, bold: true),
        ],
      ),
      pw.TableRow(children: List.generate(7, (_) => _finCell(''))),
      pw.TableRow(children: List.generate(7, (_) => _finCell(''))),
    ]);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.0),
        1: pw.FlexColumnWidth(1.15),
        2: pw.FlexColumnWidth(1.15),
        3: pw.FlexColumnWidth(2.1),
        4: pw.FlexColumnWidth(1.15),
        5: pw.FlexColumnWidth(2.1),
        6: pw.FlexColumnWidth(1.15),
      },
      children: rows,
    );
  }

  static pw.Widget _privatePayslipCard(PayslipPdfInput input, pw.MemoryImage? logo) {
    final slip = input.slip;
    final company = input.company;
    final user = input.user;
    String fmt(num x) => UiFormatters.indianNumber(x.round());

    final monthIdx = (int.tryParse(input.selectedMonth) ?? 1).clamp(1, 12);
    final monthShort = UiFormatters.monthShort(monthIdx);
    final year = input.selectedYear;

    final salaryDate = UiFormatters.indianDateLong(slip['generated_at']);
    final dojFormatted = UiFormatters.indianDateShort(user?['date_of_joining']);

    final periodStart = slip['period_start'];
    final periodEnd = slip['period_end'];
    final periodStartDt = DateTime.tryParse((periodStart ?? '').toString());
    final periodEndDt = DateTime.tryParse((periodEnd ?? '').toString());
    final totalDays = (periodStartDt != null && periodEndDt != null)
        ? (DateTime(periodEndDt.year, periodEndDt.month, periodEndDt.day)
                .difference(DateTime(periodStartDt.year, periodStartDt.month, periodStartDt.day))
                .inDays +
            1)
        : 0;
    final payDays = _n(slip['pay_days']);
    final unpaidLeaves = totalDays > 0 ? (totalDays - payDays).clamp(0, 366) : 0;

    final companyName = (company?['name'] ?? 'Company').toString();
    final companyAddr = (company?['address'] ?? '').toString();

    final empName = (user?['name'] ?? '').toString();
    final designation = (user?['designation'] ?? '').toString();
    final department = (user?['department_name'] ?? '').toString();
    final aadhaar = (user?['aadhaar'] ?? '').toString();
    final pan = (user?['pan'] ?? '').toString();
    final esicNo = (user?['esic_number'] ?? '').toString();
    final uanNo = (user?['uan_number'] ?? '').toString();
    final pfNo = (user?['pf_number'] ?? '').toString();

    final basic = _n(slip['basic']);
    final hra = _n(slip['hra']);
    final medical = _n(slip['medical']);
    final trans = _n(slip['trans']);
    final lta = _n(slip['lta']);
    final personal = _n(slip['personal']);
    final grossPay = _n(slip['gross_pay']);
    final professionalTax = _n(slip['professional_tax']);
    final pfEmployee = _n(slip['pf_employee']);
    final esicEmployee = _n(slip['esic_employee']);
    final tds = _n(slip['tds']);
    final incentive = _n(slip['incentive']);
    final prBonus = _n(slip['pr_bonus']);
    final reimbursement = _n(slip['reimbursement']);
    final totalPerf = incentive + prBonus + reimbursement;
    final totalEmployeeDeductions = professionalTax + pfEmployee + esicEmployee + tds;
    final takeHome = (grossPay - totalEmployeeDeductions + totalPerf).round();

    final cfg = _asStrMap(input.privatePayrollConfig);
    final (mode, effYm) = _earningsCfg(cfg);
    final pm = payslipPeriodMonthKey(slip);
    final useCompactHeads =
        mode == 'basic_hra_advance_special' && RegExp(r'^\d{4}-\d{2}$').hasMatch(effYm) && pm.isNotEmpty && pm.compareTo(effYm) >= 0;

    final earningsRows = useCompactHeads
        ? <(String, num)>[
            ('Basic + DA', basic),
            ('HRA', hra),
            ('Advance bonus', medical),
            ('Special allowance', personal),
          ]
        : <(String, num)>[
            ('Basic', basic),
            ('HRA', hra),
            ('Medical', medical),
            ('Transport', trans),
            ('LTA', lta),
            ('Personal', personal),
          ];

    final financial = _privateFinancialSevenCol(
      earningsRows: earningsRows,
      fmt: fmt,
      professionalTax: professionalTax,
      pfEmployee: pfEmployee,
      esicEmployee: esicEmployee,
      incentive: incentive,
      prBonus: prBonus,
      reimbursement: reimbursement,
      grossPay: grossPay,
      totalEmployeeDeductions: totalEmployeeDeductions,
      totalPerf: totalPerf,
      takeHome: takeHome,
    );

    final w = payslipContentWidthPt();
    return pw.Container(
      width: w,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: _hdrPad,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Image(logo, height: 48, fit: pw.BoxFit.contain),
                  pw.SizedBox(height: 6),
                ],
                pw.Text(
                  companyName,
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                if (companyAddr.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Text(
                      companyAddr,
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'SALARY SLIP',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  '$monthShort $year',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
          _privateDetailsGrid(
            leftRow1: [
              _privateHdrLine('Employee Name', _emDash(empName)),
              _privateHdrLine('Designation', _emDash(designation)),
              _privateHdrLine('Department', _emDash(department)),
              _privateHdrLine('Salary Date', salaryDate),
            ],
            rightRow1: [
              _privateHdrLine('Joining Date', _emDash(dojFormatted)),
              _privateHdrLine('Aadhaar', _emDash(aadhaar)),
              _privateHdrLine('PAN', _emDash(pan)),
            ],
            leftRow2: [
              _privateHdrLine('Total Paid Days', fmt(payDays)),
              _privateHdrLine('Unpaid Leaves', fmt(unpaidLeaves)),
            ],
            rightRow2: [
              _privateHdrLine('ESIC number', _emDash(esicNo)),
              _privateHdrLine('UAN number', _emDash(uanNo)),
              _privateHdrLine('PF number', _emDash(pfNo)),
            ],
          ),
          financial,
        ],
      ),
    );
  }

  static pw.Widget _governmentPayslipCard(PayslipPdfInput input, Map<String, dynamic> gov, pw.MemoryImage? logo) {
    final slip = input.slip;
    final company = input.company;
    final user = input.user;
    String fmt(num x) => UiFormatters.indianNumber(x.round());

    final companyName = (company?['name'] ?? '').toString();
    final companyAddr = (company?['address'] ?? '').toString();

    final periodStartStr = (slip['period_start'] ?? '').toString();
    String title = 'PAY SLIP';
    if (periodStartStr.length >= 7) {
      final y = periodStartStr.substring(0, 4);
      final mi = int.tryParse(periodStartStr.substring(5, 7)) ?? 1;
      final m = mi.clamp(1, 12);
      const upper = [
        'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
      ];
      title = 'PAY SLIP FOR ${upper[m - 1]} $y';
    }

    num grossBasic = _gnum(gov, 'basic_actual');
    if (grossBasic == 0) grossBasic = _gnum(gov, 'basic_paid');
    final dim = _gnum(gov, 'days_in_month');
    num paidDays = _gnum(gov, 'paid_days');
    if (paidDays == 0) paidDays = _n(slip['pay_days']);
    final periodEndStr = (slip['period_end'] ?? '').toString();
    final psDt = DateTime.tryParse(periodStartStr);
    final peDt = DateTime.tryParse(periodEndStr);
    final totalDays = (psDt != null && peDt != null)
        ? (DateTime(peDt.year, peDt.month, peDt.day).difference(DateTime(psDt.year, psDt.month, psDt.day)).inDays + 1)
        : 0;
    final unpaid = totalDays > 0 ? (totalDays - paidDays).clamp(0, 366) : 0;
    final netRounded = (_n(slip['net_pay']) != 0 ? _n(slip['net_pay']) : _gnum(gov, 'net_salary')).round();

    final totalEarn = _gnum(gov, 'total_earnings');
    final totalDed = _gnum(gov, 'total_deductions');
    final salaryDate = UiFormatters.indianDateLong(slip['generated_at']);

    final left = _govEarningPairs(gov);
    final right = _govDeductionPairs(gov);
    final len = left.length > right.length ? left.length : right.length;
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Earnings', style: _t(8, bold: true))),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Amt', style: _t(8, bold: true))),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Deductions', style: _t(8, bold: true))),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Amt', style: _t(8, bold: true))),
          ),
        ],
      ),
    ];

    for (var i = 0; i < len; i++) {
      final L = i < left.length ? left[i] : ('', 0);
      final R = i < right.length ? right[i] : ('', 0);
      tableRows.add(
        pw.TableRow(
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(L.$1.isEmpty ? '' : L.$1, style: _t(8))),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(L.$1.isEmpty ? '' : fmt(L.$2), style: _t(8)),
              ),
            ),
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(R.$1.isEmpty ? '' : R.$1, style: _t(8))),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(R.$1.isEmpty ? '' : fmt(R.$2), style: _t(8)),
              ),
            ),
          ],
        ),
      );
    }

    tableRows.addAll([
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('TOTAL EARNINGS', style: _t(8, bold: true))),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(fmt(totalEarn), style: _t(8, bold: true))),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('TOTAL DEDUCTIONS', style: _t(8, bold: true))),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(fmt(totalDed), style: _t(8, bold: true))),
          ),
        ],
      ),
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('NET SALARY', style: _t(9, bold: true)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(fmt(netRounded), style: _t(9, bold: true)),
            ),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
        ],
      ),
    ]);

    final empCode = (user?['employee_code'] ?? '').toString();
    final empName = (user?['name'] ?? '').toString();
    final designation = (user?['designation'] ?? '').toString();
    final dept = (user?['department_name'] ?? '').toString();

    final w = payslipContentWidthPt();
    final inner = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.Image(logo, height: 52, fit: pw.BoxFit.contain),
                pw.SizedBox(height: 8),
              ],
              if (companyAddr.isNotEmpty)
                pw.Text(companyAddr, style: _t(8), textAlign: pw.TextAlign.center),
              if (companyName.isNotEmpty)
                pw.Text(companyName, style: _t(11, bold: true), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 8),
              pw.Text(title, style: _t(13, bold: true), textAlign: pw.TextAlign.center),
            ],
          ),
        ),
        pw.Divider(color: PdfColors.black, thickness: 1),
        pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _privateHdrLine('Employee ID', _emDash(empCode)),
                    _privateHdrLine('Employee Name', _emDash(empName)),
                    _privateHdrLine('Designation', _emDash(designation)),
                    _privateHdrLine('Department', _emDash(dept)),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _privateHdrLine('Salary date', salaryDate),
                    _privateHdrLine('Paid days', fmt(paidDays)),
                    _privateHdrLine('Unpaid leave days', fmt(unpaid)),
                    if (dim > 0) _privateHdrLine('Days in month', fmt(dim)),
                    _privateHdrLine('Gross basic', fmt(grossBasic)),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
          columnWidths: {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(1),
          },
          children: tableRows,
        ),
      ],
    );

    return pw.Container(
      width: w,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: inner,
    );
  }
}
