import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/announce.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/mascot.dart';
import '../../widgets/playful.dart';
import 'result_screen.dart';

/// Layar pengerjaan pre-test atau post-test satu materi.
///
/// Soal diambil dari backend lalu percobaan dimulai (atau dilanjutkan kalau
/// ada yang belum dikumpulkan). Tiap jawaban dikirim ke server dan hanya
/// dijawab benar atau salah; jawaban benar dan pembahasan baru terbuka
/// setelah tenggat kuis lewat.
///
/// Urutan fokus TalkBack (lihat angka OrdinalSortKey):
/// 1 info soal, 4 pertanyaan, 5 jawaban, 6 umpan balik atau error, 7 tombol
/// periksa/lanjut.
class PlayGameScreen extends StatelessWidget {
  const PlayGameScreen({
    super.key,
    required this.quiz,
    required this.materialTitle,
    required this.studentName,
    this.preTest,
  });

  final QuizInfo quiz;
  final String materialTitle;
  final String studentName;

  /// Hasil pre-test siswa, untuk dibandingkan saat post-test selesai.
  final Attempt? preTest;

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('${quiz.kind.label}: $materialTitle'),
      body: SafeArea(
        child: LoadView<QuizSession>(
          listenToStore: false,
          loadingMessage: 'Menyiapkan soal ${quiz.kind.label}.',
          load: () => store.startQuiz(quiz.id),
          builder: (context, session, _) => session.questions.isEmpty
              ? const EmptyState(message: 'Kuis ini belum punya soal.')
              : _QuizRunner(
                  session: session,
                  quiz: quiz,
                  materialTitle: materialTitle,
                  studentName: studentName,
                  preTest: preTest,
                ),
        ),
      ),
    );
  }
}

class _QuizRunner extends StatefulWidget {
  const _QuizRunner({
    required this.session,
    required this.quiz,
    required this.materialTitle,
    required this.studentName,
    required this.preTest,
  });

  final QuizSession session;
  final QuizInfo quiz;
  final String materialTitle;
  final String studentName;
  final Attempt? preTest;

  @override
  State<_QuizRunner> createState() => _QuizRunnerState();
}

class _QuizRunnerState extends State<_QuizRunner> {
  static const List<Choice> _trueFalse = [
    Choice('true', 'Benar'),
    Choice('false', 'Salah'),
  ];

  final _answer = TextEditingController();

  int _index = 0;
  bool _answered = false;
  bool _correct = false;
  int? _picked;
  List<Choice> _order = [];

  /// Sedang mengirim jawaban atau mengumpulkan kuis.
  bool _busy = false;
  String? _error;
  int _errorSerial = 0;

  List<StudentQuestion> get _questions => widget.session.questions;
  StudentQuestion get _q => _questions[_index];
  GameType get _type => _q.type;
  int get _total => _questions.length;
  bool get _isLast => _index == _total - 1;

  List<Choice> get _choices =>
      _type == GameType.trueFalse ? _trueFalse : _q.choices;

