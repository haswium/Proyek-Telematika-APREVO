import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/announce.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../../widgets/search_box.dart';
import 'subject_detail_screen.dart';

/// Beranda guru: kartu sambutan, tombol buat kelas, lalu kartu tiap kelas
/// dengan kode aksesnya. Materi dikelola di dalam kelasnya.
class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({super.key});

  void _open(BuildContext context, Subject subject) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: kMaterialListRoute,
        builder: (_) => SubjectDetailScreen(subject: subject),
      ),
    );
  }

  Future<void> _createSubject(BuildContext context) async {
    // Dialog yang mengirim ke backend, supaya error tampil di dalamnya.
    final subject = await showDialog<Subject>(
      context: context,
      builder: (_) => const _NewSubjectDialog(),
    );
    if (subject == null) return;
    final message =
        'Kelas ${subject.name} dibuat. Kode aksesnya '
        '${spellCode(subject.accessCode)}.';
    announce(message);
    if (!context.mounted) return;
    _open(context, subject);
  }

  @override
  Widget build(BuildContext context) {
    final teacher = store.currentUser?.name ?? 'Guru';
    return PurpleScaffold(
      appBar: aprevoAppBar('Kelas Saya'),
      body: SafeArea(
        child: LoadView<List<Subject>>(
          loadingMessage: 'Memuat kelasmu.',
          load: store.teacherSubjects,
          builder: (context, subjects, _) => FilteredList<Subject>(
            items: subjects,
            textOf: (subject) => subject.name,
            label: 'Cari kelas',
            noun: 'kelas',
            builder: (context, visible, searchBox) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Pill(
                        '${subjects.length} kelas',
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
                        'Satu kelas, satu kode akses. Siswa '
                        'bergabung lewat kode itu dan melihat semua materi '
                        'yang sudah dipublikasikan.',
                        style: TextStyle(color: AppColors.white, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Buat Kelas',
                  icon: Icons.add_circle_outline,
                  onPressed: () => _createSubject(context),
                ),
                const SizedBox(height: 8),
                for (final subject in store.unfinishedDeletions)
                  _UnfinishedDeletionCard(
                    key: ValueKey(subject.id),
                    subject: subject,
                  ),
                ?searchBox,
                SectionTitle(
                  'Daftar kelas (${countLabel(visible.length, subjects.length)})',
                ),
                if (subjects.isEmpty)
                  const EmptyState(message: 'Belum ada kelas.'),
                for (var i = 0; i < visible.length; i++)
                  Padding(
                    key: ValueKey(visible[i].id),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 60 * (i > 5 ? 5 : i)),
                      child: _SubjectCard(
                        subject: visible[i],
                        onOpen: () => _open(context, visible[i]),
                      ),
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

/// Dialog nama kelas baru. Membuat kelas di backend lalu
/// mengembalikannya, atau `null` kalau dibatalkan.
class _NewSubjectDialog extends StatefulWidget {
  const _NewSubjectDialog();

  @override
  State<_NewSubjectDialog> createState() => _NewSubjectDialogState();
}

class _NewSubjectDialogState extends State<_NewSubjectDialog> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  int _errorSerial = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _busy = false;
      _error = message;
      _errorSerial++;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showError('Nama kelas belum diisi.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    announce('Membuat kelas $name.');
    try {
      // Kode akses dibuat otomatis oleh backend.
      final subject = await store.createSubject(name);
      if (!mounted) return;
      Navigator.pop(context, subject);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Gagal membuat kelas. ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kelas baru'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: fieldDecoration(
                'Nama kelas',
                hint: 'Contoh: 7A Geografi',
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Membuat...' : 'Buat'),
        ),
      ],
    );
  }
}

/// Penghapusan kelas yang berhenti di tengah. Sudah dikonfirmasi guru, jadi
/// melanjutkannya tidak perlu dialog lagi.
class _UnfinishedDeletionCard extends StatefulWidget {
  const _UnfinishedDeletionCard({super.key, required this.subject});

  final Subject subject;

  @override
  State<_UnfinishedDeletionCard> createState() =>
      _UnfinishedDeletionCardState();
}

class _UnfinishedDeletionCardState extends State<_UnfinishedDeletionCard> {
  bool _busy = false;
  String? _error;

  Future<void> _resume() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = widget.subject.name;
    try {
      await store.deleteSubject(widget.subject.id);
      announce('Kelas $name dihapus');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.subject.name;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: AppCard(
        color: AppColors.highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              child: Text(
                'Penghapusan kelas $name belum selesai',
                style: AppType.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: Text('Lanjutkan hapus kelas $name'),
              onPressed: _busy ? null : _resume,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(_error!, style: AppType.bodyMedium),
              ),
            ],
          ],
        ),
      ),
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
                child: StatTile(value: '${s.studentCount}', label: 'Siswa'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(value: '${s.materialCount}', label: 'Materi'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Bouncy(
            // Tiap kartu punya tombol ini; sebut namanya supaya TalkBack
            // tidak membaca "Buka kelas" berulang tanpa konteks.
            child: Semantics(
              label: 'Buka kelas ${s.name}',
              button: true,
              onTap: onOpen,
              excludeSemantics: true,
              child: FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Buka kelas'),
                onPressed: onOpen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
