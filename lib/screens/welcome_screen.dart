import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Layar sambutan: logo, penjelasan singkat, tombol Masuk dan Daftar.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const FadeSlideIn(child: SoundWaveLogo(height: 88, onDark: true)),
                const SizedBox(height: 20),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: Column(
                    children: [
                      Semantics(
                        header: true,
                        child: const Text(
                          'APREVO',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Belajar lebih mudah,\nsatu suara.',
                        textAlign: TextAlign.center,
                        style: AppType.titleLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: AppCard(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Media pembelajaran interaktif yang dirancang khusus '
                      'untuk pengalaman belajar audio-first yang ramah bagi '
                      'semua kalangan.',
                      textAlign: TextAlign.center,
                      style: AppType.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: Column(
                    children: [
                      PrimaryButton(
                        label: 'Masuk',
                        onPressed: () => _push(context, const LoginScreen()),
                      ),
                      const SizedBox(height: 12),
                      Bouncy(
                        child: OutlinedButton(
                          onPressed: () =>
                              _push(context, const RegisterScreen()),
                          child: const Text('Daftar'),
                        ),
                      ),
                    ],
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
