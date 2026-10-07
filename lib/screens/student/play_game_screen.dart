import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/mascot.dart';
import '../../widgets/playful.dart';
import 'result_screen.dart';

/// Layar pengerjaan pre-test atau post-test satu materi. Jenis soalnya
/// mengikuti jenis yang dipilih guru untuk materi itu.
///
/// Urutan fokus TalkBack (lihat angka OrdinalSortKey):
/// 1 info soal, 2 tombol dengarkan, 3 deskripsi gambar, 4 pertanyaan,
/// 5 jawaban, 6 umpan balik, 7 tombol kirim/lanjut.
class PlayGameScreen extends StatefulWidget {
  const PlayGameScreen({
    super.key,
    required this.material,
    required this.kind,
    required this.studentName,
  });

  final LessonMaterial material;
  final TestKind kind;
  final String studentName;

  @override
  State<PlayGameScreen> createState() => _PlayGameScreenState();
}

class _PlayGameScreenState extends State<PlayGameScreen> {
  final _answer = TextEditingController();
  late final List<Question> _questions = List<Question>.of(
    widget.material.questionsFor(widget.kind),
  );
  late final GameType _type = widget.material.questionType;

  int _index = 0;
  int _score = 0;
  bool _answered = false;
  bool _correct = false;
  int? _picked;
  List<String> _order = [];

  Question get _q => _questions[_index];
  int get _total => _questions.length;
  bool get _isLast => _index == _total - 1;

  @override
  void initState() {
    super.initState();
    _prepare();
    // Tunggu layar tampil dulu supaya pengumuman tidak tertimpa pembacaan
    // judul halaman oleh TalkBack.
    WidgetsBinding.instance.addPostFrameCallback((_) => _announceQuestion());
  }

  @override
  void dispose() {
    Speech.stop();
    _answer.dispose();
    super.dispose();
  }

  void _prepare() {
    _answered = false;
    _correct = false;
    _picked = null;
    _answer.clear();
    if (_type == GameType.ordering) {
      _order = List<String>.of(_q.options);
      // Acak sampai urutannya berbeda dari jawaban benar.
      var tries = 0;
      while (_order.length > 1 && listEquals(_order, _q.options) && tries < 10) {
        _order.shuffle();
        tries++;
      }
    }
  }

  void _announceQuestion() {
    Speech.announce('Soal ${_index + 1} dari $_total. ${_type.instruction}');
  }

  /// Teks lengkap soal untuk tombol "Dengarkan soal".
  String _spokenQuestion() {
    final b = StringBuffer('Soal ${_index + 1} dari $_total. ');
    if (_q.imageDescription != null) {
      b.write('Deskripsi gambar: ${_q.imageDescription}. ');
    }
    b.write('${_q.prompt} ');
    switch (_type) {
      case GameType.quiz:
        for (var i = 0; i < _q.options.length; i++) {
          b.write('Pilihan ${_letter(i)}: ${_q.options[i]}. ');
        }
      case GameType.trueFalse:
        b.write('Pilih benar atau salah.');
      case GameType.shortAnswer:
        b.write('Ketik jawabanmu.');
      case GameType.ordering:
        for (var i = 0; i < _order.length; i++) {
          b.write('Urutan ${i + 1}: ${_order[i]}. ');
        }
    }
    return b.toString();
  }

  String _letter(int i) => String.fromCharCode(65 + i);

  bool get _canSubmit {
    switch (_type) {
      case GameType.quiz:
      case GameType.trueFalse:
        return _picked != null;
      case GameType.shortAnswer:
        return _answer.text.trim().isNotEmpty;
      case GameType.ordering:
        return true;
    }
  }

