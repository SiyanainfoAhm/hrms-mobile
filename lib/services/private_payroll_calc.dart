// Ported from hrms-web `payrollCalc.ts` + `payrollConfig.ts` for private payroll master
// preview and save parity with `/api/payroll/master` PATCH (private branch).

import 'dart:math' as math;

class PrivatePayrollBreakupPct {
  const PrivatePayrollBreakupPct({
    required this.basicPct,
    required this.hraPct,
    required this.medicalPct,
    required this.transPct,
    required this.ltaPct,
    required this.personalPct,
  });

  final double basicPct;
  final double hraPct;
  final double medicalPct;
  final double transPct;
  final double ltaPct;
  final double personalPct;
}

class PrivatePayrollPtSlab {
  const PrivatePayrollPtSlab({required this.minInclusive, required this.maxExclusive, required this.amount});

  final int minInclusive;
  final int? maxExclusive;
  final int amount;
}

class PrivatePayrollConfig {
  const PrivatePayrollConfig({
    required this.pfRate,
    required this.pfWageCap,
    required this.pfCap,
    required this.esicEmployeeRate,
    required this.esicEmployerRate,
    required this.esicWageCeilingInclusive,
    required this.esicApplyAboveCeilingWhenEligible,
    required this.ptMonthlyDefault,
    required this.ptMode,
    required this.ptSlabs,
    required this.breakupPct,
    required this.hraRateOnBasicDa,
    required this.hraZeroWhenPotentialHraBelow,
    required this.basicDaFloorWhenHalfGrossLow,
    required this.advanceBonusRateOnBasic,
    required this.payslipEarningsMode,
    required this.payslipEarningsEffectiveFromYm,
  });

  final double pfRate;
  final double pfWageCap;
  final double pfCap;
  final double esicEmployeeRate;
  final double esicEmployerRate;
  final int esicWageCeilingInclusive;
  final bool? esicApplyAboveCeilingWhenEligible;
  final int ptMonthlyDefault;
  final String ptMode;
  final List<PrivatePayrollPtSlab> ptSlabs;
  final PrivatePayrollBreakupPct breakupPct;
  final double hraRateOnBasicDa;
  final double hraZeroWhenPotentialHraBelow;
  final int basicDaFloorWhenHalfGrossLow;
  final double advanceBonusRateOnBasic;
  final String payslipEarningsMode;
  final String payslipEarningsEffectiveFromYm;
}

const _defaultSlabs = <PrivatePayrollPtSlab>[
  PrivatePayrollPtSlab(minInclusive: 0, maxExclusive: 6000, amount: 0),
  PrivatePayrollPtSlab(minInclusive: 6000, maxExclusive: 9000, amount: 80),
  PrivatePayrollPtSlab(minInclusive: 9000, maxExclusive: 12000, amount: 150),
  PrivatePayrollPtSlab(minInclusive: 12000, maxExclusive: null, amount: 200),
];

PrivatePayrollConfig defaultPrivatePayrollConfig() => PrivatePayrollConfig(
      pfRate: 0.12,
      pfWageCap: 15000,
      pfCap: 1800,
      esicEmployeeRate: 0.0075,
      esicEmployerRate: 0.0325,
      esicWageCeilingInclusive: 21000,
      esicApplyAboveCeilingWhenEligible: false,
      ptMonthlyDefault: 200,
      ptMode: 'slab',
      ptSlabs: _defaultSlabs,
      breakupPct: const PrivatePayrollBreakupPct(
        basicPct: 0.5,
        hraPct: 0,
        medicalPct: 0,
        transPct: 0,
        ltaPct: 0,
        personalPct: 0,
      ),
      hraRateOnBasicDa: 0.4,
      hraZeroWhenPotentialHraBelow: 6000,
      basicDaFloorWhenHalfGrossLow: 14290,
      advanceBonusRateOnBasic: 0.0833,
      payslipEarningsMode: 'classic',
      payslipEarningsEffectiveFromYm: '',
    );

double _clamp(double x, double min, double max) => x < min ? min : (x > max ? max : x);

double? _n(dynamic v) {
  final x = num.tryParse('${v ?? ''}');
  return x != null && x.isFinite ? x.toDouble() : null;
}

