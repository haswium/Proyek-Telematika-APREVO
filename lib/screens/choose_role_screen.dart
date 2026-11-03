import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../services/announce.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'auth_flow.dart';

/// Akun Google yang baru pertama kali masuk memilih peran di sini.
class ChooseRoleScreen extends StatefulWidget {
  const ChooseRoleScreen({super.key});

  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen> {
  bool _busy = false;
  String? _error;
  int _errorSerial = 0;

  Future<void> _choose(UserRole role) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await store.chooseRole(role);
      if (!mounted) return;
      // Peran yang sudah tersimpan tidak berubah, walaupun yang dipilih berbeda.
      if (account.role != role) {
        announce('Akun ini sudah terdaftar sebagai ${account.role.label}');
      }
      goHome(context, account);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _errorSerial++;
      });
    }
  }

  Widget _roleButton(UserRole role, String description) {
    final onTap = _busy ? null : () => _choose(role);
    return Semantics(
      label:
          '${role.label}. $description Peran tidak bisa diganti setelah '
          'dipilih.',
      button: true,
      enabled: !_busy,
      onTap: onTap,
      excludeSemantics: true,
      child: PrimaryButton(label: role.label, onPressed: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Semantics(
              header: true,
              child: Text('Pilih peran', style: AppType.headlineMedium),
            ),
            const SizedBox(height: 12),
            Text(
              'Peran tidak bisa diganti setelah dipilih.',
              style: AppType.bodyLarge,
            ),
            const SizedBox(height: 28),
            _roleButton(
              UserRole.teacher,
              'Membuat kelas, memberi materi dan kuis.',
            ),
            const SizedBox(height: 16),
            _roleButton(
              UserRole.student,
              'Bergabung ke kelas, membaca materi, dan mengerjakan kuis.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
            ],
            const SizedBox(height: 20),
            TextButton(
              onPressed: _busy ? null : () => logout(context),
              child: const Text('Batal dan keluar'),
            ),
          ],
        ),
      ),
    );
  }
}
