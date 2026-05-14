// Ported from hrms-web `governmentPayroll.ts` for Run payroll preview parity.

import 'dart:math' as math;

class TransportSlab {
  const TransportSlab({required this.transportSlabGroup, required this.transportBase});

  final String transportSlabGroup;
  final int transportBase;
}

TransportSlab deriveTransportSlabFromLevel(num? level) {
  if (level == null || !level.isFinite) {
    throw ArgumentError('government_pay_level is required for government payroll');
  }
  final lv = level.floor();
  if (lv < 1) throw ArgumentError('government_pay_level must be at least 1');
  if (lv <= 2) return const TransportSlab(transportSlabGroup: 'LEVEL_1_2', transportBase: 1350);
  if (lv <= 8) return const TransportSlab(transportSlabGroup: 'LEVEL_3_8', transportBase: 3600);
  return const TransportSlab(transportSlabGroup: 'LEVEL_9_ABOVE', transportBase: 7200);
}

class GovernmentDeductionDefaults {
  const GovernmentDeductionDefaults({
    required this.incomeTax,
    required this.pt,
    required this.lic,
    required this.cpf,
    required this.daCpf,
    required this.vpf,
    required this.pfLoan,
    required this.postOffice,
    required this.creditSociety,
    required this.stdLicenceFee,
    required this.electricity,
    required this.water,
    required this.mess,
    required this.horticulture,
    required this.welfare,
    required this.vehCharge,
    required this.other,
  });

  final int incomeTax;
  final int pt;
  final int lic;
  final int cpf;
  final int daCpf;
  final int vpf;
  final int pfLoan;
  final int postOffice;
  final int creditSociety;
  final int stdLicenceFee;
  final int electricity;
  final int water;
  final int mess;
  final int horticulture;
  final int welfare;
  final int vehCharge;
  final int other;
}

class GovernmentOptionalMonthlyEarnings {
  const GovernmentOptionalMonthlyEarnings({
    this.spPay = 0,
    this.extraWorkAllowance = 0,
    this.nightAllowance = 0,
    this.uniformAllowance = 0,
    this.educationAllowance = 0,
    this.daArrears = 0,
    this.transportArrears = 0,
    this.encashment = 0,
    this.encashmentDa = 0,
  });

  final int spPay;
  final int extraWorkAllowance;
  final int nightAllowance;
  final int uniformAllowance;
  final int educationAllowance;
  final int daArrears;
  final int transportArrears;
  final int encashment;
  final int encashmentDa;
}

class GovernmentEarningPaidOverrides {
  const GovernmentEarningPaidOverrides({
    this.basicPaid,
    this.spPayPaid,
    this.daPaid,
    this.transportPaid,
    this.hraPaid,
    this.medicalPaid,
    this.extraWorkAllowancePaid,
    this.nightAllowancePaid,
    this.uniformAllowancePaid,
    this.educationAllowancePaid,
    this.daArrearsPaid,
    this.transportArrearsPaid,
    this.encashmentPaid,
    this.encashmentDaPaid,
  });

  final int? basicPaid;
  final int? spPayPaid;
  final int? daPaid;
  final int? transportPaid;
  final int? hraPaid;
  final int? medicalPaid;
  final int? extraWorkAllowancePaid;
  final int? nightAllowancePaid;
  final int? uniformAllowancePaid;
  final int? educationAllowancePaid;
  final int? daArrearsPaid;
  final int? transportArrearsPaid;
  final int? encashmentPaid;
  final int? encashmentDaPaid;
}

class GovernmentMonthlyInput {
  const GovernmentMonthlyInput({
    required this.grossBasic,
    required this.daPercent,
    required this.hraPercent,
    required this.medicalFixed,
    required this.transportDaPercent,
    required this.payLevel,
    required this.daysInMonth,
    required this.unpaidDays,
    required this.deductionDefaults,
    this.optionalEarnings,
    this.earningPaidOverrides,
  });

  final int grossBasic;
  final double daPercent;
  final double hraPercent;
  final int medicalFixed;
  final double transportDaPercent;
  final int payLevel;
  final int daysInMonth;
  final double unpaidDays;
  final GovernmentDeductionDefaults deductionDefaults;
  final GovernmentOptionalMonthlyEarnings? optionalEarnings;
  final GovernmentEarningPaidOverrides? earningPaidOverrides;
}

