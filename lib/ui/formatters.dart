class UiFormatters {
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  static const _monthsLong = [
    'January','February','March','April','May','June','July','August','September','October','November','December'
  ];

  static DateTime? tryParse(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static String indianDate(dynamic v) {
    final dt = tryParse(v);
    if (dt == null) return (v ?? '—').toString();
    final m = (dt.month >= 1 && dt.month <= 12) ? _months[dt.month - 1] : dt.month.toString();
    return '${dt.day.toString().padLeft(2, '0')} - $m - ${dt.year}';
  }

  static String inr(dynamic amount) {
    if (amount == null) return '—';
    final n = num.tryParse(amount.toString());
    if (n == null) return amount.toString();
    final s = n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2);
    return '₹$s';
  }

  static String indianNumber(dynamic v) {
    final n = num.tryParse((v ?? 0).toString());
    if (n == null) return (v ?? '').toString();
    final isNeg = n < 0;
    final abs = n.abs();
    final fixed = abs.toStringAsFixed(abs == abs.roundToDouble() ? 0 : 2);
    final parts = fixed.split('.');
    var i = parts[0];
    final dec = parts.length > 1 ? parts[1] : null;

    if (i.length > 3) {
      final last3 = i.substring(i.length - 3);
      var rest = i.substring(0, i.length - 3);
      final buf = StringBuffer();
      while (rest.length > 2) {
        buf.write('${rest.substring(rest.length - 2)},');
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) buf.write('$rest,');
      i = '${buf.toString()}$last3';
    }

    final out = dec == null || dec == '00' ? i : '$i.$dec';
    return isNeg ? '-$out' : out;
  }

  static String indianDateLong(dynamic v) {
    final dt = tryParse(v);
    if (dt == null) return (v ?? '—').toString();
    final m = (dt.month >= 1 && dt.month <= 12) ? _monthsLong[dt.month - 1] : dt.month.toString();
    return '${dt.day} $m ${dt.year}';
  }

  /// Accepts YYYY-MM-DD (or longer ISO) and returns DD-MM-YYYY.
  static String fmtDmy(dynamic isoOrYmd) {
    final raw = (isoOrYmd ?? '').toString();
    final s = raw.length >= 10 ? raw.substring(0, 10) : raw;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return raw;
    final parts = s.split('-');
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  /// Accepts DD-MM-YYYY and returns YYYY-MM-DD (or '' if invalid).
  static String ymdFromDmy(String dmy) {
    final s = dmy.trim();
    final m = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(s);
    if (m == null) return '';
    final dd = m.group(1)!;
    final mm = m.group(2)!;
    final yyyy = m.group(3)!;
    return '$yyyy-$mm-$dd';
  }

  static String indianDateShort(dynamic v) {
    final dt = tryParse(v);
    if (dt == null) return (v ?? '—').toString();
    final m = (dt.month >= 1 && dt.month <= 12) ? _months[dt.month - 1] : dt.month.toString();
    return '${dt.day.toString().padLeft(2, '0')} $m ${dt.year}';
  }
}

