import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../services/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/mascot.dart';
import '../../widgets/playful.dart';
import 'play_game_screen.dart';
import 'review_screen.dart';
import 'section_reader_screen.dart';

/// Layar belajar satu materi, mengikuti desain "Live Audio Lesson":
/// kartu kepala, materi per sub-bab, lalu pre-test dan post-test dengan
/// jadwalnya.
class MaterialJourneyScreen extends StatelessWidget {
  const MaterialJourneyScreen({
    super.key,
    required this.subject,
    required this.material,
    required this.studentName,
  });

  final Subject subject;

  /// Data dari daftar materi, supaya layar langsung tampil. Status kuis
  /// terbaru tetap dimuat ulang.
  final LessonMaterial material;
  final String studentName;

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Materi'),
      body: SafeArea(
        child: LoadView<LessonMaterial>(
          initialData: material,
          loadingMessage: 'Memuat materi ${material.title}.',
          load: () => store.studentMaterial(subject.id, material.id),
          builder: (context, m, _) => _JourneyBody(
            subject: subject,
            material: m,
            studentName: studentName,
          ),
        ),
      ),
    );
  }
}

class _JourneyBody extends StatelessWidget {
  const _JourneyBody({
    required this.subject,
    required this.material,
    required this.studentName,
  });

  final Subject subject;
  final LessonMaterial material;
  final String studentName;