double? _pct(dynamic v) {
  final x = _n(v);
  if (x == null) return null;
  final y = x > 1 ? x / 100.0 : x;
  return _clamp(y, 0, 1);
}

PrivatePayrollPtSlab? _ptSlabFrom(dynamic raw) {
  if (raw is! Map) return null;
  final min = _n(raw['minInclusive'])?.round();
  final maxRaw = raw['maxExclusive'];
  final int? maxEx = maxRaw == null ? null : _n(maxRaw)?.round();
  final amt = _n(raw['amount'])?.round();
  if (min == null || min < 0) return null;
  if (maxEx != null && (maxEx <= min || maxEx < 0)) return null;
  if (amt == null || amt < 0) return null;
  return PrivatePayrollPtSlab(minInclusive: min, maxExclusive: maxEx, amount: amt);
}

PrivatePayrollConfig normalizePrivatePayrollConfig(dynamic raw) {
  final d = defaultPrivatePayrollConfig();
  final r = raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
  final bp = r['breakupPct'] is Map ? (r['breakupPct'] as Map).map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};

  final ptModeRaw = r['ptMode']?.toString();
  final ptMode = ptModeRaw == 'fixed' ? 'fixed' : 'slab';
  final slabsRaw = r['ptSlabs'];
  final ptSlabs = <PrivatePayrollPtSlab>[];
  if (slabsRaw is List) {
    for (final e in slabsRaw) {
      final s = _ptSlabFrom(e);
      if (s != null) ptSlabs.add(s);
      if (ptSlabs.length >= 20) break;
    }
  }

  final breakupPct = PrivatePayrollBreakupPct(
    basicPct: _pct(bp['basicPct']) ?? d.breakupPct.basicPct,
    hraPct: _pct(bp['hraPct']) ?? d.breakupPct.hraPct,
    medicalPct: _pct(bp['medicalPct']) ?? d.breakupPct.medicalPct,
    transPct: _pct(bp['transPct']) ?? d.breakupPct.transPct,
    ltaPct: _pct(bp['ltaPct']) ?? d.breakupPct.ltaPct,
    personalPct: _pct(bp['personalPct']) ?? d.breakupPct.personalPct,
  );

  final pem = r['payslipEarningsMode']?.toString();
  final payslipEarningsMode = pem == 'basic_hra_advance_special' ? 'basic_hra_advance_special' : 'classic';
  final ymRaw = r['payslipEarningsEffectiveFromYm']?.toString().trim() ?? '';
  final payslipEarningsEffectiveFromYm = RegExp(r'^\d{4}-\d{2}$').hasMatch(ymRaw) ? ymRaw : '';

  return PrivatePayrollConfig(
    pfRate: _clamp(_n(r['pfRate']) ?? d.pfRate, 0, 1),
    pfWageCap: math.max(0, (_n(r['pfWageCap']) ?? d.pfWageCap).roundToDouble()),
    pfCap: math.max(0, (_n(r['pfCap']) ?? d.pfCap).roundToDouble()),
    esicEmployeeRate: _clamp(_n(r['esicEmployeeRate']) ?? d.esicEmployeeRate, 0, 1),
    esicEmployerRate: _clamp(_n(r['esicEmployerRate']) ?? d.esicEmployerRate, 0, 1),
    esicWageCeilingInclusive: math.max(
      0,
      (_n(r['esicWageCeilingInclusive']) ?? _n(r['esicGrossCeilingInclusive']) ?? d.esicWageCeilingInclusive.toDouble()).round(),
    ),
    esicApplyAboveCeilingWhenEligible: r['esicApplyAboveCeilingWhenEligible'] is bool ? r['esicApplyAboveCeilingWhenEligible'] as bool : d.esicApplyAboveCeilingWhenEligible,
    ptMonthlyDefault: math.max(0, (_n(r['ptMonthlyDefault']) ?? d.ptMonthlyDefault.toDouble()).round()),
    ptMode: ptMode,
    ptSlabs: ptSlabs.isNotEmpty ? ptSlabs : d.ptSlabs,
    breakupPct: breakupPct,
    hraRateOnBasicDa: _clamp(_n(r['hraRateOnBasicDa']) ?? d.hraRateOnBasicDa, 0, 1),
    hraZeroWhenPotentialHraBelow: math.max(0, (_n(r['hraZeroWhenPotentialHraBelow']) ?? d.hraZeroWhenPotentialHraBelow).roundToDouble()),
    basicDaFloorWhenHalfGrossLow: math.max(0, (_n(r['basicDaFloorWhenHalfGrossLow']) ?? d.basicDaFloorWhenHalfGrossLow.toDouble()).round()),
    advanceBonusRateOnBasic: _clamp(_n(r['advanceBonusRateOnBasic']) ?? d.advanceBonusRateOnBasic, 0, 1),
    payslipEarningsMode: payslipEarningsMode,
    payslipEarningsEffectiveFromYm: payslipEarningsEffectiveFromYm,
  );
}

