import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Guru melihat siswa di kelasnya dan bisa mengeluarkan siswa. Tiap baris satu
/// fokus TalkBack, lalu tombol "Keluarkan" sebagai fokus sendiri.
class SubjectMembersScreen extends StatefulWidget {
  const SubjectMembersScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<SubjectMembersScreen> createState() => _SubjectMembersScreenState();
}

class _SubjectMembersScreenState extends State<SubjectMembersScreen> {
  bool _announced = false;
  bool _removing = false;
  String? _feedback;

  /// Jumlah siswa diumumkan sekali, tidak diulang saat data dimuat ulang.
  void _announceCount(int count) {
    if (_announced) return;
    _announced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        announce('Anggota kelas ${widget.subject.name}: $count siswa');
      }
    });
  }

  Future<void> _remove(SubjectMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _RemoveMemberDialog(member: member),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _removing = true;
      _feedback = null;
    });
    String message;
    try {
      final left = await store.removeSubjectMember(
        widget.subject.id,
        member.id,
      );
      message = '${member.name} dikeluarkan dari kelas. Sisa $left siswa.';
    } on ApiException catch (e) {
      message = e.message;
    }
    if (!mounted) return;
    setState(() {
      _removing = false;
      _feedback = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Anggota kelas'),
      body: SafeArea(
        child: LoadView<List<SubjectMember>>(
          loadingMessage: 'Memuat anggota ${widget.subject.name}.',
          load: () => store.subjectMembers(widget.subject.id),
          builder: (context, members, _) {
            _announceCount(members.length);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    widget.subject.name,
                    style: AppType.headlineMedium,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${members.length} siswa', style: AppType.titleMedium),
                if (_feedback != null) ...[
                  const SizedBox(height: 12),
                  // Tombol yang difokus ikut hilang bersama barisnya, jadi
                  // hasilnya harus dibacakan.
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text(_feedback!, style: AppType.bodyMedium),
                  ),
                ],
                const SizedBox(height: 16),
                if (members.isEmpty)
                  const EmptyState(message: 'Belum ada siswa di kelas ini.'),
                for (final member in members) ...[
                  ListRow(
                    icon: Icons.person_outline,
                    title: member.name,
                    subtitle: [member.emailText, ?member.joinedText].join('\n'),
                    semanticLabel: member.label,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_remove_outlined),
                      label: Text('Keluarkan ${member.name}'),
                      onPressed: _removing ? null : () => _remove(member),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Langkah kedua sebelum siswa dikeluarkan.
class _RemoveMemberDialog extends StatelessWidget {
  const _RemoveMemberDialog({required this.member});

  final SubjectMember member;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(kTouchTarget, kTouchTarget),
    );
    return AlertDialog(
      title: Text('Keluarkan ${member.name} dari kelas?'),
      content: Text(
        '${member.name} tidak bisa lagi membuka materi kelas ini. Nilainya '
        'tetap tersimpan. ${member.name} bisa bergabung lagi dengan kode '
        'akses, dan nilainya muncul kembali.',
        style: AppType.bodyMedium,
      ),
      actions: [
        TextButton(
          style: buttonStyle,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        TextButton(
          style: buttonStyle,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Ya, keluarkan'),
        ),
      ],
    );
  }
}
