import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'auth_flow.dart';
import 'login_screen.dart';

/// Layar daftar. Peran (siswa atau guru) dipilih di sini, sekali saja.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.student;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
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
    if (_name.text.trim().isEmpty) {
      _showError('Nama belum diisi.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showError('Email belum benar. Contoh: nama@email.com');
      return;
    }
    if (_password.text.length < 6) {
      _showError('Password minimal 6 karakter.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await store.register(
      name: _name.text,
      email: email,
      password: _password.text,
      role: _role,
    );
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
            const FadeSlideIn(child: AuthHeader(title: 'Daftar')),
            const SizedBox(height: 24),
            FadeSlideIn(
              delay: const Duration(milliseconds: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ExcludeSemantics(
                    child: Text(
                      'Saya adalah',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _RoleCard(
                          role: UserRole.student,
                          icon: Icons.headphones,
                          selected: _role == UserRole.student,
                          onTap: () =>
                              setState(() => _role = UserRole.student),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RoleCard(
                          role: UserRole.teacher,
                          icon: Icons.school_outlined,
                          selected: _role == UserRole.teacher,
                          onTap: () =>
                              setState(() => _role = UserRole.teacher),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Nama',
                    hint: 'Nama lengkap',
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Email',
                    hint: 'contoh@email.com',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Password',
                    hint: 'Minimal 6 karakter',
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
            const SizedBox(height: 20),
            if (_error != null) ...[
              ErrorCard(message: _error!),
              const SizedBox(height: 16),
            ],
            PrimaryButton(
              label: _busy ? 'Membuat akun...' : 'Daftar',
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text('Sudah punya akun? Masuk'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pilihan peran. Dibaca TalkBack sebagai satu tombol: "Siswa, dipilih".
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const foreground = AppColors.ink;
    return Semantics(
      label: role.label,
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: Bouncy(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.ink,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.ink),
                const SizedBox(width: 8),
                Text(
                  role.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
