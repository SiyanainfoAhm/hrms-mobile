// Mirrors web `src/lib/attendancePolicy.ts` — combined lunch+tea minimum break
// counting on punch-out.

const int minCombinedBreakMinutes = 60;

int clampMinutes(num n) {
  final x = n.round();
  if (x < 0) return 0;
  if (x > 24 * 60) return 24 * 60;
  return x;
}

/// Same semantics as `effectiveCombinedBreakBreakdown` on the web.
({int lunchBreakMinutes, int teaBreakMinutes, int actualBreakMinutes, int countedBreakMinutes, int policyShortfallMinutes})
    effectiveCombinedBreakBreakdown({
  required int lunchMinutes,
  required int teaMinutes,
  required int grossWorkMinutes,
  int? minimumBreakMinutes,
}) {
  final lunch = clampMinutes(lunchMinutes);
  final tea = clampMinutes(teaMinutes);
  final gross = clampMinutes(grossWorkMinutes);
  final minimum = clampMinutes(minimumBreakMinutes ?? minCombinedBreakMinutes);

  final actualBreakMinutes = lunch + tea;
  final countedBreakMinutes = actualBreakMinutes < minimum ? minimum : actualBreakMinutes;
  final capped = countedBreakMinutes > gross ? gross : countedBreakMinutes;
  final policyShortfallMinutes = ((capped - actualBreakMinutes).clamp(0, 24 * 60)).toInt();

  return (
    lunchBreakMinutes: lunch + policyShortfallMinutes,
    teaBreakMinutes: tea,
    actualBreakMinutes: actualBreakMinutes,
    countedBreakMinutes: capped,
    policyShortfallMinutes: policyShortfallMinutes,
  );
}