int computeProfessionalTaxMonthly(int grossMonthly, PrivatePayrollConfig cfg, [double? fallbackFixed]) {
  final g = math.max(0, grossMonthly);
  final mode = cfg.ptMode;
  final fixed = math.max(
    0,
    (fallbackFixed != null && fallbackFixed.isFinite ? fallbackFixed.round() : cfg.ptMonthlyDefault).round(),
  );
  if (mode != 'slab') return fixed;
  final slabs = cfg.ptSlabs.isNotEmpty ? cfg.ptSlabs : _defaultSlabs;
  for (final s in slabs) {
    final min = math.max(0, s.minInclusive);
    final max = s.maxExclusive;
    if (g < min) continue;
    if (max != null && g >= max) continue;
    return math.max(0, s.amount);
  }
  return fixed;
}

int computeBasicDaFromGross(int gross, PrivatePayrollConfig cfg) {
  final g = math.max(0, gross);
  final bp = cfg.breakupPct.basicPct;
  final floor = cfg.basicDaFloorWhenHalfGrossLow;
  final rawHalf = (g * bp).round();
  return (rawHalf <= floor ? floor : rawHalf).round();
}

int computeHraFromBasicDa(int basicDa, PrivatePayrollConfig cfg) {
  final base = math.max(0, basicDa);
  final rate = cfg.hraRateOnBasicDa;
  final threshold = cfg.hraZeroWhenPotentialHraBelow;
  final potential = base * rate;
  if (potential < threshold) return 0;
  return potential.round();
}

bool isWithinEsicWageCeiling(int basicDa, PrivatePayrollConfig cfg) {
  final w = math.max(0, basicDa);
  final maxInclusive = cfg.esicWageCeilingInclusive;
  return w >= 1 && w <= maxInclusive;
}

int computePfFromBasicDa(int basicDa, bool pfEligible, PrivatePayrollConfig cfg) {
  if (!pfEligible) return 0;
  final base = math.max(0, basicDa);
  final raw = base * cfg.pfRate;
  if (raw >= cfg.pfCap) return cfg.pfCap.round();
  return raw.round();
}

int computeEsicEmployee(int esicWageBase, bool esicEligible, PrivatePayrollConfig cfg) {
  if (!esicEligible) return 0;
  if (!(cfg.esicApplyAboveCeilingWhenEligible == true) && !isWithinEsicWageCeiling(esicWageBase, cfg)) return 0;
  final w = math.max(0, esicWageBase);
  final raw = w * cfg.esicEmployeeRate;
  return raw.ceil();
}

int computeEsicEmployer(int esicWageBase, bool esicEligible, PrivatePayrollConfig cfg) {
  if (!esicEligible) return 0;
  if (!(cfg.esicApplyAboveCeilingWhenEligible == true) && !isWithinEsicWageCeiling(esicWageBase, cfg)) return 0;
  final w = math.max(0, esicWageBase);
  final raw = w * cfg.esicEmployerRate;
  return raw.ceil();
}

class PrivateSalaryBreakup {
  const PrivateSalaryBreakup({
    required this.basic,
    required this.hra,
    required this.medical,
    required this.trans,
    required this.lta,
    required this.personal,
  });

  final int basic;
  final int hra;
  final int medical;
  final int trans;
  final int lta;
  final int personal;
}

/// Optional components (null = use default split for that field).
class PrivateSalaryBreakupInput {
  const PrivateSalaryBreakupInput({this.basic, this.hra, this.medical, this.trans, this.lta, this.personal});

