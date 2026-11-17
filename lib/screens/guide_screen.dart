import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../data/guide.dart';
import '../models/models.dart';
import '../services/settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';

/// Panduan singkat per fitur. Tiap fitur punya judul (`header`) supaya bisa
/// dilompati dengan navigasi Judul TalkBack atau tombol H di NVDA. Tiap
/// langkah satu fokus: "Langkah 1 dari 3: ...". Tidak ada bagian yang dilipat,
/// jadi semua langkah langsung terbaca.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final sections = guideFor(role);
    return PurpleScaffold(
      appBar: aprevoAppBar('Panduan ${role.label}'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Panduan APREVO untuk ${role.label.toLowerCase()}',
                style: AppType.headlineMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ada ${sections.length} bagian. Lompat antarjudul untuk memilih '
              'bagian.',
              style: AppType.bodyMedium,
            ),
            for (final section in sections) ...[
              const SizedBox(height: 20),
              SectionTitle(section.title),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < section.steps.length; i++)
                      Semantics(
                        container: true,
                        label:
                            'Langkah ${i + 1} dari ${section.steps.length}: '
                            '${section.steps[i]}',
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${i + 1}.',
                                  style: AppType.titleMedium,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  section.steps[i],
                                  style: AppType.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Selesai membaca panduan',
              icon: Icons.check,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

void openGuide(BuildContext context, UserRole role) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => GuideScreen(role: role)),
  );
}

/// Menawarkan panduan sekali per akun di perangkat ini, saat pertama kali
/// sampai di beranda. Dialog dibuka setelah layar beranda tampil, supaya
/// TalkBack membaca judul dialog, bukan judul beranda.
Future<void> offerGuideOnce(BuildContext context) async {
  final account = store.currentUser;
  if (!Settings.offerGuide || account == null) return;
  if (Settings.guideOffered(account.email)) return;
  await Settings.markGuideOffered(account.email);
  if (!context.mounted) return;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Mau membaca panduan dulu?'),
      semanticLabel: 'Mau membaca panduan dulu?',
      content: const Text(
        'Panduan berisi langkah singkat memakai setiap fitur. Panduan juga '
        'bisa dibuka kapan saja dari Profil.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nanti saja'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Buka panduan'),
        ),
      ],
    ),
  );
  if (open == true && context.mounted) openGuide(context, account.role);
}
