import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/app_theme.dart';
import '../widgets/playful.dart';
import 'auth_flow.dart';
import 'welcome_screen.dart';

/// Layar pembuka: latar ungu, logo gelombang suara, lalu pindah sendiri
/// ke layar sambutan. Bisa diketuk untuk langsung lanjut.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_left || !mounted) return;
    _left = true;
    // Kalau masih masuk dari sebelumnya, langsung ke beranda.
    final user = store.restoreSession();
    if (user != null) {
      goHome(context, user);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _goNext,
        child: OceanBackground(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FadeSlideIn(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const PulseRings(
                            size: 190,
                            color: Color(0x14FFFFFF),
                            child: SoundWaveLogo(height: 84, onDark: true),
                          ),
                          const SizedBox(height: 12),
                          Semantics(
                            header: true,
                            child: const Text(
                              'APREVO',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Belajar lebih mudah,\nsatu suara.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 18,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Text(
                    'Audio-first Inclusive Learning',
                    style: TextStyle(color: AppColors.white, fontSize: 14),
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
