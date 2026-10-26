import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Pengaturan yang disimpan di perangkat: alamat server dan siswa yang
/// sudah melihat layar sambutan.
///
/// [load] dipanggil sekali di `main()`. Widget test tidak menjalankan
/// `main()`, jadi di tes nilainya bawaan dan tidak ada yang disimpan.
class Settings {
  Settings._();

  static const String _baseUrlKey = 'api_base_url';
  static const String _onboardedKey = 'onboarded_emails';

  static SharedPreferences? _prefs;

  static String? _savedBaseUrl;
  static final Set<String> _onboarded = {};

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _savedBaseUrl = prefs.getString(_baseUrlKey);
      _onboarded.addAll(prefs.getStringList(_onboardedKey) ?? const []);
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
}
