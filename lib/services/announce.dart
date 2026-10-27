import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Mengirim pesan ke screen reader (TalkBack/VoiceOver), untuk perubahan
/// kondisi seperti pindah halaman, pindah soal, benar/salah, atau item
/// pindah. Tidak berbunyi kalau screen reader mati: APREVO tidak punya TTS.
void announce(String message) {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final view =
      dispatcher.implicitView ??
      (dispatcher.views.isEmpty ? null : dispatcher.views.first);
  if (view == null) return;
  SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
}
