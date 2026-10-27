import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import 'material_editor_screen.dart';
import 'new_material_screen.dart';

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
            return ListView(
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
                        style: TextStyle(color: AppColors.white, fontSize: 15),
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
                const SizedBox(height: 8),
                SectionTitle('Daftar materi (${materials.length})'),
                if (materials.isEmpty)
                  const EmptyState(message: 'Belum ada materi di kelas ini.'),
                for (var i = 0; i < materials.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 60 * (i > 5 ? 5 : i)),
                      child: _MaterialCard(
                        material: materials[i],
                        onOpen: () => _open(context, materials[i]),
                      ),
                    ),
                  ),
                if (materials.isNotEmpty)
                  Text(
                    'Ketuk "Kelola materi" untuk mengatur jadwal, soal, dan '
                    'publikasi.',
                    style: AppType.bodySmall,
                  ),
              ],
            );
          },
        ),
      ),
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