class GovernmentMonthlyComputed {
  const GovernmentMonthlyComputed({
    required this.transportSlab,
    required this.transportActual,
    required this.transportPaid,
    required this.basicActual,
    required this.basicPaid,
    required this.spPayActual,
    required this.spPayPaid,
    required this.daActual,
    required this.daPaid,
    required this.hraActual,
    required this.hraPaid,
    required this.medicalActual,
    required this.medicalPaid,
    required this.extraWorkAllowanceActual,
    required this.extraWorkAllowancePaid,
    required this.nightAllowanceActual,
    required this.nightAllowancePaid,
    required this.uniformAllowanceActual,
    required this.uniformAllowancePaid,
    required this.educationAllowanceActual,
    required this.educationAllowancePaid,
    required this.daArrearsActual,
    required this.daArrearsPaid,
    required this.transportArrearsActual,
    required this.transportArrearsPaid,
    required this.encashmentActual,
    required this.encashmentPaid,
    required this.encashmentDaActual,
    required this.encashmentDaPaid,
    required this.deductions,
    required this.totalEarnings,
    required this.totalDeductions,
    required this.netSalary,
  });

  final TransportSlab transportSlab;
  final int transportActual;
  final int transportPaid;
  final int basicActual;
  final int basicPaid;
  final int spPayActual;
  final int spPayPaid;
  final int daActual;
  final int daPaid;
  final int hraActual;
  final int hraPaid;
  final int medicalActual;
  final int medicalPaid;
  final int extraWorkAllowanceActual;
  final int extraWorkAllowancePaid;
  final int nightAllowanceActual;
  final int nightAllowancePaid;
  final int uniformAllowanceActual;
  final int uniformAllowancePaid;
  final int educationAllowanceActual;
  final int educationAllowancePaid;
  final int daArrearsActual;
  final int daArrearsPaid;
  final int transportArrearsActual;
  final int transportArrearsPaid;
  final int encashmentActual;
  final int encashmentPaid;
  final int encashmentDaActual;
  final int encashmentDaPaid;
  final GovernmentDeductionDefaults deductions;
  final int totalEarnings;
  final int totalDeductions;
  final int netSalary;
}

int _rr(num n) => (n.isFinite ? n : 0).round();

const double governmentDefaultCpfRateOnTotalEarnings = 0.12;

int paidAfterUnpaidDays(int actual, int daysInMonth, num unpaidDays) {
  final dim = math.max(1, daysInMonth.floor());
  final u = math.max(0, math.min(unpaidDays.floor(), dim));
  return _rr(actual - (actual / dim) * u);
}

