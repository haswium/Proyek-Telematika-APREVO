import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../models/progress.dart';
import '../../services/announce.dart';
import '../../services/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Progres satu siswa di satu kelas: rata-rata kenaikan (diumumkan sekali),
/// lalu tiap materi dengan nilai pre-test dan post-test, bintang, waktu
/// mengerjakan, dan jumlah percobaan. Tiap baris satu label utuh.
class StudentProgressScreen extends StatefulWidget {
  const StudentProgressScreen({
    super.key,
    required this.subject,
    required this.studentId,
    required this.studentName,
  });

  final Subject subject;
  final String studentId;
  final String studentName;

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  bool _announced = false;

  void _announceSummary(String sentence) {
    if (_announced) return;
    _announced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) announce(sentence);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar(widget.studentName),
      body: SafeArea(
        child: LoadView<StudentProgress>(
          loadingMessage: 'Memuat progres ${widget.studentName}.',
          load: () =>
              store.studentProgressFor(widget.subject.id, widget.studentId),
          builder: (context, data, _) {
            final sentence = data.sentence;
            _announceSummary(sentence);
            final gain = data.averageGain;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Progres ${data.name}',
                    style: AppType.headlineMedium.copyWith(
                      color: AppColors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  label: sentence,
                  excludeSemantics: true,
                  child: AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            value: gain == null ? '-' : gainSigned(gain),
                            label: 'Rata-rata kenaikan',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            value: '${data.completeCount}',
                            label: 'Materi lengkap',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  kProgressRule,
                  style: AppType.bodyMedium.copyWith(color: AppColors.white),
                ),
                const SizedBox(height: 8),
                if (data.materials.isEmpty)
                  const EmptyState(
                    message: 'Belum ada materi dengan pre-test atau post-test.',
                  ),
                for (final material in data.materials) ...[
                  SectionTitle(quizName(material.title)),
                  _QuizRow(
                    kindLabel: 'Pre-test',
                    title: material.title,
                    quiz: material.scores.pre,
                  ),
                  _QuizRow(
                    kindLabel: 'Post-test',
                    title: material.title,
                    quiz: material.scores.post,
                  ),
                  if (material.scores.gain != null)
                    ListRow(
                      icon: material.scores.gain! >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      title: 'Kenaikan: ${gainWords(material.scores.gain!)}',
                      semanticLabel:
                          'Kenaikan ${material.title}: '
                          '${gainWords(material.scores.gain!)}',
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuizRow extends StatelessWidget {
  const _QuizRow({
    required this.kindLabel,
    required this.title,
    required this.quiz,
  });

  final String kindLabel;
  final String title;
  final QuizScore? quiz;

  @override
  Widget build(BuildContext context) {
    final quiz = this.quiz;
    final score = quiz?.score;
    final String subtitle;
    if (quiz == null) {
      subtitle = 'Belum dibuat';
    } else if (score == null) {
      subtitle = 'Belum dikerjakan';
    } else {
      subtitle = [
        'Benar ${quiz.correct} dari ${quiz.total}, ${quiz.stars ?? 0} bintang',
        if (quiz.submittedAt != null)
          'Dikerjakan ${formatDateTime(quiz.submittedAt!)}',
        '${quiz.attemptCount} kali percobaan',
      ].join('\n');
    }
    return ListRow(
      icon: kindLabel == 'Pre-test'
          ? Icons.flag_outlined
          : Icons.emoji_events_outlined,
      title: score == null ? kindLabel : '$kindLabel: $score',
      subtitle: subtitle,
      semanticLabel: quizScoreLabel(kindLabel, title, quiz),
    );
  }
}
