import 'package:flutter/material.dart';

/// Memilih tanggal lalu jam, untuk jadwal kuis dan sesi presensi.
///
/// Kedua dialog dibuka dalam mode ketik: tanggal diketik di satu kolom
/// (hh/bb/tttt), jam di dua kolom. Kalender bertingkat dan dropdown tahun
/// sering tidak terbaca utuh oleh TalkBack. Tombol bawaan di dialog tetap
/// bisa dipakai untuk beralih ke kalender atau jam putar.
///
/// [what] melengkapi judul dialog: "Pilih tanggal buka", "Pilih jam buka".
/// `null` kalau guru membatalkan salah satu dialog.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
  required String what,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(firstDate) ? firstDate : initial,
    firstDate: firstDate,
    lastDate: lastDate,
    initialEntryMode: DatePickerEntryMode.input,
    helpText: 'Pilih tanggal $what',
    fieldLabelText: 'Tanggal $what',
    fieldHintText: 'hh/bb/tttt',
    errorFormatText: 'Format tanggal salah. Contoh: 17/11/2026',
    errorInvalidText: 'Tanggal di luar rentang yang boleh dipilih',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    initialEntryMode: TimePickerEntryMode.input,
    helpText: 'Pilih jam $what',
    hourLabelText: 'Jam',
    minuteLabelText: 'Menit',
    errorInvalidText: 'Jam tidak valid',
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
