/// Sambungan ke Supabase.
///
/// Yang boleh ditaruh di sini HANYA kunci `anon` (public). Kunci
/// `service_role` tidak boleh masuk ke aplikasi; itu hanya untuk backend.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://jlyvuhcwzshpwgwgfaer.supabase.co';

  /// Tempel kunci `anon` `public` dari dashboard Supabase
  /// (Settings > API Keys) di antara tanda kutip ini.
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpseXZ1aGN3enNocHdnd2dmYWVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA1NzU2NjAsImV4cCI6MjEwNjE1MTY2MH0.vVCFETC0nJiYfPtn2rN2eIgVLv73iS8dNhPTFhYMdho';

  /// `false` selama kunci belum diisi. Aplikasi lalu berjalan dalam mode
  /// demo: akun contoh di memori, tanpa internet.
  static bool get isConfigured => anonKey.startsWith('eyJ');
}
