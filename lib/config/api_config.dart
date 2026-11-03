import 'package:flutter/foundation.dart';

/// Alamat backend FastAPI.
///
/// Urutan sumbernya:
/// 1. Alamat yang disimpan pengguna di layar "Alamat server" (lihat
///    `services/settings.dart`).
/// 2. `--dart-define=API_BASE_URL=http://192.168.1.7:8000` saat build.
/// 3. Bawaan: `localhost` di web dan desktop, `10.0.2.2` (alamat laptop dari
///    emulator Android) di Android.
///
/// Dari HP sungguhan, isi alamat IP laptop di jaringan Wi-Fi yang sama, dan
/// jalankan backend dengan `--host 0.0.0.0`.
class ApiConfig {
  ApiConfig._();

  static const String _fromDefine = String.fromEnvironment('API_BASE_URL');

  static const int defaultPort = 8000;

  static String get defaultBaseUrl {
    if (_fromDefine.isNotEmpty) return normalize(_fromDefine) ?? _fromDefine;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$defaultPort';
    }
    return 'http://localhost:$defaultPort';
  }

  /// Merapikan ketikan alamat. "192.168.1.7" menjadi
  /// "http://192.168.1.7:8000". Kalau skema tidak diketik, dianggap http dan
  /// port bawaan 8000 ditambahkan. Garis miring di akhir dibuang.
  /// Mengembalikan `null` kalau alamatnya tidak bisa dipakai.
  static String? normalize(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    final typedScheme = text.contains('://');
    if (!typedScheme) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final withPort = !typedScheme && !uri.hasPort
        ? uri.replace(port: defaultPort)
        : uri;
    var result = withPort.toString();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
