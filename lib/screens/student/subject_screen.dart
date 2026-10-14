import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/mascot.dart';
import '../../widgets/playful.dart';
import 'student_space_screen.dart';

/// Isi satu mata pelajaran untuk siswa: hanya materi yang sudah
/// dipublikasikan guru, masing-masing dengan progresnya.
class StudentSubjectScreen extends StatelessWidget {
  const StudentSubjectScreen({
    super.key,
    required this.subject,
    required this.studentName,
  });

  final Subject subject;
  final String studentName;

  void _open(BuildContext context, LessonMaterial material) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialJourneyScreen(
          material: material,
          studentName: studentName,
        ),
      ),
    );
  }

  String _progress(LessonMaterial m) {
    final post = store.latestAttempt(m, studentName, TestKind.post);
    if (post != null) return 'Selesai, ${post.stars} dari 3 bintang';
    final pre = store.latestAttempt(m, studentName, TestKind.pre);
    if (pre != null) return 'Pre-test selesai, lanjut dengarkan materi';
    return 'Soal ${m.questionType.label}, belum dimulai';
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar(subject.name),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final materials = store.publishedMaterials(subject);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          subject.name,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.white,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${materials.length} materi siap dipelajari',
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Kalau kosong, cukup EmptyState di bawah supaya TalkBack
                // tidak membacakan pesan yang sama dua kali.
                if (materials.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const MascotBubble(
                    text: 'Pilih materi yang mau kamu pelajari. Kita mulai '
                        'dari pre-test, ya.',
                  ),
                ],
                const SizedBox(height: 8),
                SectionTitle('Daftar materi (${materials.length})'),
                if (materials.isEmpty)
                  const EmptyState(
                    message: 'Guru belum mempublikasikan materi.',
                  ),
                for (final m in materials)
                  ListRow(
                    icon: gameIcon(m.questionType),
                    title: m.title,
                    subtitle: _progress(m),
                    semanticLabel: 'Materi ${m.title}. ${_progress(m)}',
                    onTap: () => _open(context, m),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