  void _submit() {
    if (!_canSubmit || _answered) return;
    var correct = false;
    switch (_type) {
      case GameType.quiz:
      case GameType.trueFalse:
        correct = _picked == _q.correctIndex;
      case GameType.shortAnswer:
        correct = _answer.text.trim().toLowerCase() ==
            _q.answerText.trim().toLowerCase();
      case GameType.ordering:
        correct = listEquals(_order, _q.options);
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _answered = true;
      _correct = correct;
      if (correct) _score++;
    });
    // TalkBack membacakan kartu umpan balik lewat liveRegion. Kalau TalkBack
    // mati, Odi yang membacakannya.
    if (!MediaQuery.of(context).accessibleNavigation) {
      Speech.speak(_feedbackSpoken());
    }
  }

  // ---- Umpan balik -------------------------------------------------------

  String get _headline => _correct ? 'Benar! Hebat!' : 'Belum tepat, tidak apa-apa.';

  /// Jawaban yang diberikan siswa, dalam kalimat.
  String _yourAnswer() {
    switch (_type) {
      case GameType.quiz:
        return 'Pilihan ${_letter(_picked!)}, ${_q.options[_picked!]}';
      case GameType.trueFalse:
        return _q.options[_picked!];
      case GameType.shortAnswer:
        return _answer.text.trim();
      case GameType.ordering:
        return _order.join(', lalu ');
    }
  }

  String _rightAnswer() {
    if (_type == GameType.quiz) {
      return 'Pilihan ${_letter(_q.correctIndex)}, '
          '${_q.options[_q.correctIndex]}';
    }
    return _q.correctText(_type);
  }

  /// Untuk puzzle urutan: tunjukkan posisi pertama yang keliru.
  String? _orderingHint() {
    if (_type != GameType.ordering) return null;
    for (var i = 0; i < _order.length; i++) {
      if (_order[i] != _q.options[i]) {
        return 'Urutan ${i + 1} seharusnya "${_q.options[i]}", '
            'tetapi kamu menaruh "${_order[i]}".';
      }
    }
    return null;
  }

  /// Penjelasan dari guru. Kalau guru belum menulisnya, arahkan siswa ke
  /// materi supaya umpan balik tidak berhenti di "salah".
  String _why() {
    final explanation = _q.explanation;
    if (explanation != null && explanation.isNotEmpty) return explanation;
    return 'Dengarkan lagi materi ${widget.material.title} untuk memahami '
        'bagian ini.';
  }

  /// Baris-baris kartu umpan balik: judul kecil dan isinya.
  List<(String, String)> _feedbackRows() {
    if (_correct) {
      final explanation = _q.explanation;
      return [
        ('Jawabanmu', _yourAnswer()),
        if (explanation != null && explanation.isNotEmpty)
          ('Penjelasan', explanation),
      ];
    }
    final hint = _orderingHint();
    return [
      ('Jawabanmu', _yourAnswer()),
      ('Jawaban yang benar', _rightAnswer()),
      if (hint != null) ('Yang perlu diperbaiki', hint),
      ('Penjelasan', _why()),
    ];
  }

  String _feedbackSpoken() {
    final b = StringBuffer('$_headline ');
    for (final row in _feedbackRows()) {
      b.write('${row.$1}: ${row.$2}. ');
    }
    if (!_correct) b.write('Tetap semangat, kamu pasti bisa!');
    return b.toString();
  }

  // ---- Navigasi ----------------------------------------------------------

  void _next() {
    if (_isLast) {
      final pre = widget.kind == TestKind.post
          ? store.latestAttempt(
              widget.material,
              widget.studentName,
              TestKind.pre,
            )
          : null;
      store.addAttempt(
        widget.material,
        Attempt(
          studentName: widget.studentName,
          materialId: widget.material.id,
          materialTitle: widget.material.title,
          kind: widget.kind,
          score: _score,
          total: _total,
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            materialTitle: widget.material.title,
            kind: widget.kind,
            score: _score,
            total: _total,
            studentName: widget.studentName,
            preTest: pre,
          ),
        ),
      );
      return;
    }
    Speech.stop();
    setState(() {
      _index++;
      _prepare();
    });
    _announceQuestion();
  }

  void _move(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= _order.length) return;
    setState(() {
      final item = _order.removeAt(from);
      _order.insert(to, item);
    });
    Speech.announce('${_order[to]} pindah ke urutan ${to + 1}.');
  }

  Widget _ordered(double order, Widget child) {
    return Semantics(sortKey: OrdinalSortKey(order), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PurpleScaffold(
      appBar: aprevoAppBar('${widget.kind.label}: ${widget.material.title}'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ordered(
              1,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Soal ${_index + 1} dari $_total',
                      style: AppType.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Batang progres hanya visual; infonya sudah ada di judul.
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: (_index + 1) / _total),
                        duration: reduceMotion(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 12,
                          backgroundColor: AppColors.soft,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_type.instruction, style: AppType.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ordered(
              2,
              OutlinedButton.icon(
                icon: const Icon(Icons.volume_up),
                label: const Text('Dengarkan soal'),
                onPressed: () => Speech.speak(_spokenQuestion()),
              ),
            ),
            const SizedBox(height: 16),
            if (_q.imageDescription != null) ...[
              _ordered(
                3,
                AppCard(
                  color: AppColors.lilac,
                  child: Text(
                    'Deskripsi gambar: ${_q.imageDescription}',
                    style: AppType.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _ordered(
              4,
              // Key per soal supaya animasi masuk terulang tiap ganti soal.
              FadeSlideIn(
                key: ValueKey('prompt-$_index'),
                child: Text(_q.prompt, style: AppType.headlineMedium),
              ),
            ),
            const SizedBox(height: 20),
            _ordered(5, _buildAnswerArea(text)),
            const SizedBox(height: 8),
            if (_answered) ...[
              _ordered(6, _buildFeedback(text)),
              const SizedBox(height: 16),
            ],
            _ordered(
              7,
              _answered
                  ? PrimaryButton(
                      label: _isLast ? 'Lihat hasil' : 'Soal berikutnya',
                      icon: Icons.arrow_forward,
                      onPressed: _next,
                    )
                  : PrimaryButton(
                      label: 'Periksa Jawaban',
                      icon: Icons.check,
                      onPressed: _canSubmit ? _submit : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu umpan balik: Odi, judul benar/salah, lalu rincian jawaban dan
  /// penjelasan. Dibaca TalkBack sebagai satu pesan utuh begitu muncul.
  Widget _buildFeedback(TextTheme text) {
    final color = _correct ? AppColors.success : AppColors.danger;
    return Semantics(
      liveRegion: true,
      container: true,
      label: _feedbackSpoken(),
      excludeSemantics: true,
      child: FadeSlideIn(
        key: ValueKey('feedback-$_index'),
        child: AppCard(
          color: _correct ? AppColors.successBg : AppColors.dangerBg,
          borderColor: color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Mascot(
                    size: 76,
                    mood: _correct ? MascotMood.cheer : MascotMood.oops,
                    decorative: true,
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    _correct ? Icons.check_circle : Icons.cancel,
                    color: color,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _headline,
                      style: AppType.titleLarge.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              for (final row in _feedbackRows()) ...[
                const SizedBox(height: 12),
                Text(
                  row.$1,
                  style: AppType.bodySmall.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(row.$2, style: AppType.bodyLarge),
              ],
              if (!_correct) ...[
                const SizedBox(height: 12),
                Text(
                  'Tetap semangat, kamu pasti bisa!',
                  style: AppType.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerArea(TextTheme text) {
    switch (_type) {
      case GameType.quiz:
        return Column(
          children: [
            for (var i = 0; i < _q.options.length; i++)
              Bouncy(
                child: _OptionTile(
                  badge: _letter(i),
                  label: _q.options[i],
                  semanticLabel: 'Pilihan ${_letter(i)}, ${_q.options[i]}',
                  selected: _picked == i,
                  onTap: _answered ? null : () => setState(() => _picked = i),
                ),
              ),
          ],
        );
      case GameType.trueFalse:
        return Column(
          children: [
            for (var i = 0; i < _q.options.length; i++)
              Bouncy(
                child: _OptionTile(
                  badge: i == 0 ? 'B' : 'S',
                  label: _q.options[i],
                  semanticLabel: _q.options[i],
                  selected: _picked == i,
                  onTap: _answered ? null : () => setState(() => _picked = i),
                ),
              ),
          ],
        );
      case GameType.shortAnswer:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _answer,
            enabled: !_answered,
            style: AppType.bodyLarge,
            textInputAction: TextInputAction.done,
            decoration: fieldDecoration('Jawabanmu'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        );
      case GameType.ordering:
        return Column(
          children: [
            for (var i = 0; i < _order.length; i++)
              _OrderRow(
                position: i + 1,
                total: _order.length,
                label: _order[i],
                onUp: _answered || i == 0 ? null : () => _move(i, -1),
                onDown: _answered || i == _order.length - 1
                    ? null
                    : () => _move(i, 1),
              ),
          ],
        );
    }
  }
}

/// Pilihan jawaban. Dibaca TalkBack sebagai satu tombol:
/// "Pilihan A, Daun, tombol" dan "dipilih" kalau sedang terpilih.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.badge,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String badge;
  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: semanticLabel,
        button: true,
        selected: selected,
        enabled: onTap != null,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: selected ? AppColors.accent : AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppColors.ink, width: selected ? 3 : 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.white : AppColors.lilac,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: AppColors.ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Satu item puzzle urutan, mengikuti desain Figma. Tanpa drag and drop:
/// dipindahkan dengan tombol "Naikkan" dan "Turunkan" yang berlabel teks,
/// dan tiap item punya tombol dengarkan sendiri.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.position,
    required this.total,
    required this.label,
    required this.onUp,
    required this.onDown,
  });

  final int position;
  final int total;
  final String label;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  ButtonStyle get _moveStyle => FilledButton.styleFrom(
        backgroundColor: AppColors.lilac,
        foregroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.soft,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(0, kTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Posisi $position dari $total: $label',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$position',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Posisi $position dari $total',
                                style: AppType.bodySmall,
                              ),
                              Text(
                                label,
                                style: AppType.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dengarkan $label',
                  constraints: const BoxConstraints(
                    minWidth: kTouchTarget,
                    minHeight: kTouchTarget,
                  ),
                  color: AppColors.primary,
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => Speech.speak('Posisi $position: $label'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Naikkan $label',
                    button: true,
                    enabled: onUp != null,
                    onTap: onUp,
                    excludeSemantics: true,
                    child: FilledButton.icon(
                      style: _moveStyle,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      label: const Text('Naikkan'),
                      onPressed: onUp,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    label: 'Turunkan $label',
                    button: true,
                    enabled: onDown != null,
                    onTap: onDown,
                    excludeSemantics: true,
                    child: FilledButton.icon(
                      style: _moveStyle,
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      label: const Text('Turunkan'),
                      onPressed: onDown,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
