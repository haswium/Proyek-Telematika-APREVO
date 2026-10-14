import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../widgets/playful.dart';
import 'auth_flow.dart';

/// Tab Profil, dipakai guru dan siswa: nama, email, peran, dan tombol keluar.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

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
                  Text('Email', style: AppType.bodySmall),
                  Text(
                    email.isEmpty ? 'Belum ada email' : email,
                    style: AppType.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text('Penyimpanan akun', style: AppType.bodySmall),
                  Text(
                    store.online
                        ? 'Tersimpan di Supabase'
                        : 'Mode demo, hilang saat aplikasi ditutup',
                    style: AppType.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
