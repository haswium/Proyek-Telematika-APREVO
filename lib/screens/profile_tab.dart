import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../services/settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../widgets/playful.dart';
import 'auth_flow.dart';
import 'guide_screen.dart';
import 'server_settings_screen.dart';

/// Tab Profil, dipakai guru dan siswa: nama, email, peran, panduan, efek
/// bunyi, dan tombol keluar.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  // Status saklar ("aktif"/"nonaktif") sudah dibacakan TalkBack sendiri.
  void _setSound(bool on) {
    Settings.setSoundEffects(on);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = store.currentUser;
    final name = user?.name ?? 'Pengguna';
    final email = user?.email ?? '';
    final role = user?.role ?? UserRole.student;
    return PurpleScaffold(
      appBar: aprevoAppBar('Profil'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: Mascot(size: 140)),
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: AppType.headlineMedium,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Pill(
                role.label,
                icon: role == UserRole.teacher
                    ? Icons.school_outlined
                    : Icons.headphones,
                color: AppColors.accent,
                textColor: AppColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Judul kecil dan isinya dibaca sebagai satu: "Email, ...".
                  MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Email', style: AppType.bodySmall),
                        Text(
                          email.isEmpty ? 'Belum ada email' : email,
                          style: AppType.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ListRow(
              icon: Icons.menu_book_outlined,
              title: 'Panduan',
              subtitle: 'Buku langkah demi langkah untuk setiap fitur',
              onTap: () => openGuide(context, role),
            ),
            // Untuk guru dan siswa: bunyi membalik halaman panduan dipakai
            // keduanya, bunyi benar dan salah hanya di kuis siswa.
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: Settings.soundEffects,
                  onChanged: _setSound,
                  title: Text('Efek bunyi', style: AppType.titleMedium),
                  subtitle: Text(
                    role == UserRole.student
                        ? 'Bunyi pendek setelah menjawab soal dan saat '
                              'membalik halaman panduan. Pengumuman TalkBack '
                              'tetap ada.'
                        : 'Bunyi pendek saat membalik halaman panduan. '
                              'Pengumuman TalkBack tetap ada.',
                    style: AppType.bodySmall,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const AboutAprevoRow(),
            const SizedBox(height: 8),
            Bouncy(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Keluar dari akun'),
                onPressed: () => logout(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