  LessonMaterial get _m => material;

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    Speech.feedback(context, message);
  }

  void _play(BuildContext context, QuizInfo quiz) {
    Speech.stop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayGameScreen(
          quiz: quiz,
          materialTitle: _m.title,
          studentName: studentName,
          preTest: quiz.kind == TestKind.post
              ? _m.quiz(TestKind.pre)?.latestAttempt
              : null,
        ),
      ),
    );
  }

  void _review(BuildContext context, Attempt attempt, {required bool key}) {
    Speech.stop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(attemptId: attempt.id, withKey: key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pre = _m.quiz(TestKind.pre)?.latestAttempt;
    final post = _m.quiz(TestKind.post)?.latestAttempt;
    final sections = _m.sectionCount == 0
        ? 'Belum ada sub bab'
        : '${_m.sectionCount} sub bab';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pill(
                subject.name,
                icon: Icons.folder_outlined,
                color: AppColors.accent,
                textColor: AppColors.ink,
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  _m.title,
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
                sections,
                style: const TextStyle(fontSize: 16, color: AppColors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MascotBubble(
          mood: post != null ? MascotMood.cheer : MascotMood.happy,
          text: _guide(pre, post),
        ),
        const SizedBox(height: 16),
        // Materi audio per sub-bab.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.lilac,
                      child: Icon(Icons.headphones, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Materi audio', style: AppType.bodySmall),
                          Text(_m.title, style: AppType.titleMedium),
                          Text(sections, style: AppType.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: 'Dengarkan per sub bab',
                icon: Icons.play_arrow,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MaterialSectionsScreen(
                      materialId: _m.id,
                      materialTitle: _m.title,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Tes untuk materi ini'),
        for (final kind in TestKind.values) _testCard(context, kind),
        if (pre != null && post != null)
          AppCard(
            color: AppColors.mint,
            borderColor: AppColors.success,
            child: Column(
              children: [
                Text(
                  _compare(pre, post),
                  textAlign: TextAlign.center,
                  style: AppType.bodyLarge,
                ),
                const SizedBox(height: 8),
                StarRow(stars: post.stars, size: 44),
              ],
            ),
          ),
      ],
    );
  }

  Widget _testCard(BuildContext context, TestKind kind) {
    final q = _m.quiz(kind);
    final label = kind.label;
    if (q == null) {
      return _TestCard(
        icon: Icons.hourglass_empty,
        title: label,
        status: 'Guru belum membuat $label',
        actions: const [],
      );
    }
    final latest = q.latestAttempt;
    final canStart =
        q.status == QuizStatus.open && !q.locked && !q.limitReached;
    final parts = <String>[
      if (q.locked) 'Terkunci. Kerjakan pre-test dulu',
      q.scheduleText,
      if (latest != null)
        'Hasil terakhir: benar ${latest.score} dari ${latest.total}, '
            '${latest.stars} dari 3 bintang'
      else
        'Belum dikerjakan',
      if (q.limitReached) 'Batas percobaan sudah habis',
      if (latest != null && !q.discussionAvailable && q.deadlineAt != null)
        'Pembahasan terbuka setelah ${formatDateTime(q.deadlineAt!)}',
    ];
    final String startLabel;
    if (q.unfinishedAttemptId != null) {
      startLabel = 'Lanjutkan $label';
    } else if (latest != null) {
      startLabel = 'Ulangi $label';
    } else {
      startLabel = 'Mulai $label';
    }
    return _TestCard(
      icon: q.locked
          ? Icons.lock_outline
          : kind == TestKind.pre
          ? Icons.flag_outlined
          : Icons.emoji_events_outlined,
      title: label,
      status: parts.join('. '),
      actions: [
        if (canStart)
          _TestAction(
            label: startLabel,
            icon: Icons.arrow_forward,
            primary: latest == null,
            onPressed: () => _play(context, q),
          )
        else if (q.locked)
          _TestAction(
            label: startLabel,
            icon: Icons.lock_outline,
            primary: false,
            onPressed: () => _say(context, 'Kerjakan pre-test dulu, ya.'),
          ),
        if (latest != null)
          _TestAction(
            label: 'Lihat jawaban $label',
            icon: Icons.fact_check_outlined,
            primary: false,
            onPressed: () => _review(context, latest, key: false),
          ),
        if (latest != null && q.discussionAvailable)
          _TestAction(
            label: 'Pembahasan $label',
            icon: Icons.lightbulb_outline,
            primary: false,
            onPressed: () => _review(context, latest, key: true),
          ),
      ],
    );
  }

  String _guide(Attempt? pre, Attempt? post) {
    if (post != null) {
      return 'Hebat, materi ini sudah selesai! Kamu boleh melihat ulang '
          'jawabanmu kapan saja.';
    }
    if (pre != null) {
      return 'Pre-test selesai. Sekarang dengarkan materinya per sub bab, '
          'lalu kerjakan post-test.';
    }
    return 'Kita mulai dari pre-test dulu, ya. Tidak apa-apa kalau belum '
        'tahu jawabannya.';
  }

  String _compare(Attempt pre, Attempt post) {
    final before = 'Pre-test: benar ${pre.score} dari ${pre.total}. ';
    final after = 'Post-test: benar ${post.score} dari ${post.total}. ';
    final prePct = pre.total == 0 ? 0 : pre.score / pre.total;
    final postPct = post.total == 0 ? 0 : post.score / post.total;
    if (postPct > prePct) return '$before${after}Nilaimu naik!';
    if (postPct == prePct) return '$before${after}Nilaimu tetap.';
    return '$before${after}Yuk dengarkan materinya sekali lagi.';
  }
}

class _TestAction {
  const _TestAction({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;
}

/// Kartu satu tes: status dan jadwal dalam satu kalimat, lalu tombolnya.
class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String status;
  final List<_TestAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Judul dan status dibaca sebagai satu kalimat.
              Semantics(
                label: '$title. $status.',
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: AppColors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppType.titleMedium),
                          const SizedBox(height: 4),
                          Text('$status.', style: AppType.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final a in actions) ...[
                const SizedBox(height: 12),
                a.primary
                    ? PrimaryButton(
                        label: a.label,
                        icon: a.icon,
                        onPressed: a.onPressed,
                      )
                    : Bouncy(
                        child: OutlinedButton.icon(
                          icon: Icon(a.icon),
                          label: Text(a.label),
                          onPressed: a.onPressed,
                        ),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
