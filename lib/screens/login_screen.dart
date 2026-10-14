import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'auth_flow.dart';
import 'register_screen.dart';

/// Layar masuk. Satu form untuk guru dan siswa; perannya diambil dari akun.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _error = message);
    Speech.announce(message);
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
    setState(() {
      _busy = true;
      _error = null;
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

  /// Fitur yang butuh Supabase Auth dan belum tersambung.
  void _notYet(String feature) {
    final message = '$feature akan aktif setelah aplikasi tersambung ke '
        'Supabase.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    Speech.announce(message);
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _notYet('Lupa password'),
                      child: const Text('Lupa password?'),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              ErrorCard(message: _error!),
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
                      onPressed: () => _notYet('Masuk dengan Google'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterScreen(),
                      ),
                    ),
                    child: const Text('Belum punya akun? Daftar sekarang'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
