/// Alamat backend FastAPI.
///
/// Urutan sumbernya:
/// 1. Alamat yang disimpan di menu pengembang (lihat `services/settings.dart`).
/// 2. `--dart-define=API_BASE_URL=http://192.168.1.7:8000` saat build, untuk
///    backend di laptop. Dari emulator Android, alamat laptop adalah `10.0.2.2`.
/// 3. Bawaan: [productionBaseUrl], jadi siswa tidak perlu mengisi apa pun.
class ApiConfig {
  ApiConfig._();

  /// Alamat backend di Render. Ganti dengan alamat yang tampil di dashboard
  /// setelah layanannya dibuat (lihat `docs/deploy.md`).
  static const String productionBaseUrl = 'https://proyek-telematika-aprevo.onrender.com';

  static const String _fromDefine = String.fromEnvironment('API_BASE_URL');

  static const int defaultPort = 8000;

  static String get defaultBaseUrl {
    if (_fromDefine.isNotEmpty) return normalize(_fromDefine) ?? _fromDefine;
    return productionBaseUrl;
  }

  /// Merapikan ketikan alamat. "192.168.1.7" menjadi
  /// "http://192.168.1.7:8000", dan "aprevo.onrender.com" menjadi
  /// "https://aprevo.onrender.com". Kalau skema tidak diketik, alamat lokal
  /// dianggap http dengan port 8000, nama domain dianggap https. Garis miring di
  /// akhir dibuang.
  /// Mengembalikan `null` kalau alamatnya tidak bisa dipakai.
  static String? normalize(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    final typedScheme = text.contains('://');
    if (!typedScheme) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final isLocal =
        !uri.host.contains('.') ||
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(uri.host);
    final Uri complete;
    if (typedScheme) {
      complete = uri;
    } else if (!isLocal) {
      complete = uri.replace(scheme: 'https');
    } else {
      complete = uri.hasPort ? uri : uri.replace(port: defaultPort);
    }
    var result = complete.toString();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