  final int? basic;
  final int? hra;
  final int? medical;
  final int? trans;
  final int? lta;
  final int? personal;
}

PrivateSalaryBreakup defaultSalaryBreakup(int gross, PrivatePayrollConfig cfg) {
  final g = math.max(0, gross);
  final basic = computeBasicDaFromGross(gross, cfg);
  final hra = computeHraFromBasicDa(basic, cfg);
  final medical = (basic * cfg.advanceBonusRateOnBasic).round();
  const trans = 0;
  const lta = 0;
  final personal = math.max(0, g - basic - hra - medical - trans - lta);
  return PrivateSalaryBreakup(basic: basic, hra: hra, medical: medical, trans: trans, lta: lta, personal: personal);
}

PrivateSalaryBreakup resolveSalaryComponentsForPrivate(
  int gross,
  PrivateSalaryBreakupInput? salaryBreakup,
  PrivatePayrollConfig cfg,
) {
  final g = math.max(0, gross);
  final defaults = defaultSalaryBreakup(gross, cfg);
  if (salaryBreakup == null) return defaults;

  final hasAny = [salaryBreakup.basic, salaryBreakup.hra, salaryBreakup.medical, salaryBreakup.trans, salaryBreakup.lta, salaryBreakup.personal]
      .any((v) => v != null);
  if (!hasAny) return defaults;

  final basic = salaryBreakup.basic != null ? salaryBreakup.basic!.round() : defaults.basic;
  final hra = salaryBreakup.hra != null ? salaryBreakup.hra!.round() : computeHraFromBasicDa(basic, cfg);
  final medical = salaryBreakup.medical != null ? salaryBreakup.medical!.round() : (basic * cfg.advanceBonusRateOnBasic).round();
  final trans = salaryBreakup.trans != null ? salaryBreakup.trans!.round() : 0;
  final lta = salaryBreakup.lta != null ? salaryBreakup.lta!.round() : 0;
  final personal = salaryBreakup.personal != null ? salaryBreakup.personal!.round() : math.max(0, g - basic - hra - medical - trans - lta);

  return PrivateSalaryBreakup(basic: basic, hra: hra, medical: medical, trans: trans, lta: lta, personal: personal);
}

class PrivateGrossPayrollResult {
  const PrivateGrossPayrollResult({
    required this.basic,
    required this.hra,
    required this.medical,
    required this.trans,
    required this.lta,
    required this.personal,
    required this.grossTotal,
    required this.pfEmp,
    required this.pfEmpr,
    required this.esicEmp,
    required this.esicEmpr,
    required this.ctc,
    required this.takeHomeBase,
  });

  final int basic;
  final int hra;
  final int medical;
  final int trans;
  final int lta;
  final int personal;
  final int grossTotal;
  final int pfEmp;
  final int pfEmpr;
  final int esicEmp;
  final int esicEmpr;
  final int ctc;
  final int takeHomeBase;

  PrivateGrossPayrollResult copyWith({
    int? basic,
    int? hra,
    int? medical,
    int? trans,
    int? lta,
    int? personal,
    int? grossTotal,
    int? pfEmp,
    int? pfEmpr,
    int? esicEmp,
    int? esicEmpr,
    int? ctc,
    int? takeHomeBase,
  }) {
    return PrivateGrossPayrollResult(
      basic: basic ?? this.basic,
      hra: hra ?? this.hra,
      medical: medical ?? this.medical,
      trans: trans ?? this.trans,
      lta: lta ?? this.lta,
      personal: personal ?? this.personal,
      grossTotal: grossTotal ?? this.grossTotal,
      pfEmp: pfEmp ?? this.pfEmp,
      pfEmpr: pfEmpr ?? this.pfEmpr,
      esicEmp: esicEmp ?? this.esicEmp,
      esicEmpr: esicEmpr ?? this.esicEmpr,
      ctc: ctc ?? this.ctc,
      takeHomeBase: takeHomeBase ?? this.takeHomeBase,
    );
  }
}

