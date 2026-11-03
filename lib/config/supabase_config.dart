/// Sambungan ke Supabase.
///
/// Nilainya diberikan saat build lewat
/// `--dart-define-from-file=config/app_env.json`. File itu tidak di-commit, dan
/// contohnya ada di `config/app_env.example.json` (lihat `docs/deploy.md`).
///
/// Yang boleh diisi HANYA kunci `anon` (public). Kunci `service_role` tidak boleh
/// masuk ke aplikasi; itu hanya untuk backend.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// `false` kalau file di atas tidak diberikan. Saat pengembangan aplikasi tetap
  /// terbuka, tetapi tidak bisa masuk atau daftar. Build release menolak keadaan
  /// ini, lihat `android/app/build.gradle.kts`.
  static bool get isConfigured =>
      url.startsWith('https://') && anonKey.startsWith('eyJ');
}
