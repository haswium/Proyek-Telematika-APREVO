import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/mascot.dart';
import '../../widgets/playful.dart';

/// Hasil satu tes: skor bintang dan apresiasi dari Odi.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.materialTitle,
    required this.kind,
    required this.score,
    required this.total,
    required this.studentName,
    this.preTest,
  });

  final String materialTitle;
  final TestKind kind;
  final int score;
  final int total;
  final String studentName;

  /// Hasil pre-test siswa, untuk dibandingkan saat post-test selesai.
  final Attempt? preTest;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  int get _stars => starsFor(widget.score, widget.total);

  MascotMood get _mood {
    if (_stars == 3) return MascotMood.cheer;
    if (_stars == 0) return MascotMood.oops;
    return MascotMood.happy;
  }

  /// Apresiasi dari Odi, berbeda untuk tiap jumlah bintang.
  String get _praise {
    final name = widget.studentName;
    switch (_stars) {
      case 3:
        return 'Luar biasa, $name! Kamu mendapat tiga bintang. '
            'Odi bangga sekali padamu!';
      case 2:
        return 'Bagus sekali, $name! Dua bintang untukmu. '
            'Sedikit lagi menuju tiga bintang.';
      case 1:
        return 'Kerja bagus sudah menyelesaikannya, $name. Satu bintang '
            'untukmu. Yuk berlatih lagi bersama Odi.';
      default:
        return 'Terima kasih sudah mencoba, $name. Belum ada bintang kali '
            'ini, tapi tidak apa-apa. Odi temani kamu belajar lagi.';
    }
  }

  String get _nextStep {
    if (widget.kind == TestKind.pre) {
      return 'Langkah berikutnya: dengarkan materinya, lalu kerjakan '
          'post-test.';
    }
    final pre = widget.preTest;
    if (pre == null || pre.total == 0 || widget.total == 0) return '';
    final before = pre.score / pre.total;
    final after = widget.score / widget.total;
    if (after > before) {
      return 'Saat pre-test kamu benar ${pre.score} dari ${pre.total}. '
          'Sekarang nilaimu naik!';
    }
    if (after == before) {
      return 'Nilaimu sama dengan pre-test. Coba dengarkan materinya '
          'sekali lagi.';
    }
    return 'Nilai pre-test kamu lebih tinggi. Dengarkan lagi materinya, '
        'lalu ulangi post-test.';
  }

  String get _summary =>
      '${widget.kind.label} ${widget.materialTitle} selesai. '
      'Kamu benar ${widget.score} dari ${widget.total} soal, '
      '$_stars dari 3 bintang. $_praise $_nextStep';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Kalau TalkBack menyala, liveRegion di bawah yang membacakan.
      // Kalau tidak, Odi membacakannya sendiri.
      if (!MediaQuery.of(context).accessibleNavigation) {
        Speech.speak(_summary);
      }
    });
  }

  @override
  void dispose() {
    Speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Hasil ${widget.kind.label}'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Mascot(size: 150, mood: _mood)),
            const SizedBox(height: 8),
            // Seluruh hasil dibaca TalkBack sebagai satu pesan utuh.
            Semantics(
              liveRegion: true,
              container: true,
              label: _summary,
              excludeSemantics: true,
              child: Column(
                children: [
                  StarRow(stars: _stars),
                  const SizedBox(height: 12),
                  AppCard(
                    color: AppColors.primary,
                    borderColor: AppColors.ink,
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Text(
                          'Benar ${widget.score} dari ${widget.total}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: AppColors.highlight,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.materialTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            color: AppColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    color: AppColors.highlight,
                    borderColor: AppColors.ink,
                    child: Text(_praise, style: AppType.bodyLarge),
                  ),
                  if (_nextStep.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    AppCard(
                      color: AppColors.mint,
                      borderColor: AppColors.ink,
                      child: Text(_nextStep, style: AppType.bodyLarge),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.volume_up),
              label: const Text('Dengarkan hasil'),
              onPressed: () => Speech.speak(_summary),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Kembali ke langkah belajar',
              icon: Icons.arrow_back,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
