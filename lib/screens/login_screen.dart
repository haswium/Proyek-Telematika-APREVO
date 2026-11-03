import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../data/app_store.dart';
import '../services/announce.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'auth_flow.dart';
import 'register_screen.dart';
import 'server_settings_screen.dart';

/// Jeda setelah kembali dari browser, memberi waktu tautan login diproses. Kalau
/// belum ada hasil, login dianggap dibatalkan. Hasil yang datang lebih lambat
/// tetap diterima.
const Duration kGoogleReturnGrace = Duration(seconds: 5);

/// Layar masuk. Satu form untuk guru dan siswa; perannya diambil dari akun.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  int _errorSerial = 0;

  /// Login Google dimulai dari layar ini.
  bool _googleStarted = false;

  /// Sudah pindah ke browser dan belum kembali.
  bool _inBrowser = false;
  bool _openingGoogle = false;
  String? _googleStatus;
  Timer? _returnTimer;
  StreamSubscription<Object>? _googleResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (store.online) {
      _googleResult = store.googleSignedIn.listen(
        _googleSignedIn,
        onError: _googleFailed,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_googleStarted) return;
    if (state == AppLifecycleState.paused) {
      _inBrowser = true;
      _returnTimer?.cancel();
    } else if (state == AppLifecycleState.resumed && _inBrowser) {
      _inBrowser = false;
      _returnTimer?.cancel();
      _returnTimer = Timer(kGoogleReturnGrace, _googleCancelled);
    }
  }

  Future<void> _startGoogle() async {
    if (!store.online) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Masuk dengan Google akan aktif setelah aplikasi tersambung ke '
              'Supabase.',
            ),
          ),
        );
      return;
    }
    if (_openingGoogle) return;
    _returnTimer?.cancel();
    setState(() {
      _openingGoogle = true;
      _googleStarted = true;
      _googleStatus = null;
      _error = null;
    });
    announce('Membuka halaman login Google');
    var opened = false;
    try {
      opened = await store.googleAuth.open();
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _openingGoogle = false);
    if (!opened) {
      _googleStarted = false;
      _showError('Halaman login Google tidak bisa dibuka. Coba lagi.');
    }
  }

  void _googleSignedIn(Object account) {
    if (!_googleStarted || !mounted) return;
    _returnTimer?.cancel();
    _googleStarted = false;
    announce('Berhasil masuk');
    goHome(context, store.currentUser!);
  }

  void _googleCancelled() {
    if (!mounted) return;
    setState(() => _googleStatus = 'Login Google dibatalkan');
    announce('Login Google dibatalkan');
  }

  void _googleFailed(Object error) {
    if (!_googleStarted || !mounted) return;
    _returnTimer?.cancel();
    _googleStarted = false;
    final denied =
        error is AuthException &&
        '${error.code} ${error.message}'.contains('access_denied');
    if (denied) {
      _googleCancelled();
    } else {
      _showError('Login Google gagal. Coba lagi.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _returnTimer?.cancel();
    _googleResult?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _error = message;
      _errorSerial++;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      _showError('Email belum benar. Contoh: nama@email.com');
      return;
    }
    if (_password.text.isEmpty) {
      _showError('Password belum diisi.');
      return;
    }
    _googleStarted = false;
    _returnTimer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _googleStatus = null;
    });
    final error = await store.signIn(email: email, password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _showError(error);
      return;
    }
    goHome(context, store.currentUser!);
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: plainAppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const FadeSlideIn(child: AuthHeader(title: 'Masuk')),
            const SizedBox(height: 28),
            FadeSlideIn(
              delay: const Duration(milliseconds: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledField(
                    label: 'Email',
                    hint: 'contoh@email.com',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Password',
                    hint: 'Masukkan password',
                    controller: _password,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    suffixIcon: PasswordToggle(
                      visible: _showPassword,
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
              const SizedBox(height: 16),
            ],
            FadeSlideIn(
              delay: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _busy ? 'Sedang masuk...' : 'Masuk',
                    onPressed: _busy ? null : _submit,
                  ),
                  const SizedBox(height: 16),
                  ExcludeSemantics(
                    child: Text('atau', style: AppType.bodySmall),
                  ),
                  const SizedBox(height: 16),
                  Bouncy(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 1.5,
                        ),
                      ),
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Masuk dengan Google'),
                      onPressed: _startGoogle,
                    ),
                  ),
                  // Sudah diumumkan, jadi hanya untuk yang melihat layar.
                  if (_googleStatus != null) ...[
                    const SizedBox(height: 12),
                    ExcludeSemantics(
                      child: Text(_googleStatus!, style: AppType.bodySmall),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text('Belum punya akun? Daftar sekarang'),
                  ),
                  const SizedBox(height: 12),
                  const AboutAprevoRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
