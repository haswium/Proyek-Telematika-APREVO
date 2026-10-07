import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Dua jalur suara APREVO:
///
/// * [announce] mengirim pesan ke screen reader (TalkBack/VoiceOver).
///   Dipakai untuk perubahan kondisi: pindah soal, benar/salah, item pindah.
///   Tidak berbunyi kalau screen reader mati.
/// * [speak] membacakan teks dengan text-to-speech bawaan perangkat.
///   Dipakai untuk tombol "Dengarkan", jadi tetap berbunyi tanpa TalkBack.
class Speech {
  Speech._();

  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.setLanguage('id-ID');
      await _tts.setSpeechRate(0.45);
    } catch (_) {
      // Bahasa Indonesia belum terpasang di perangkat: pakai suara bawaan.
    }
  }

  static Future<void> speak(String text) async {
    try {
      await _init();
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // TTS tidak tersedia (misalnya saat widget test). Abaikan.
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  static void announce(String message) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.implicitView ??
        (dispatcher.views.isEmpty ? null : dispatcher.views.first);
    if (view == null) return;
    SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
  }
}
