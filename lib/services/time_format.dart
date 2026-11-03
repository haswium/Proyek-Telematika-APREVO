/// Waktu dalam bahasa Indonesia untuk dibaca dan didengar, dan waktu ISO
/// 8601 berzona untuk dikirim ke backend.
library;

const List<String> _days = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

const List<String> _months = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Senin, 3 November 2026"
String formatDate(DateTime time) {
  final t = time.toLocal();
  return '${_days[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// "21.00"
String formatClock(DateTime time) {
  final t = time.toLocal();
  return '${_two(t.hour)}.${_two(t.minute)}';
}

/// "Senin, 3 November 2026 pukul 21.00"
String formatDateTime(DateTime time) =>
    '${formatDate(time)} pukul ${formatClock(time)}';

/// Waktu lokal dengan zona waktunya, misalnya
/// "2026-11-03T21:00:00+07:00". `toIso8601String()` bawaan Dart tidak
/// menyertakan zona untuk waktu lokal, dan backend menolak waktu tanpa zona.
String isoWithOffset(DateTime time) {
  final t = time.toLocal();
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-'
      '${_two(t.day)}T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}'
      '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

/// Waktu dari backend, diubah ke waktu lokal. `null` kalau kosong.
DateTime? parseTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
