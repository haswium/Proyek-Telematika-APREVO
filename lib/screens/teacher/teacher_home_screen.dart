import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';
import 'subject_detail_screen.dart';

/// Beranda guru: kartu sambutan, tombol buat mata pelajaran, lalu kartu
/// tiap mata pelajaran dengan kode aksesnya. Materi dikelola di dalam
/// mata pelajarannya.
class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({super.key});

  void _open(BuildContext context, Subject subject) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubjectDetailScreen(subject: subject),
      ),
    );
  }

  Future<void> _createSubject(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewSubjectDialog(),
    );
    if (name == null) return;
    // Kode akses mata pelajaran dibuat otomatis di dalam createSubject.
    final subject = store.createSubject(name);
    Speech.announce('Mata pelajaran ${subject.name} dibuat.');
    if (!context.mounted) return;
    _open(context, subject);
  }

  @override
  Widget build(BuildContext context) {
    final teacher = store.currentUser?.name ?? 'Guru';
    return PurpleScaffold(
      appBar: aprevoAppBar('Mata Pelajaran Saya'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final subjects = store.subjects;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Pill(
                        '${subjects.length} mata pelajaran',
                        color: const Color(0x33FFFFFF),
                        textColor: AppColors.white,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Selamat datang kembali',
                        style: TextStyle(color: AppColors.white, fontSize: 15),
                      ),
                      Semantics(
                        header: true,
                        child: Text(
                          teacher,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Satu mata pelajaran, satu kode akses. Siswa '
                        'bergabung lewat kode itu dan melihat semua materi '
                        'yang sudah dipublikasikan.',
                        style: TextStyle(color: AppColors.white, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Buat Mata Pelajaran',
                  icon: Icons.add_circle_outline,
                  onPressed: () => _createSubject(context),
                ),
                const SizedBox(height: 8),
                SectionTitle('Daftar mata pelajaran (${subjects.length})'),
                if (subjects.isEmpty)
                  const EmptyState(message: 'Belum ada mata pelajaran.'),
                for (var i = 0; i < subjects.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 60 * (i > 5 ? 5 : i)),
                      child: _SubjectCard(
                        subject: subjects[i],
                        onOpen: () => _open(context, subjects[i]),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dialog nama mata pelajaran baru. Mengembalikan nama yang sudah dirapikan,
/// atau `null` kalau dibatalkan.
class _NewSubjectDialog extends StatefulWidget {
  const _NewSubjectDialog();

  @override
  State<_NewSubjectDialog> createState() => _NewSubjectDialogState();
}

class _NewSubjectDialogState extends State<_NewSubjectDialog> {
  final _name = TextEditingController();
  String? _error;
  int _errorSerial = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      const message = 'Nama mata pelajaran belum diisi.';
      setState(() {
        _error = message;
        _errorSerial++;
      });
      Speech.feedback(context, message);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mata pelajaran baru'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: fieldDecoration(
                'Nama mata pelajaran',
                hint: 'Contoh: IPA Kelas 5',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(onPressed: _submit, child: const Text('Buat')),
      ],
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject, required this.onOpen});

  final Subject subject;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = subject;
    final published = store.publishedMaterials(s).length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(s.name, style: AppType.titleLarge),
          ),
          const SizedBox(height: 10),
          CodeBox(code: s.accessCode),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(value: '${s.students.length}', label: 'Siswa'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '${s.materials.length}',
                  label: 'Materi',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(value: '$published', label: 'Materi publik'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Bouncy(
            // Tiap kartu punya tombol ini; sebut namanya supaya TalkBack
            // tidak membaca "Buka mata pelajaran" berulang tanpa konteks.
            child: Semantics(
              label: 'Buka mata pelajaran ${s.name}',
              button: true,
              onTap: onOpen,
              excludeSemantics: true,
              child: FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Buka mata pelajaran'),
                onPressed: onOpen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
