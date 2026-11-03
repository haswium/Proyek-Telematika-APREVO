import 'package:supabase_flutter/supabase_flutter.dart';

/// Alamat kembali ke aplikasi setelah login Google. Harus sama dengan
/// intent-filter di `AndroidManifest.xml` dan Redirect URLs di dashboard Supabase
/// (lihat `docs/deploy.md`).
const String kAuthRedirectUrl = 'id.aprevo.app://login-callback';

/// Login Google lewat Supabase. Diganti tiruan di tes.
class GoogleAuth {
  const GoogleAuth();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Membuka halaman login Google. `false` kalau browser tidak bisa dibuka.
  Future<bool> open() =>
      _auth.signInWithOAuth(OAuthProvider.google, redirectTo: kAuthRedirectUrl);

  /// Akun yang berhasil masuk. Kegagalan dari Google datang sebagai error.
  Stream<User> get signedIn => _auth.onAuthStateChange
      .where(
        (state) =>
            state.event == AuthChangeEvent.signedIn && state.session != null,
      )
      .map((state) => state.session!.user);

  /// Menyimpan nama dan peran ke metadata akun.
  Future<User> saveProfile({required String name, required String role}) async {
    final response = await _auth.updateUser(
      UserAttributes(data: {'name': name, 'role': role}),
    );
    return response.user!;
  }
}
