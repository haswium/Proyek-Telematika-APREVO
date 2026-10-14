/// Alamat backend FastAPI (folder `backend/`).
///
/// Bawaannya untuk `flutter run -d chrome` di laptop yang sama dengan
/// backend. Untuk perangkat lain, ganti tanpa mengubah kode:
///
/// ```bash
/// # emulator Android (10.0.2.2 = localhost laptop)
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// ```
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Batas waktu tiap permintaan sebelum dianggap gagal.
  static const Duration timeout = Duration(seconds: 15);
}
