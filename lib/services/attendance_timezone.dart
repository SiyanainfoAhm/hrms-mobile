import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Same IANA ids as web `attendanceTimeZone.ts`.
const String kIstTz = 'Asia/Kolkata';
const String kUsEasternTz = 'America/New_York';

bool _tzInitialized = false;

void ensureAttendanceTimeZonesInitialized() {
  if (_tzInitialized) return;
  tzdata.initializeTimeZones();
  _tzInitialized = true;
}

int? _parseTime24ToMinutes(String? value) {
  final v = (value ?? '').trim();
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(v);
  if (m == null) return null;
  final hh = int.tryParse(m.group(1)!);
  final mm = int.tryParse(m.group(2)!);
  if (hh == null || mm == null) return null;
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
  return hh * 60 + mm;
}

/// Calendar `yyyy-MM-dd` in [ianaTimeZone] for instant [utc].
String ymdInTimeZone(DateTime utc, String ianaTimeZone) {
  ensureAttendanceTimeZonesInitialized();
  final loc = tz.getLocation(ianaTimeZone);
  final z = tz.TZDateTime.from(utc.toUtc(), loc);
  return '${z.year.toString().padLeft(4, '0')}-${z.month.toString().padLeft(2, '0')}-${z.day.toString().padLeft(2, '0')}';
}

/// Minute-of-day (0–1439) in [ianaTimeZone] for instant [utc].
int hmMinutesInTimeZone(DateTime utc, String ianaTimeZone) {
  ensureAttendanceTimeZonesInitialized();
  final loc = tz.getLocation(ianaTimeZone);
  final z = tz.TZDateTime.from(utc.toUtc(), loc);
  return z.hour * 60 + z.minute;
}

/// Web `computeWorkDateForNow` (`attendanceTimeZone.ts`).
String computeWorkDateForNow({
  required DateTime nowUtc,
  required String attendanceTz,
  required bool isNightShift,
  required String? shiftStartTime,
  required String? shiftEndTime,
}) {
  final today = ymdInTimeZone(nowUtc, attendanceTz);
  if (!isNightShift) return today;

  final endMin = shiftEndTime != null ? _parseTime24ToMinutes(shiftEndTime) : null;
  if (endMin == null) {
    final nowMin = hmMinutesInTimeZone(nowUtc, attendanceTz);
    if (nowMin < 6 * 60) {
      return ymdInTimeZone(nowUtc.subtract(const Duration(days: 1)), attendanceTz);
    }
    return today;
  }

  final nowMin = hmMinutesInTimeZone(nowUtc, attendanceTz);
  if (nowMin < endMin) {
    return ymdInTimeZone(nowUtc.subtract(const Duration(days: 1)), attendanceTz);
  }
  return today;
}

/// Web `getAttendanceContextForUser` (`attendanceTimeZone.ts`).
Future<({String timeZone, bool isNightShift, String? shiftStartTime, String? shiftEndTime})> getAttendanceContextForUser({
  required SupabaseClient sb,
  required String companyId,
  required String attendanceEmployeeId,
}) async {
  final emp = await sb
      .from('HRMS_employees')
      .select('shift_id')
      .eq('company_id', companyId)
      .eq('id', attendanceEmployeeId)
      .maybeSingle();

  final shiftId = (emp?['shift_id'] ?? '').toString().trim();
  if (shiftId.isEmpty) {
    return (timeZone: kIstTz, isNightShift: false, shiftStartTime: null, shiftEndTime: null);
  }

  final shift = await sb
      .from('HRMS_shifts')
      .select('is_night_shift, start_time, end_time')
      .eq('company_id', companyId)
      .eq('id', shiftId)
      .maybeSingle();

  final isNightShift = shift?['is_night_shift'] == true;
  final timeZone = isNightShift ? kUsEasternTz : kIstTz;
  final st = shift?['start_time']?.toString();
  final et = shift?['end_time']?.toString();

  return (
    timeZone: timeZone,
    isNightShift: isNightShift,
    shiftStartTime: (st != null && st.trim().isNotEmpty) ? st.trim() : null,
    shiftEndTime: (et != null && et.trim().isNotEmpty) ? et.trim() : null,
  );
}
