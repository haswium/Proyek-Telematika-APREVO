import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../models/progress.dart';
import '../../services/announce.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import 'student_progress_screen.dart';

/// Progres satu kelas: ringkasan kelas (diumumkan sekali saat layar dibuka),
/// lalu tabel nilai per materi. Tiap baris tabel dibaca TalkBack sebagai satu
/// label utuh, misalnya "Andi, Kuis Fotosintesis, pre-test 60, post-test 85,
/// naik 25". Hanya angka, tanpa grafik.
class SubjectProgressScreen extends StatefulWidget {
  const SubjectProgressScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<SubjectProgressScreen> createState() => _SubjectProgressScreenState();
}

class _SubjectProgressScreenState extends State<SubjectProgressScreen> {
  bool _announced = false;

  /// Ringkasan diumumkan sekali, tidak diulang saat data dimuat ulang.
  void _announceSummary(String sentence) {
    if (_announced) return;
    _announced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) announce(sentence);
    });
  }

  void _openStudent(ProgressRow row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentProgressScreen(
          subject: widget.subject,
          studentId: row.studentId,
          studentName: row.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    return PurpleScaffold(
      appBar: aprevoAppBar('Progres siswa'),
      body: SafeArea(
        child: LoadView<ClassProgress>(
          loadingMessage: 'Memuat progres ${subject.name}.',
          load: () => store.subjectProgress(subject.id),
          builder: (context, data, _) {
            final sentence = data.summary.sentence(subject.name);
            _announceSummary(sentence);
            final white = AppType.bodyMedium.copyWith(color: AppColors.white);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Progres ${subject.name}',
                    style: AppType.headlineMedium.copyWith(
                      color: AppColors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SummaryCard(summary: data.summary, sentence: sentence),
                const SizedBox(height: 12),
                // Ikut dibaca TalkBack sebagai teks biasa.
                Text(kProgressRule, style: white),
                const SizedBox(height: 8),
                if (data.materials.isEmpty)
                  const EmptyState(
                    message:
                        'Belum ada materi dengan pre-test atau post-test di '
                        'kelas ini.',
                  ),
                for (final material in data.materials) ...[
                  SectionTitle(quizName(material.title)),
                  Text('${material.averageText}.', style: white),
                  const SizedBox(height: 8),
                  if (material.rows.isEmpty)
                    const EmptyState(message: 'Belum ada siswa di kelas ini.')
                  else
                    _ScoreTable(material: material, onOpen: _openStudent),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Ringkasan kelas dalam kotak angka. Dibaca sebagai satu kalimat utuh.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.sentence});

  final ClassProgressSummary summary;
  final String sentence;

  String _avg(double? value) => value == null ? '-' : formatAverage(value);

  @override
  Widget build(BuildContext context) {
    final gain = summary.averageGain;
    return Semantics(
      container: true,
      label: sentence,
      excludeSemantics: true,
      child: AppCard(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    value: '${summary.studentCount}',
                    label: 'Siswa',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '${summary.materialCount}',
                    label: 'Materi',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    value: _avg(summary.averagePre),
                    label: 'Rata-rata pre-test',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: _avg(summary.averagePost),
                    label: 'Rata-rata post-test',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: gain == null ? '-' : gainSigned(gain),
                    label: 'Kenaikan',
                  ),
                ),
              ],
            ),
            if (summary.completeCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${summary.improved} naik, ${summary.same} tetap, '
                '${summary.declined} turun',
                style: AppType.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tabel nilai satu materi. Kepala kolom hanya untuk mata; TalkBack membaca
/// tiap baris sebagai satu label yang sudah menyebut nama kolomnya.
class _ScoreTable extends StatelessWidget {
  const _ScoreTable({required this.material, required this.onOpen});

  final MaterialProgress material;
  final ValueChanged<ProgressRow> onOpen;

  static String _cell(QuizScore? quiz) {
    if (quiz == null) return '-';
    final score = quiz.score;
    if (score == null) return 'Belum';
    return quiz.attemptCount > 1 ? '$score (${quiz.attemptCount}x)' : '$score';
  }

  Widget _row(List<String> cells, {bool header = false}) {
    final style = header ? AppType.bodySmall : AppType.titleMedium;
    return Row(
      children: [
        Expanded(flex: 3, child: Text(cells[0], style: style)),
        for (final cell in cells.skip(1))
          Expanded(
            flex: 2,
            child: Text(cell, textAlign: TextAlign.end, style: style),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _row(const [
                'Siswa',
                'Pre',
                'Post',
                'Selisih',
              ], header: true),
            ),
          ),
          for (final row in material.rows)
            Semantics(
              key: ValueKey('${material.id}-${row.studentId}'),
              label: row.labelFor(material.title),
              button: true,
              onTap: () => onOpen(row),
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onOpen(row),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kTouchTarget),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _row([
                        row.name,
                        _cell(row.scores.pre),
                        _cell(row.scores.post),
                        row.scores.gain == null
                            ? '-'
                            : gainSigned(row.scores.gain!),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