GovernmentMonthlyComputed computeGovernmentMonthlyPayroll(GovernmentMonthlyInput input) {
  final slab = deriveTransportSlabFromLevel(input.payLevel);
  final tda = input.transportDaPercent;
  final transportActual = _rr(slab.transportBase + (slab.transportBase * tda) / 100);
  var transportPaid = transportActual;

  final gb = input.grossBasic;
  final daPct = input.daPercent;
  final hraPct = input.hraPercent;
  final medFixed = input.medicalFixed;

  final basicActual = gb;
  final daActual = _rr((gb * daPct) / 100);
  final hraActual = _rr((gb * hraPct) / 100);
  final medicalActual = medFixed;

  final dim = math.max(1, input.daysInMonth.floor());
  final unpaid = math.max(0, math.min(input.unpaidDays.floor(), dim));

  var basicPaid = paidAfterUnpaidDays(basicActual, dim, unpaid);
  var daPaid = paidAfterUnpaidDays(daActual, dim, unpaid);
  var hraPaid = paidAfterUnpaidDays(hraActual, dim, unpaid);
  var medicalPaid = paidAfterUnpaidDays(medicalActual, dim, unpaid);

  final opt = input.optionalEarnings ?? const GovernmentOptionalMonthlyEarnings();
  final sp = opt.spPay;
  final ewa = opt.extraWorkAllowance;
  final na = opt.nightAllowance;
  final ua = opt.uniformAllowance;
  final eda = opt.educationAllowance;
  final daa = opt.daArrears;
  final tra = opt.transportArrears;
  final enc = opt.encashment;
  final encDa = opt.encashmentDa;

  final eo = input.earningPaidOverrides;
  int pickPaid(int computed, int? override) {
    if (override != null) return override;
    return computed;
  }

  final basicPaidF = pickPaid(basicPaid, eo?.basicPaid);
  final daPaidF = pickPaid(daPaid, eo?.daPaid);
  final hraPaidF = pickPaid(hraPaid, eo?.hraPaid);
  final medicalPaidF = pickPaid(medicalPaid, eo?.medicalPaid);
  final transportPaidF = pickPaid(transportPaid, eo?.transportPaid);
  final spF = pickPaid(sp, eo?.spPayPaid);
  final ewaF = pickPaid(ewa, eo?.extraWorkAllowancePaid);
  final naF = pickPaid(na, eo?.nightAllowancePaid);
  final uaF = pickPaid(ua, eo?.uniformAllowancePaid);
  final edaF = pickPaid(eda, eo?.educationAllowancePaid);
  final daaF = pickPaid(daa, eo?.daArrearsPaid);
  final traF = pickPaid(tra, eo?.transportArrearsPaid);
  final encF = pickPaid(enc, eo?.encashmentPaid);
  final encDaF = pickPaid(encDa, eo?.encashmentDaPaid);

  final dIn = input.deductionDefaults;

  final totalEarnings = basicPaidF +
      daPaidF +
      hraPaidF +
      medicalPaidF +
      transportPaidF +
      spF +
      ewaF +
      naF +
      uaF +
      edaF +
      daaF +
      traF +
      encF +
      encDaF;

  var cpfFromMaster = _rr(dIn.cpf);
  if (cpfFromMaster <= 0) {
    cpfFromMaster = _rr(totalEarnings * governmentDefaultCpfRateOnTotalEarnings);
  }

  final deductions = GovernmentDeductionDefaults(
    incomeTax: _rr(dIn.incomeTax),
    pt: _rr(dIn.pt),
    lic: _rr(dIn.lic),
    cpf: cpfFromMaster,
    daCpf: _rr(dIn.daCpf),
    vpf: _rr(dIn.vpf),
    pfLoan: _rr(dIn.pfLoan),
    postOffice: _rr(dIn.postOffice),
    creditSociety: _rr(dIn.creditSociety),
    stdLicenceFee: _rr(dIn.stdLicenceFee),
    electricity: _rr(dIn.electricity),
    water: _rr(dIn.water),
    mess: _rr(dIn.mess),
    horticulture: _rr(dIn.horticulture),
    welfare: _rr(dIn.welfare),
    vehCharge: _rr(dIn.vehCharge),
    other: _rr(dIn.other),
  );

  final totalDeductions = deductions.incomeTax +
      deductions.pt +
      deductions.lic +
      deductions.cpf +
      deductions.daCpf +
      deductions.vpf +
      deductions.pfLoan +
      deductions.postOffice +
      deductions.creditSociety +
      deductions.stdLicenceFee +
      deductions.electricity +
      deductions.water +
      deductions.mess +
      deductions.horticulture +
      deductions.welfare +
      deductions.vehCharge +
      deductions.other;

  final netSalary = _rr(totalEarnings - totalDeductions);
  transportPaid = transportPaidF;

  return GovernmentMonthlyComputed(
    transportSlab: slab,
    transportActual: transportActual,
    transportPaid: transportPaidF,
    basicActual: basicActual,
    basicPaid: basicPaidF,
    spPayActual: spF,
    spPayPaid: spF,
    daActual: daActual,
    daPaid: daPaidF,
    hraActual: hraActual,
    hraPaid: hraPaidF,
    medicalActual: medicalActual,
    medicalPaid: medicalPaidF,
    extraWorkAllowanceActual: ewaF,
    extraWorkAllowancePaid: ewaF,
    nightAllowanceActual: naF,
    nightAllowancePaid: naF,
    uniformAllowanceActual: uaF,
    uniformAllowancePaid: uaF,
    educationAllowanceActual: edaF,
    educationAllowancePaid: edaF,
    daArrearsActual: daaF,
    daArrearsPaid: daaF,
    transportArrearsActual: traF,
    transportArrearsPaid: traF,
    encashmentActual: encF,
    encashmentPaid: encF,
    encashmentDaActual: encDaF,
    encashmentDaPaid: encDaF,
    deductions: deductions,
    totalEarnings: totalEarnings,
    totalDeductions: totalDeductions,
    netSalary: netSalary,
  );
}

GovernmentDeductionDefaults masterRowToDeductionDefaults(Map<String, dynamic> m) {
  int nz(dynamic a, dynamic b) {
    final x = num.tryParse('${a ?? b ?? 0}');
    return x != null && x.isFinite ? x.round() : 0;
  }

  return GovernmentDeductionDefaults(
    incomeTax: nz(m['income_tax_default'], m['tds']),
    pt: nz(m['pt_default'], 200),
    lic: nz(m['lic_default'], 0),
    cpf: nz(m['cpf_default'], 0),
    daCpf: nz(m['da_cpf_default'], 0),
    vpf: nz(m['vpf_default'], 0),
    pfLoan: nz(m['pf_loan_default'], 0),
    postOffice: nz(m['post_office_default'], 0),
    creditSociety: nz(m['credit_society_default'], 0),
    stdLicenceFee: nz(m['std_licence_fee_default'], 0),
    electricity: nz(m['electricity_default'], 0),
    water: nz(m['water_default'], 0),
    mess: nz(m['mess_default'], 0),
    horticulture: nz(m['horticulture_default'], 0),
    welfare: nz(m['welfare_default'], 0),
    vehCharge: nz(m['veh_charge_default'], 0),
    other: nz(m['other_deduction_default'], 0),
  );
}
