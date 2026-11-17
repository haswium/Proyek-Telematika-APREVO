import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Pengaturan yang disimpan di perangkat: alamat server, siswa yang sudah
/// melihat layar sambutan, efek bunyi, dan akun yang sudah ditawari panduan.
///
/// [load] dipanggil sekali di `main()`. Widget test tidak menjalankan
/// `main()`, jadi di tes nilainya bawaan dan tidak ada yang disimpan.
class Settings {
  Settings._();

  static const String _baseUrlKey = 'api_base_url';
  static const String _onboardedKey = 'onboarded_emails';
  static const String _soundKey = 'sound_effects';
  static const String _guideKey = 'guide_offered_emails';

  static SharedPreferences? _prefs;

  static String? _savedBaseUrl;
  static final Set<String> _onboarded = {};
  static bool _soundEffects = true;
  static final Set<String> _guideOffered = {};

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _savedBaseUrl = prefs.getString(_baseUrlKey);
      _onboarded.addAll(prefs.getStringList(_onboardedKey) ?? const []);
      _soundEffects = prefs.getBool(_soundKey) ?? true;
      _guideOffered.addAll(prefs.getStringList(_guideKey) ?? const []);
    } catch (_) {
      // Penyimpanan tidak tersedia: pakai nilai bawaan.
    }
  }

  /// Alamat backend yang dipakai sekarang.
  static String get baseUrl => _savedBaseUrl ?? ApiConfig.defaultBaseUrl;

  /// `true` kalau pengguna mengganti alamat bawaan.
  static bool get hasCustomBaseUrl => _savedBaseUrl != null;

  /// [url] `null` mengembalikan alamat bawaan.
  static Future<void> setBaseUrl(String? url) async {
    _savedBaseUrl = url;
    try {
      if (url == null) {
        await _prefs?.remove(_baseUrlKey);
      } else {
        await _prefs?.setString(_baseUrlKey, url);
      }
    } catch (_) {}
  }

  static bool isOnboarded(String email) => _onboarded.contains(email);

  static Future<void> markOnboarded(String email) async {
    _onboarded.add(email);
    try {
      await _prefs?.setStringList(_onboardedKey, _onboarded.toList());
    } catch (_) {}
  }

  /// Bunyi pendek saat jawaban benar atau salah. Menyala secara bawaan,
  /// bisa dimatikan di Profil.
  static bool get soundEffects => _soundEffects;

  static Future<void> setSoundEffects(bool on) async {
    _soundEffects = on;
    try {
      await _prefs?.setBool(_soundKey, on);
    } catch (_) {}
  }

  /// `false` mematikan tawaran panduan. Tes mematikannya (lihat
  /// `test/flutter_test_config.dart`), kecuali tes panduan sendiri.
  static bool offerGuide = true;

  /// Panduan ditawarkan sekali per akun di perangkat ini.
  static bool guideOffered(String email) => _guideOffered.contains(email);

  static Future<void> markGuideOffered(String email) async {
    _guideOffered.add(email);
    try {
      await _prefs?.setStringList(_guideKey, _guideOffered.toList());
    } catch (_) {}
  }

  /// Mengembalikan nilai bawaan di antara tes.
  @visibleForTesting
  static void reset() {
    _savedBaseUrl = null;
    _onboarded.clear();
    _soundEffects = true;
    _guideOffered.clear();
  }
}
