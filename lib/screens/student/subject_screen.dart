import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/mascot.dart';
import '../../widgets/playful.dart';
import 'student_space_screen.dart';

/// Kemajuan siswa di satu materi, dalam satu kalimat.
String materialProgress(LessonMaterial m) {
  final post = m.quiz(TestKind.post)?.latestAttempt;
  if (post != null) return 'Selesai, ${post.stars} dari 3 bintang';
  if (m.quiz(TestKind.pre)?.latestAttempt != null) {
    return 'Pre-test selesai, lanjut baca materi';
  }
  return '${m.sectionCount} sub bab, belum dimulai';
}

/// Isi satu kelas untuk siswa: hanya materi yang sudah
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
          subject: subject,
          material: material,
          studentName: studentName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar(subject.name),
      body: SafeArea(
        child: LoadView<List<LessonMaterial>>(
          loadingMessage: 'Memuat materi ${subject.name}.',
          load: () => store.studentMaterials(subject.id),
          builder: (context, materials, _) => ListView(
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
                  text:
                      'Pilih materi yang mau kamu pelajari. Kita mulai '
                      'dari pre-test, ya.',
                ),
              ],
              const SizedBox(height: 8),
              SectionTitle('Daftar materi (${materials.length})'),
              if (materials.isEmpty)
                const EmptyState(message: 'Guru belum mempublikasikan materi.'),
              for (final m in materials)
                ListRow(
                  icon: Icons.headphones_outlined,
                  title: m.title,
                  subtitle: materialProgress(m),
                  semanticLabel: 'Materi ${m.title}. ${materialProgress(m)}',
                  onTap: () => _open(context, m),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
