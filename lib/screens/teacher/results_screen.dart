import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Rata-rata satu tes dalam kalimat, misalnya "rata-rata 75, 3 siswa
/// mengumpulkan".
String quizAverageText(QuizResult? q) {
  if (q == null) return 'belum dibuat';
  final avg = q.averagePercent;
  if (avg == null) return 'belum ada yang mengumpulkan';
  return 'rata-rata ${avg.round()}, ${q.submittedCount} siswa mengumpulkan';
}

/// Hasil satu siswa untuk satu tes.
String studentResultText(TestKind kind, StudentResult? r) {
  final a = r?.latest;
  if (a == null) return '${kind.label} belum dikerjakan';
  return '${kind.label} benar ${a.score} dari ${a.total}, ${a.stars} bintang';
}

/// Ringkasan pre-test dan post-test satu materi.
class MaterialResultCard extends StatelessWidget {
  const MaterialResultCard({
    super.key,
    required this.material,
    required this.studentCount,
    this.onOpen,
  });

  final MaterialResult material;
  final int studentCount;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final pre = material.quiz(TestKind.pre);
    final post = material.quiz(TestKind.post);
    final preAvg = pre?.averagePercent?.round();
    final postAvg = post?.averagePercent?.round();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(material.title, style: AppType.titleLarge),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(value: '$studentCount', label: 'Siswa'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: preAvg == null ? 'Belum ada' : '$preAvg',
                  label: 'Nilai pre-test',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: postAvg == null ? 'Belum ada' : '$postAvg',
                  label: 'Nilai post-test',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Pre-test: ${quizAverageText(pre)}. '
            'Post-test: ${quizAverageText(post)}.',
            style: AppType.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(_change(preAvg, postAvg), style: AppType.bodyMedium),
          if (onOpen != null) ...[
            const SizedBox(height: 12),
            Bouncy(
              child: Semantics(
                label: 'Lihat hasil per siswa untuk ${material.title}',
                button: true,
                onTap: onOpen,
                excludeSemantics: true,
                child: FilledButton.icon(
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Lihat per siswa'),
                  onPressed: onOpen,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _change(int? pre, int? post) {
    if (pre == null || post == null) {
      return 'Perbandingan muncul setelah siswa mengerjakan pre-test dan '
          'post-test.';
    }
    final diff = post - pre;
    if (diff > 0) return 'Nilai naik $diff poin setelah belajar.';
    if (diff < 0) return 'Nilai turun ${-diff} poin. Materinya perlu diulang.';
    return 'Nilai pre-test dan post-test sama.';
  }
}

/// Hasil tiap siswa untuk satu materi.
class MaterialResultScreen extends StatelessWidget {
  const MaterialResultScreen({
    super.key,
    required this.subjectId,
    required this.materialId,
    required this.materialTitle,
  });

  final String subjectId;
  final String materialId;
  final String materialTitle;

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Hasil $materialTitle'),
      body: SafeArea(
        child: LoadView<SubjectResults>(
          loadingMessage: 'Memuat hasil siswa $materialTitle.',
          load: () => store.subjectResults(subjectId),
          builder: (context, results, _) {
            MaterialResult? material;
            for (final m in results.materials) {
              if (m.id == materialId) material = m;
            }
            if (material == null) {
              return const EmptyState(message: 'Materi tidak ditemukan.');
            }
            final pre = material.quiz(TestKind.pre);
            final post = material.quiz(TestKind.post);
            // Gabungan siswa dari pre-test dan post-test.
            final names = <String, String>{};
            for (final q in material.quizzes) {
              for (final s in q.students) {
                names[s.studentId] = s.name;
              }
            }
            StudentResult? find(QuizResult? q, String id) {
              if (q == null) return null;
              for (final s in q.students) {
                if (s.studentId == id) return s;
              }
              return null;
            }

            final ids = names.keys.toList()
              ..sort((a, b) => names[a]!.compareTo(names[b]!));
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                MaterialResultCard(
                  material: material,
                  studentCount: results.studentCount,
                ),
                SectionTitle('Siswa (${ids.length})'),
                if (ids.isEmpty)
                  const EmptyState(
                    message:
                        'Belum ada data siswa. Hasil muncul setelah '
                        'pre-test atau post-test dibuat dan siswa '
                        'bergabung.',
                  ),
                for (final id in ids)
                  ListRow(
                    icon: Icons.person_outline,
                    title: names[id]!,
                    subtitle:
                        '${studentResultText(TestKind.pre, find(pre, id))}. '
                        '${studentResultText(TestKind.post, find(post, id))}',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