/// When monthly CTC is fixed, search gross so that Gross + Empr PF + Empr ESIC matches target (web `payrollCalc.ts`).
PrivateGrossPayrollResult computePayrollFromCtc(
  int ctcMonthly,
  bool pfEligible,
  bool esicEligible,
  int fixedProfessionalTaxMonthly,
  PrivateSalaryBreakupInput? salaryBreakup,
  PrivatePayrollConfig cfg,
) {
  final target = math.max(0, ctcMonthly);
  if (target <= 0) {
    return computePayrollFromGross(0, pfEligible, esicEligible, fixedProfessionalTaxMonthly, salaryBreakup, cfg);
  }
  final start = target;
  final minGross = math.max(0, target - 10000);
  PrivateGrossPayrollResult? best;
  for (var g = start; g >= minGross; g--) {
    final calc = computePayrollFromGross(g, pfEligible, esicEligible, fixedProfessionalTaxMonthly, salaryBreakup, cfg);
    if (calc.ctc == target) return calc;
    if (calc.ctc < target) {
      if (best == null || calc.ctc > best.ctc) best = calc;
    }
  }
  if (best != null) return best.copyWith(ctc: target);
  return computePayrollFromGross(0, pfEligible, esicEligible, fixedProfessionalTaxMonthly, salaryBreakup, cfg);
}

PrivateGrossPayrollResult computePayrollFromGross(
  int gross,
  bool pfEligible,
  bool esicEligible,
  int ptMonthly,
  PrivateSalaryBreakupInput? salaryBreakup,
  PrivatePayrollConfig cfg,
) {
  final components = resolveSalaryComponentsForPrivate(gross, salaryBreakup, cfg);
  final grossTotal =
      (components.basic + components.hra + components.medical + components.trans + components.lta + components.personal).round();

  final pfEmp = computePfFromBasicDa(components.basic, pfEligible, cfg);
  final pfEmpr = pfEligible ? ((pfEmp / 12) * 13).round() : 0;
  final esicWage = components.basic;
  final esicEmp = computeEsicEmployee(esicWage, esicEligible, cfg);
  final esicEmpr = computeEsicEmployer(esicWage, esicEligible, cfg);
  final takeHomeBase = grossTotal - pfEmp - esicEmp - ptMonthly;
  final ctc = grossTotal + pfEmpr + esicEmpr;

  return PrivateGrossPayrollResult(
    basic: components.basic,
    hra: components.hra,
    medical: components.medical,
    trans: components.trans,
    lta: components.lta,
    personal: components.personal,
    grossTotal: grossTotal,
    pfEmp: pfEmp,
    pfEmpr: pfEmpr,
    esicEmp: esicEmp,
    esicEmpr: esicEmpr,
    ctc: ctc,
    takeHomeBase: takeHomeBase,
  );
}

bool isPfStatutorilyMandatory(int gross, PrivatePayrollConfig cfg) {
  if (gross <= 0) return false;
  final basicDa = computeBasicDaFromGross(gross, cfg);
  return basicDa <= cfg.pfWageCap.round();
}

bool isDefaultSalaryBreakupForGross(
  int gross,
  int basic,
  int hra,
  int medical,
  int trans,
  int lta,
  int personal,
  PrivatePayrollConfig cfg,
) {
  if (gross <= 0) return false;
  final d = defaultSalaryBreakup(gross, cfg);
  const tol = 2;
  return (basic - d.basic).abs() <= tol &&
      (hra - d.hra).abs() <= tol &&
      (medical - d.medical).abs() <= tol &&
      (trans - d.trans).abs() <= tol &&
      (lta - d.lta).abs() <= tol &&
      (personal - d.personal).abs() <= tol;
}

class PrivateEditPreview {
  const PrivateEditPreview({
    required this.calc,
    required this.ptMonthly,
    required this.takeHome,
    required this.tds,
    required this.advanceBonus,
  });

  final PrivateGrossPayrollResult calc;
  final int ptMonthly;
  final int takeHome;
  final int tds;
  final int advanceBonus;
}