  @override
  void initState() {
    super.initState();
    _prepare();
    // Tunggu layar tampil dulu supaya pengumuman tidak tertimpa pembacaan
    // judul halaman oleh TalkBack.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final resumed = widget.session.resumed
          ? 'Melanjutkan ${widget.quiz.kind.label} yang belum dikumpulkan. '
          : '';
      announce('$resumed${_questionIntro()}');
    });
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _prepare() {
    _answered = false;
    _correct = false;
    _picked = null;
    _error = null;
    _answer.clear();
    // Urutan item sudah diacak server.
    _order = _type == GameType.ordering ? List<Choice>.of(_q.choices) : [];
  }

  String _questionIntro() =>
      'Soal ${_index + 1} dari $_total. ${_type.instruction}';

  String _letter(int i) => String.fromCharCode(65 + i);

  bool get _canSubmit {
    if (_busy) return false;
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

  StudentAnswer _studentAnswer() {
    switch (_type) {
      case GameType.quiz:
        return StudentAnswer.option(_choices[_picked!].id);
      case GameType.trueFalse:
        return StudentAnswer.boolean(_picked == 0);
      case GameType.shortAnswer:
        return StudentAnswer.text(_answer.text.trim());
      case GameType.ordering:
        return StudentAnswer.order([for (final c in _order) c.id]);
    }
  }

  void _showError(String message) {
    setState(() {
      _busy = false;
      _error = message;
      _errorSerial++;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit || _answered) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    announce('Memeriksa jawaban.');
    try {
      final correct = await store.saveAnswer(
        widget.session.attemptId,
        _q.id,
        _studentAnswer(),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _answered = true;
        _correct = correct;
      });
      // TalkBack membacakan kartu umpan balik lewat liveRegion.
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Jawaban belum terkirim. ${e.message}');
    }
  }

  // ---- Umpan balik -------------------------------------------------------

  String get _headline =>
      _correct ? 'Benar! Hebat!' : 'Belum tepat, tidak apa-apa.';

  /// Jawaban yang diberikan siswa, dalam kalimat.
  String _yourAnswer() {
    switch (_type) {
      case GameType.quiz:
        return 'Pilihan ${_letter(_picked!)}, ${_choices[_picked!].text}';
      case GameType.trueFalse:
        return _choices[_picked!].text;
      case GameType.shortAnswer:
        return _answer.text.trim();
      case GameType.ordering:
        return _order.map((c) => c.text).join(', lalu ');
    }
  }

  /// Saat mengerjakan, siswa hanya diberi tahu benar atau salah. Jawaban
  /// benar dan pembahasan baru terbuka setelah tenggat.
  String _feedbackLabel() {
    final b = StringBuffer('$_headline Jawabanmu: ${_yourAnswer()}. ');
    if (!_correct) b.write('Tetap semangat, kamu pasti bisa!');
    return b.toString();
  }

  // ---- Navigasi ----------------------------------------------------------

  Future<void> _next() async {
    if (_busy) return;
    if (_isLast) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _prepare();
    });
    announce(_questionIntro());
  }

  Future<void> _finish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    announce('Mengumpulkan jawaban.');
    try {
      final result = await store.submitAttempt(widget.session.attemptId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            attemptId: result.attemptId,
            materialTitle: widget.materialTitle,
            kind: widget.quiz.kind,
            score: result.score,
            total: result.total,
            studentName: widget.studentName,
            deadlineAt: widget.quiz.deadlineAt,
            discussionAvailable: result.deadlinePassed,
            preTest: widget.preTest,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError('Jawaban belum terkumpul. ${e.message}');
    }
  }

  void _move(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= _order.length) return;
    setState(() {
      final item = _order.removeAt(from);
      _order.insert(to, item);
    });
    announce('${_order[to].text} pindah ke urutan ${to + 1}.');
  }

  // `container: true` supaya tiap bagian menjadi node sendiri; sortKey
  // hanya berlaku pada node.
  Widget _ordered(double order, Widget child) {
    return Semantics(
      container: true,
      sortKey: OrdinalSortKey(order),
      child: child,
    );
  }

  String get _actionLabel {
    if (!_answered) return _busy ? 'Memeriksa...' : 'Periksa Jawaban';
    if (!_isLast) return 'Soal berikutnya';
    return _busy ? 'Mengumpulkan...' : 'Kumpulkan dan lihat hasil';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
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
          4,
          // Key per soal supaya animasi masuk terulang tiap ganti soal.
          FadeSlideIn(
            key: ValueKey('prompt-$_index'),
            child: Text(_q.prompt, style: AppType.headlineMedium),
          ),
        ),
        const SizedBox(height: 20),
        _ordered(5, _buildAnswerArea()),
        const SizedBox(height: 8),
        if (_answered) ...[
          _ordered(6, _buildFeedback()),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[
          _ordered(
            6,
            ErrorCard(key: ErrorCard.keyFor(_errorSerial), message: _error!),
          ),
          const SizedBox(height: 16),
        ],
        _ordered(
          7,
          _answered
              ? PrimaryButton(
                  label: _actionLabel,
                  icon: Icons.arrow_forward,
                  onPressed: _busy ? null : _next,
                )
              : PrimaryButton(
                  label: _actionLabel,
                  icon: Icons.check,
                  onPressed: _canSubmit ? _submit : null,
                ),
        ),
      ],
    );
  }

  /// Kartu umpan balik: Odi, judul benar/salah, dan jawaban siswa. Dibaca
  /// TalkBack sebagai satu pesan utuh begitu muncul.
  Widget _buildFeedback() {
    final color = _correct ? AppColors.success : AppColors.danger;
    return Semantics(
      liveRegion: true,
      container: true,
      label: _feedbackLabel(),
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
              const SizedBox(height: 12),
              Text(
                'Jawabanmu',
                style: AppType.bodySmall.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(_yourAnswer(), style: AppType.bodyLarge),
              if (!_correct) ...[
                const SizedBox(height: 12),
                Text(
                  'Tetap semangat, kamu pasti bisa!',
                  style: AppType.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerArea() {
    final locked = _answered || _busy;
    switch (_type) {
      case GameType.quiz:
        return Column(
          children: [
            for (var i = 0; i < _choices.length; i++)
              Bouncy(
                child: _OptionTile(
                  badge: _letter(i),
                  label: _choices[i].text,
                  semanticLabel: 'Pilihan ${_letter(i)}, ${_choices[i].text}',
                  selected: _picked == i,
                  onTap: locked ? null : () => setState(() => _picked = i),
                ),
              ),
          ],
        );
      case GameType.trueFalse:
        return Column(
          children: [
            for (var i = 0; i < _choices.length; i++)
              Bouncy(
                child: _OptionTile(
                  badge: i == 0 ? 'B' : 'S',
                  label: _choices[i].text,
                  semanticLabel: _choices[i].text,
                  selected: _picked == i,
                  onTap: locked ? null : () => setState(() => _picked = i),
                ),
              ),
          ],
        );
      case GameType.shortAnswer:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _answer,
            enabled: !locked,
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
                label: _order[i].text,
                onUp: locked || i == 0 ? null : () => _move(i, -1),
                onDown: locked || i == _order.length - 1
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
/// dipindahkan dengan tombol "Naikkan" dan "Turunkan" yang berlabel teks.
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
            Semantics(
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
                        Text(label, style: AppType.titleMedium),
                      ],
                    ),
                  ),
                ],
              ),
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
