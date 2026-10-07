import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/mascot.dart';
import '../../widgets/playful.dart';
import 'play_game_screen.dart';

String _starsText(Attempt? attempt) => attempt == null
    ? 'Belum dikerjakan'
    : 'Selesai, ${attempt.stars} dari 3 bintang';

/// Layar belajar satu materi, mengikuti desain "Live Audio Lesson":
/// kartu kepala, pemutar audio materi, lalu pre-test dan post-test.
class MaterialJourneyScreen extends StatefulWidget {
  const MaterialJourneyScreen({
    super.key,
    required this.material,
    required this.studentName,
  });

  final LessonMaterial material;
  final String studentName;

  @override
  State<MaterialJourneyScreen> createState() => _MaterialJourneyScreenState();
}

class _MaterialJourneyScreenState extends State<MaterialJourneyScreen> {
  LessonMaterial get _m => widget.material;

  @override
  void dispose() {
    Speech.stop();
    super.dispose();
  }

  void _play(TestKind kind) {
    if (_m.questionsFor(kind).isEmpty) {
      _say('Guru belum membuat soal ${kind.label}.');
      return;
    }
    Speech.stop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayGameScreen(
          material: _m,
          kind: kind,
          studentName: widget.studentName,
        ),
      ),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    Speech.announce(message);
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Materi'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final name = widget.studentName;
            final pre = store.latestAttempt(_m, name, TestKind.pre);
            final post = store.latestAttempt(_m, name, TestKind.post);
            final needPreFirst = _m.preTest.isNotEmpty && pre == null;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Pill(
                        'Kode: ${_m.accessCode}',
                        icon: Icons.key,
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
                        'Jenis soal: ${_m.questionType.label}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.white,
                        ),
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
                // Pemutar audio materi.
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
                              child: Icon(
                                Icons.headphones,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Materi audio', style: AppType.bodySmall),
                                Text(_m.title, style: AppType.titleMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      PrimaryButton(
                        label: 'Dengarkan',
                        icon: Icons.play_arrow,
                        onPressed: () =>
                            Speech.speak('${_m.title}. ${_m.body}'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.stop),
                              label: const Text('Hentikan'),
                              onPressed: Speech.stop,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.menu_book_outlined),
                              label: const Text('Baca teks'),
                              onPressed: () {
                                Speech.stop();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MaterialReaderScreen(material: _m),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Tes untuk materi ini'),
                _TestCard(
                  icon: Icons.flag_outlined,
                  title: 'Pre-test',
                  count: _m.preTest.length,
                  status: _starsText(pre),
                  done: pre != null,
                  buttonLabel: pre == null ? 'Mulai Pre-test' : 'Ulangi Pre-test',
                  onPressed: () => _play(TestKind.pre),
                ),
                _TestCard(
                  icon: needPreFirst
                      ? Icons.lock_outline
                      : Icons.emoji_events_outlined,
                  title: 'Post-test',
                  count: _m.postTest.length,
                  status: needPreFirst
                      ? 'Terkunci. Kerjakan pre-test dulu'
                      : _starsText(post),
                  done: post != null,
                  buttonLabel:
                      post == null ? 'Mulai Post-test' : 'Ulangi Post-test',
                  onPressed: () {
                    if (needPreFirst) {
                      _say('Kerjakan pre-test dulu, ya.');
                    } else {
                      _play(TestKind.post);
                    }
                  },
                ),
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
          },
        ),
      ),
    );
  }

  String _guide(Attempt? pre, Attempt? post) {
    if (post != null) {
      return 'Hebat, materi ini sudah selesai! Kamu boleh mengulang '
          'post-test untuk menambah bintang.';
    }
    if (pre != null) {
      return 'Pre-test selesai. Sekarang dengarkan materinya, lalu '
          'kerjakan post-test.';
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

/// Kartu satu tes: jumlah soal, status, dan tombol mulai.
class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.status,
    required this.done,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final int count;
  final String status;
  final bool done;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Judul, jumlah soal, dan status dibaca sebagai satu kalimat.
              Semantics(
                label: '$title. $count soal. $status',
                excludeSemantics: true,
                child: Row(
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
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Pill('$count soal'),
                              Pill(
                                status,
                                color: done
                                    ? AppColors.successBg
                                    : AppColors.highlight,
                                textColor:
                                    done ? AppColors.success : AppColors.ink,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              done
                  ? Bouncy(
                      child: OutlinedButton(
                        onPressed: onPressed,
                        child: Text(buttonLabel),
                      ),
                    )
                  : PrimaryButton(
                      label: buttonLabel,
                      icon: Icons.arrow_forward,
                      onPressed: onPressed,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pembaca materi. Dipakai siswa dan guru.
class MaterialReaderScreen extends StatefulWidget {
  const MaterialReaderScreen({super.key, required this.material});

  final LessonMaterial material;

  @override
  State<MaterialReaderScreen> createState() => _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends State<MaterialReaderScreen> {
  @override
  void dispose() {
    Speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    return PurpleScaffold(
      appBar: aprevoAppBar('Materi'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              header: true,
              child: Text(
                m.title,
                style: AppType.headlineMedium,
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Dengarkan materi',
              icon: Icons.volume_up,
              onPressed: () => Speech.speak('${m.title}. ${m.body}'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Hentikan suara'),
              onPressed: Speech.stop,
            ),
            const SizedBox(height: 20),
            AppCard(
              color: AppColors.soft,
              child: Text(m.body, style: AppType.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}
