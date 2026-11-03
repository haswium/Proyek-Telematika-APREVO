import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../../widgets/search_box.dart';
import 'generate_questions_screen.dart';
import 'material_editor_screen.dart';
import 'material_images_screen.dart';
import 'new_material_screen.dart';
import 'subject_members_screen.dart';

/// Status satu kuis untuk guru, misalnya "Pre-test: dibuka sampai ...".
String quizSummary(LessonMaterial m, TestKind kind) {
  final q = m.quiz(kind);
  if (q == null) return '${kind.label}: belum dibuat';
  return '${kind.label}: ${q.scheduleText.toLowerCase()}';
}

/// Isi satu kelas untuk guru: kode akses untuk dibagikan, tombol
/// buat materi, lalu kartu tiap materi (publik maupun draf).
class SubjectDetailScreen extends StatelessWidget {
  const SubjectDetailScreen({super.key, required this.subject});

  final Subject subject;

  void _open(BuildContext context, LessonMaterial material) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MaterialEditorScreen(subject: subject, material: material),
      ),
    );
  }

  Future<void> _deleteSubject(BuildContext context) async {
    final outcome = await showDialog<_DeleteOutcome>(
      context: context,
      // Tidak tertutup tanpa sengaja selama penghapusan berjalan.
      barrierDismissible: false,
      builder: (_) => _DeleteSubjectDialog(subject: subject),
    );
    if (outcome == null ||
        outcome == _DeleteOutcome.cancelled ||
        !context.mounted) {
      return;
    }
    Navigator.popUntil(context, (route) => route.isFirst);
    // Setelah frame, supaya tidak tertimpa pembacaan layar daftar kelas.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => announce(
        outcome == _DeleteOutcome.deleted
            ? 'Kelas ${subject.name} dihapus'
            : 'Penghapusan kelas ${subject.name} belum selesai. Lanjutkan dari '
                  'daftar kelas.',
      ),
    );
  }

  void _createMaterial(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewMaterialScreen(subject: subject)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar(subject.name),
      body: SafeArea(
        child: LoadView<List<LessonMaterial>>(
          loadingMessage: 'Memuat materi ${subject.name}.',
          load: () => store.teacherMaterials(subject.id),
          builder: (context, materials, _) {
            final published = materials.where((m) => m.published).length;
            return FilteredList<LessonMaterial>(
              items: materials,
              textOf: (material) => material.title,
              label: 'Cari materi',
              noun: 'materi',
              builder: (context, visible, searchBox) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  HeroCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pill(
                          '$published dari ${materials.length} materi publik',
                          color: const Color(0x33FFFFFF),
                          textColor: AppColors.white,
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          header: true,
                          child: Text(
                            subject.name,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Bagikan kode ini ke siswa. Siswa hanya melihat '
                          'materi yang sudah dipublikasikan.',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        CodeBox(code: subject.accessCode, onDark: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Unggah Materi PDF',
                    icon: Icons.add_circle_outline,
                    onPressed: () => _createMaterial(context),
                  ),
                  if (materials.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Buat soal dengan AI'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GenerateQuestionsScreen(subject: subject),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ListRow(
                    icon: Icons.groups_outlined,
                    title: 'Anggota kelas',
                    subtitle: 'Daftar siswa dan jumlahnya',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubjectMembersScreen(subject: subject),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ?searchBox,
                  SectionTitle(
                    'Daftar materi (${countLabel(visible.length, materials.length)})',
                  ),
                  if (materials.isEmpty)
                    const EmptyState(message: 'Belum ada materi di kelas ini.'),
                  for (var i = 0; i < visible.length; i++)
                    Padding(
                      key: ValueKey(visible[i].id),
                      padding: const EdgeInsets.only(bottom: 14),
                      child: FadeSlideIn(
                        delay: Duration(milliseconds: 60 * (i > 5 ? 5 : i)),
                        child: _MaterialCard(
                          material: visible[i],
                          onOpen: () => _open(context, visible[i]),
                        ),
                      ),
                    ),
                  if (materials.isNotEmpty)
                    Text(
                      'Ketuk "Kelola materi" untuk mengatur jadwal, soal, dan '
                      'publikasi.',
                      style: AppType.bodySmall,
                    ),
                  // Paling bawah dan berjarak, supaya tidak tertekan tanpa sengaja.
                  const SizedBox(height: 64),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus kelas'),
                    onPressed: () => _deleteSubject(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _DeleteOutcome {
  cancelled,
  deleted,

  /// Guru menutup dialog setelah penghapusan gagal. Kelas sudah hilang dari
  /// daftar, jadi layarnya tidak bisa dipakai lagi.
  unfinished,
}

/// Langkah kedua sebelum kelas dihapus: menyebut apa saja yang ikut terhapus.
class _DeleteSubjectDialog extends StatefulWidget {
  const _DeleteSubjectDialog({required this.subject});

  final Subject subject;

  @override
  State<_DeleteSubjectDialog> createState() => _DeleteSubjectDialogState();
}

class _DeleteSubjectDialogState extends State<_DeleteSubjectDialog> {
  SubjectDeleteSummary? _summary;
  bool _busy = false;
  bool _attempted = false;
  String? _error;
  int _errorSerial = 0;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await store.subjectDeleteSummary(widget.subject.id);
      if (!mounted) return;
      setState(() => _summary = summary);
      // Fokus awal ada di tombol Batal, jadi peringatannya harus dibacakan.
      announce(summary.warning(widget.subject.name));
    } on ApiException catch (e) {
      _showError(e);
    }
  }

  void _showError(ApiException e) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = e.message;
      _errorSerial++;
    });
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      await store.deleteSubject(widget.subject.id);
      if (mounted) Navigator.pop(context, _DeleteOutcome.deleted);
    } on ApiException catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(kTouchTarget, kTouchTarget),
    );
    return AlertDialog(
      title: Text('Hapus kelas ${widget.subject.name}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary != null)
              Text(
                summary.warning(widget.subject.name),
                style: AppType.bodyMedium,
              )
            else if (_error == null)
              Text('Memuat isi kelas.', style: AppType.bodyMedium),
            if (_busy) ...[
              const SizedBox(height: 12),
              Text('Sedang menghapus kelas.', style: AppType.bodyMedium),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          style: buttonStyle,
          onPressed: _busy
              ? null
              : () => Navigator.pop(
                  context,
                  _attempted
                      ? _DeleteOutcome.unfinished
                      : _DeleteOutcome.cancelled,
                ),
          child: const Text('Batal'),
        ),
        TextButton(
          style: buttonStyle,
          onPressed: _busy || summary == null ? null : _delete,
          child: const Text('Ya, hapus kelas'),
        ),
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material, required this.onOpen});

  final LessonMaterial material;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final m = material;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill('${m.sectionCount} sub bab', icon: Icons.menu_book_outlined),
              Pill(
                m.published ? 'Publik' : 'Draf',
                color: m.published ? AppColors.primary : AppColors.highlight,
                textColor: m.published ? AppColors.white : AppColors.ink,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(m.title, style: AppType.titleLarge),
          ),
          const SizedBox(height: 8),
          Text(quizSummary(m, TestKind.pre), style: AppType.bodyMedium),
          Text(quizSummary(m, TestKind.post), style: AppType.bodyMedium),
          const SizedBox(height: 12),
          if (m.hiddenImages > 0) ...[
            HiddenImagesWarning(material: m),
            const SizedBox(height: 12),
          ],
          Bouncy(
            // Tiap kartu punya tombol ini; sebut judulnya supaya TalkBack
            // tidak membaca "Kelola materi" berulang tanpa konteks.
            child: Semantics(
              label: 'Kelola materi ${m.title}',
              button: true,
              onTap: onOpen,
              excludeSemantics: true,
              child: FilledButton.icon(
                icon: const Icon(Icons.tune),
                label: const Text('Kelola materi'),
                onPressed: onOpen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