PrivateEditPreview computePrivateEditPreview({
  required int gross,
  required bool pfEligible,
  required bool esicEligible,
  required double? ptFieldParsed,
  required int companyPt,
  required int tds,
  required int advanceBonus,
  required PrivateSalaryBreakupInput? salaryBreakup,
  required PrivatePayrollConfig cfg,
}) {
  if (gross <= 0) {
    final z = computePayrollFromGross(0, pfEligible, esicEligible, 0, salaryBreakup, cfg);
    return PrivateEditPreview(calc: z, ptMonthly: 0, takeHome: 0, tds: tds, advanceBonus: advanceBonus);
  }
  final ptFallback = (ptFieldParsed != null && ptFieldParsed.isFinite && ptFieldParsed >= 0) ? ptFieldParsed.round() : companyPt;
  final ptMonth = computeProfessionalTaxMonthly(gross, cfg, ptFallback.toDouble());
  final calc = computePayrollFromGross(gross, pfEligible, esicEligible, ptMonth, salaryBreakup, cfg);
  final takeHome = math.max(0, calc.takeHomeBase - tds + advanceBonus);
  return PrivateEditPreview(calc: calc, ptMonthly: ptMonth, takeHome: takeHome, tds: tds, advanceBonus: advanceBonus);
}

class PrivateMasterSaveRow {
  const PrivateMasterSaveRow({
    required this.grossSalary,
    required this.basic,
    required this.hra,
    required this.medical,
    required this.trans,
    required this.lta,
    required this.personal,
    required this.ctc,
    required this.pfEligible,
    required this.esicEligible,
    required this.pfEmployee,
    required this.pfEmployer,
    required this.esicEmployee,
    required this.esicEmployer,
    required this.pt,
    required this.tds,
    required this.advanceBonus,
    required this.takeHome,
  });

  final int grossSalary;
  final int basic;
  final int hra;
  final int medical;
  final int trans;
  final int lta;
  final int personal;
  final int ctc;
  final bool pfEligible;
  final bool esicEligible;
  final int pfEmployee;
  final int pfEmployer;
  final int esicEmployee;
  final int esicEmployer;
  final int pt;
  final int tds;
  final int advanceBonus;
  final int takeHome;
}

PrivateMasterSaveRow buildPrivateMasterSaveRow({
  required int grossInput,
  required int basicIn,
  required int hraIn,
  required int medicalIn,
  required int transIn,
  required int ltaIn,
  required int personalIn,
  required bool compactPayslipHeads,
  required bool pfEligible,
  required bool esicEligible,
  required double? ptOverride,
  required int companyPt,
  required int tds,
  required int advanceBonus,
  required PrivatePayrollConfig cfg,
}) {
  var grossSalary = math.max(0, grossInput);
  final t0 = compactPayslipHeads ? 0 : transIn;
  final l0 = compactPayslipHeads ? 0 : ltaIn;
  final sumComp = basicIn + hraIn + medicalIn + t0 + l0 + personalIn;
  if (sumComp > 0) grossSalary = sumComp;

  final salaryBreakup = sumComp > 0
      ? PrivateSalaryBreakupInput(basic: basicIn, hra: hraIn, medical: medicalIn, trans: t0, lta: l0, personal: personalIn)
      : null;

  final ptMonthlyFallback = (ptOverride != null && ptOverride.isFinite && ptOverride >= 0) ? ptOverride.round() : companyPt;
  final grossRoundedInitial = grossSalary;
  final ptForGrossPath = computeProfessionalTaxMonthly(grossRoundedInitial, cfg, ptMonthlyFallback.toDouble());
  final calc = computePayrollFromGross(grossRoundedInitial, pfEligible, esicEligible, ptForGrossPath, salaryBreakup, cfg);
  final takeHome = math.max(0, calc.takeHomeBase - tds + advanceBonus);
  final grossFinal = grossRoundedInitial;
  final ptStored = computeProfessionalTaxMonthly(grossFinal, cfg, ptMonthlyFallback.toDouble());

  return PrivateMasterSaveRow(
    grossSalary: grossFinal,
    basic: calc.basic,
    hra: calc.hra,
    medical: calc.medical,
    trans: calc.trans,
    lta: calc.lta,
    personal: calc.personal,
    ctc: calc.ctc,
    pfEligible: pfEligible,
    esicEligible: esicEligible,
    pfEmployee: calc.pfEmp,
    pfEmployer: calc.pfEmpr,
    esicEmployee: calc.esicEmp,
    esicEmployer: calc.esicEmpr,
    pt: ptStored,
    tds: math.max(0, tds),
    advanceBonus: math.max(0, advanceBonus),
    takeHome: takeHome,
  );
}
