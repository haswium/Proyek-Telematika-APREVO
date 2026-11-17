import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Alamat kembali ke aplikasi Android setelah login Google. Harus sama dengan
/// intent-filter di `AndroidManifest.xml` dan Redirect URLs di dashboard Supabase
/// (lihat `docs/deploy.md`).
const String kAuthRedirectUrl = 'id.aprevo.app://login-callback';

/// Alamat kembali untuk versi web: halaman yang sedang dibuka, tanpa query dan
/// fragmen. Contoh `https://haswium.github.io/Proyek-Telematika-APREVO/#/`
/// menjadi `https://haswium.github.io/Proyek-Telematika-APREVO/`. Setelah
/// kembali, `Supabase.initialize` menukar kode login sebelum aplikasi tampil,
/// jadi layar pembuka langsung menemukan sesinya.
String webRedirectUrl(Uri page) => Uri(
  scheme: page.scheme,
  host: page.host,
  port: page.port,
  path: page.path,
).toString();

/// Alamat kembali sesuai platform.
String authRedirectUrl() =>
    kIsWeb ? webRedirectUrl(Uri.base) : kAuthRedirectUrl;

/// Login Google lewat Supabase. Diganti tiruan di tes.
class GoogleAuth {
  const GoogleAuth();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Membuka halaman login Google. `false` kalau browser tidak bisa dibuka.
  Future<bool> open() => _auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: authRedirectUrl(),
  );

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
