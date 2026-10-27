import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Lihat ulang jawaban setelah kuis dikumpulkan.
///
/// [withKey] `false`: soal, jawaban siswa, dan benar atau salah saja.
/// [withKey] `true`: pembahasan, ditambah jawaban benar dan penjelasan.
/// Backend hanya membuka pembahasan setelah tenggat kuis lewat.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.attemptId,
    required this.withKey,
  });

  final String attemptId;
  final bool withKey;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  String get _title => widget.withKey ? 'Pembahasan' : 'Jawabanku';

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar(_title),
      body: SafeArea(
        child: LoadView<AttemptReview>(
          listenToStore: false,
          loadingMessage: widget.withKey
              ? 'Memuat pembahasan.'
              : 'Memuat jawabanmu.',
          load: () =>
              store.attemptReview(widget.attemptId, withKey: widget.withKey),
          builder: (context, review, _) => _body(context, review),
        ),
      ),
    );
  }

  /// Kalimat lengkap satu soal, untuk TalkBack.
  String _itemText(AttemptReview review, int i) {
    final item = review.items[i];
    final b = StringBuffer(
      'Soal ${i + 1}. ${item.prompt} Jawabanmu: ${item.yourAnswer}. '
      '${item.isCorrect ? 'Benar' : 'Salah'}.',
    );
    if (review.withKey) {
      final right = item.rightAnswer;
      if (right != null) b.write(' Jawaban benar: $right.');
      final why = item.explanation;
      if (why != null && why.trim().isNotEmpty) {
        b.write(' Penjelasan: ${why.trim()}');
      }
    }
    return b.toString();
  }

  String _lockedNote(AttemptReview review) {
    final deadline = review.deadlineAt;
    if (deadline == null) {
      return 'Jawaban benar dan pembahasan terbuka setelah tenggat kuis '
          'lewat.';
    }
    return 'Jawaban benar dan pembahasan terbuka setelah '
        '${formatDateTime(deadline)}.';
  }

  Widget _body(BuildContext context, AttemptReview review) {
    final stars = starsFor(review.score, review.total);
    final summary =
        '${review.quizTitle}. Benar ${review.score} dari ${review.total} '
        'soal, $stars dari 3 bintang.';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Semantics(
          header: true,
          child: Text(review.quizTitle, style: AppType.headlineMedium),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: summary,
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Benar ${review.score} dari ${review.total}',
                  style: AppType.titleMedium,
                ),
              ),
              StarRow(stars: stars, size: 32),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!review.withKey) ...[
          if (review.discussionAvailable)
            PrimaryButton(
              label: 'Buka pembahasan',
              icon: Icons.lightbulb_outline,
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ReviewScreen(attemptId: review.attemptId, withKey: true),
                ),
              ),
            )
          else
            AppCard(
              color: AppColors.highlight,
              child: Text(_lockedNote(review), style: AppType.bodyMedium),
            ),
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < review.items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ReviewCard(
              number: i + 1,
              item: review.items[i],
              withKey: review.withKey,
              semanticLabel: _itemText(review, i),
            ),
          ),
      ],
    );
  }
}

/// Satu soal: dibaca TalkBack sebagai satu kalimat utuh.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.number,
    required this.item,
    required this.withKey,
    required this.semanticLabel,
  });

  final int number;
  final ReviewItem item;
  final bool withKey;
  final String semanticLabel;

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppType.bodySmall.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(value, style: AppType.bodyLarge),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final right = withKey ? item.rightAnswer : null;
    final why = withKey ? item.explanation : null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: semanticLabel,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      item.isCorrect ? Icons.check_circle : Icons.cancel,
                      color: AppColors.ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Soal $number: ${item.isCorrect ? 'Benar' : 'Salah'}',
                        style: AppType.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.prompt, style: AppType.bodyLarge),
                _row('Jawabanmu', item.yourAnswer),
                if (right != null) _row('Jawaban benar', right),
                if (why != null && why.trim().isNotEmpty)
                  _row('Penjelasan', why.trim()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
