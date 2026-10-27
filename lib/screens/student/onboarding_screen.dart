import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';
import 'student_shell.dart';

/// Sambutan untuk siswa setelah masuk pertama kali.
///
/// Di Figma ada titik-titik halaman, tetapi di sini dibuat satu layar saja:
/// menggeser halaman dengan TalkBack lebih sulit daripada membaca ke bawah.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.studentName});

  final String studentName;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<String> _points = [
    'Gunakan TalkBack, pembaca layar di HP-mu',
    'Semua materi bisa dibaca dengan TalkBack',
    'Mudah, aman, dan inklusif',
  ];

  void _start() {
    final user = store.currentUser;
    if (user != null) store.markOnboarded(user);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StudentShell(studentName: widget.studentName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  Center(
                    child: FadeSlideIn(
                      child: PulseRings(
                        size: 170,
                        color: AppColors.lilac,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 104,
                              height: 104,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.headphones,
                                size: 52,
                                color: AppColors.white,
                              ),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.music_note,
                                  size: 18,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 120),
                    child: Column(
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Siap untuk belajar?',
                            textAlign: TextAlign.center,
                            style: AppType.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'APREVO telah disesuaikan untuk kemudahan '
                          'belajarmu.',
                          textAlign: TextAlign.center,
                          style: AppType.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  for (var i = 0; i < _points.length; i++)
                    FadeSlideIn(
                      delay: Duration(milliseconds: 240 + i * 120),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            const ExcludeSemantics(
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.lilac,
                                child: Icon(
                                  Icons.check,
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(_points[i], style: AppType.bodyLarge),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: PrimaryButton(label: 'Mulai Belajar', onPressed: _start),
            ),
          ],
        ),
      ),
    );
  }
}
