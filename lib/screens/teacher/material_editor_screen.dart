import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/announce.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../student/section_reader_screen.dart';
import 'question_form_screen.dart';
import 'quiz_schedule_screen.dart';
import 'results_screen.dart';

/// Data editor: materi beserta soal tersimpan pre-test dan post-test.
class _EditorData {
  _EditorData(this.material, this.quizzes);

  final LessonMaterial material;
  final Map<TestKind, TeacherQuiz?> quizzes;

  /// Jenis soal yang sudah dipakai soal tersimpan, atau `null`.
  GameType? get savedType {
    for (final q in quizzes.values) {
      if (q?.type != null) return q!.type;
    }
    return null;
  }

  int savedCount(TestKind kind) => quizzes[kind]?.questions.length ?? 0;
}

/// Guru mengatur satu materi: sub-bab hasil PDF, jadwal dan soal pre-test
/// serta post-test, lalu publikasi.
///
/// Satu materi memakai SATU jenis soal. Soal baru disusun dulu sebagai draf
/// di aplikasi (manual atau lewat AI), bisa diubah dan dihapus, lalu
/// dikirim ke server sekaligus. Soal yang sudah tersimpan hanya bisa
/// dilihat, karena backend belum punya endpoint ubah atau hapus soal.
class MaterialEditorScreen extends StatefulWidget {
  const MaterialEditorScreen({
    super.key,
    required this.subject,
    required this.material,
  });

  final Subject subject;
  final LessonMaterial material;

  @override
  State<MaterialEditorScreen> createState() => _MaterialEditorScreenState();
}

class _MaterialEditorScreenState extends State<MaterialEditorScreen> {
  final Map<TestKind, List<Question>> _drafts = {
    TestKind.pre: [],
    TestKind.post: [],
  };

  /// Jenis soal pilihan guru sebelum ada soal tersimpan.
  GameType _chosenType = GameType.quiz;

  /// Kuis yang sedang dibuatkan soal AI, atau sedang dikirim.
  TestKind? _generating;
  TestKind? _saving;
  bool _publishing = false;

  bool get _busy => _generating != null || _saving != null || _publishing;

  Future<_EditorData> _load() async {
    final m = await store.teacherMaterial(
      widget.subject.id,
      widget.material.id,
    );
    final pre = m.quiz(TestKind.pre);
    final post = m.quiz(TestKind.post);
    final quizzes = await Future.wait([
      pre == null ? Future.value(null) : store.teacherQuiz(pre),
      post == null ? Future.value(null) : store.teacherQuiz(post),
    ]);
    return _EditorData(m, {
      TestKind.pre: quizzes[0],
      TestKind.post: quizzes[1],
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _schedule(TestKind kind, QuizInfo? existing) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QuizScheduleScreen(
          materialId: widget.material.id,
          kind: kind,
          existing: existing,
        ),
      ),
    );
    // Store memberi tahu LoadView untuk memuat ulang setelah tersimpan.
  }

  Future<void> _addOrEdit(TestKind kind, GameType type, {int? index}) async {
    final list = _drafts[kind]!;
    final result = await Navigator.push<Question>(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionFormScreen(
          type: type,
          initial: index == null ? null : list[index],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        list.add(result);
      } else {
        list[index] = result;
      }
    });
    announce(
      index == null
          ? 'Soal draf ${kind.label} ditambahkan. Jangan lupa simpan ke '
                'server.'
          : 'Soal draf ${kind.label} diubah.',
    );
  }

  Future<void> _generate(TestKind kind, GameType type, String topic) async {
    setState(() => _generating = kind);
    final generated = await store.generateQuestions(type, topic);
    if (!mounted) return;
    setState(() {
      _generating = null;
      _drafts[kind]!.addAll(generated);
    });
    announce(
      '${generated.length} soal draf ${kind.label} dibuat. Periksa, lalu '
      'simpan ke server.',
    );
  }

  void _copyPreToPost(_EditorData data) {
    final pre = [
      ...?data.quizzes[TestKind.pre]?.questions,
      ..._drafts[TestKind.pre]!,
    ];
    setState(() {
      _drafts[TestKind.post]!.addAll([
        // Disalin sebagai draf baru (tanpa id) supaya dikirim ke post-test.
        for (final q in pre)
          Question(
            prompt: q.prompt,
            options: q.options,
            correctIndex: q.correctIndex,
            answerText: q.answerText,
            explanation: q.explanation,
          ),
      ]);
    });
    _toast('${pre.length} soal pre-test disalin ke draf post-test.');
  }

  Future<void> _saveDrafts(TestKind kind, QuizInfo quiz, GameType type) async {
    final drafts = _drafts[kind]!;
    if (drafts.isEmpty) return;
    setState(() => _saving = kind);
    announce('Menyimpan ${drafts.length} soal ${kind.label}.');
    try {
      await store.addQuestions(quiz.id, type, List.of(drafts));
      if (!mounted) return;
      final count = drafts.length;
      setState(() {
        _saving = null;
        drafts.clear();
      });
      _toast('$count soal ${kind.label} tersimpan di server.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = null);
      _toast('Soal ${kind.label} belum tersimpan. ${e.message}');
    }
  }

  Future<void> _setPublished(_EditorData data, bool value) async {
    if (value) {
      final missing = [
        for (final kind in TestKind.values)
          if (data.savedCount(kind) == 0) kind.label,
      ];
      if (missing.isNotEmpty) {
        _toast('Simpan dulu minimal satu soal untuk ${missing.join(' dan ')}.');
        return;
      }
    }
    setState(() => _publishing = true);
    try {
      await store.setPublished(data.material.id, value);
      if (!mounted) return;
      setState(() => _publishing = false);
      _toast(value ? 'Materi dipublikasikan.' : 'Materi jadi draf.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _toast('Status materi belum berubah. ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar(widget.material.title),
      body: SafeArea(
        child: LoadView<_EditorData>(
          loadingMessage: 'Memuat materi ${widget.material.title}.',
          load: _load,
          builder: (context, data, _) => _body(data),
        ),
      ),
    );
  }

  Widget _body(_EditorData data) {
    final m = data.material;
    final subject = widget.subject;
    final savedType = data.savedType;
    final type = savedType ?? _chosenType;
    final typeLocked =
        savedType != null || _drafts.values.any((d) => d.isNotEmpty);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    subject.name,
                    icon: Icons.folder_outlined,
                    color: const Color(0x33FFFFFF),
                    textColor: AppColors.white,
                  ),
                  Pill(
                    'Soal ${type.label}',
                    icon: gameIcon(type),
                    color: const Color(0x33FFFFFF),
                    textColor: AppColors.white,
                  ),
                  Pill(
                    m.published ? 'Publik' : 'Draf',
                    color: m.published
                        ? AppColors.accent
                        : const Color(0x33FFFFFF),
                    textColor: m.published ? AppColors.ink : AppColors.white,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  m.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                m.published
                    ? 'Publik, terlihat oleh siswa ${subject.name}.'
                    : 'Draf, belum terlihat oleh siswa.',
                style: const TextStyle(color: AppColors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ListRow(
          icon: Icons.menu_book_outlined,
          title: 'Lihat sub bab materi',
          subtitle: '${m.sectionCount} sub bab dari PDF',
          semanticLabel:
              'Lihat sub bab materi ${m.title}. ${m.sectionCount} sub bab '
              'dari PDF',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MaterialSectionsScreen(
                materialId: m.id,
                materialTitle: m.title,
              ),
            ),
          ),
        ),
        ListRow(
          icon: Icons.insights_outlined,
          title: 'Hasil siswa',
          subtitle: 'Nilai pre-test dan post-test tiap siswa',
          semanticLabel: 'Hasil siswa untuk materi ${m.title}',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MaterialResultScreen(
                subjectId: subject.id,
                materialId: m.id,
                materialTitle: m.title,
              ),
            ),
          ),
        ),
        const SectionTitle('Jenis soal materi ini'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in GameType.values)
              AppChoiceChip(
                icon: gameIcon(t),
                label: t.label,
                selected: type == t,
                onSelected: typeLocked
                    ? null
                    : (_) => setState(() => _chosenType = t),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            typeLocked
                ? 'Jenis soal terkunci karena sudah ada soal.'
                : 'Satu materi memakai satu jenis soal untuk pre-test dan '
                      'post-test.',
            style: AppType.bodySmall,
          ),
        ),
        for (final kind in TestKind.values) ..._testSection(data, kind, type),
        const SizedBox(height: 16),
        AppCard(
          color: m.published ? AppColors.mint : AppColors.soft,
          borderColor: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // Material transparan: ListTile menggambar efek sentuhnya di
          // Material terdekat, yang tertutup latar AppCard.
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              value: m.published,
              onChanged: _busy ? null : (v) => _setPublished(data, v),
              title: Text('Publikasikan ke siswa', style: AppType.titleMedium),
              subtitle: Text(
                _publishing
                    ? 'Sedang menyimpan...'
                    : m.published
                    ? 'Siswa ${subject.name} bisa melihat materi ini'
                    : 'Masih draf, siswa belum bisa melihat',
                style: AppType.bodySmall,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _testSection(_EditorData data, TestKind kind, GameType type) {
    final label = kind.label;
    final teacherQuiz = data.quizzes[kind];
    final info = data.material.quiz(kind);
    if (info == null) {
      return [
        SectionTitle(label),
        Text(
          'Belum ada $label. Buat dulu dengan jadwal buka dan tenggatnya.',
          style: AppType.bodyMedium,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event_outlined),
          label: Text('Buat $label'),
          onPressed: _busy ? null : () => _schedule(kind, null),
        ),
        const SizedBox(height: 16),
      ];
    }
    final saved = teacherQuiz?.questions ?? const <Question>[];
    final drafts = _drafts[kind]!;
    final preCount =
        data.savedCount(TestKind.pre) + _drafts[TestKind.pre]!.length;
    return [
      SectionTitle('$label (${saved.length} soal tersimpan)'),
      Text('${info.scheduleText}.', style: AppType.bodyMedium),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.edit_calendar_outlined),
        label: Text('Ubah jadwal $label'),
        onPressed: _busy ? null : () => _schedule(kind, info),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < saved.length; i++)
        ListRow(
          icon: gameIcon(type),
          title: 'Soal ${i + 1}',
          subtitle: saved[i].prompt,
          semanticLabel:
              '$label soal ${i + 1}, tersimpan. ${saved[i].prompt}. Jawaban '
              'benar: ${saved[i].correctText(type)}',
        ),
      for (var i = 0; i < drafts.length; i++)
        ListRow(
          icon: Icons.edit_note,
          title: 'Draf soal ${saved.length + i + 1}',
          subtitle: drafts[i].prompt,
          semanticLabel:
              '$label draf soal ${saved.length + i + 1}, belum tersimpan. '
              '${drafts[i].prompt}. Ketuk untuk ubah',
          onTap: _busy ? null : () => _addOrEdit(kind, type, index: i),
          trailing: IconButton(
            tooltip: 'Hapus draf $label soal ${saved.length + i + 1}',
            color: AppColors.danger,
            constraints: const BoxConstraints(
              minWidth: kTouchTarget,
              minHeight: kTouchTarget,
            ),
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy
                ? null
                : () {
                    setState(() => drafts.removeAt(i));
                    // Tombol yang difokus TalkBack ikut hilang, jadi beri tahu.
                    announce('Draf $label soal ${i + 1} dihapus.');
                  },
          ),
        ),
      if (_generating == kind)
        Semantics(
          container: true,
          liveRegion: true,
          label: 'AI sedang membuat soal $label. Tunggu sebentar.',
          excludeSemantics: true,
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      if (drafts.isNotEmpty) ...[
        PrimaryButton(
          label: _saving == kind
              ? 'Menyimpan...'
              : 'Simpan ${drafts.length} soal $label ke server',
          icon: Icons.cloud_upload_outlined,
          onPressed: _busy ? null : () => _saveDrafts(kind, info, type),
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: Text('Tambah soal $label'),
        onPressed: _busy ? null : () => _addOrEdit(kind, type),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.auto_awesome),
        label: Text('Buat soal $label dengan AI'),
        onPressed: _busy
            ? null
            : () => _generate(kind, type, data.material.title),
      ),
      if (kind == TestKind.post &&
          saved.isEmpty &&
          drafts.isEmpty &&
          preCount > 0) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_all),
          label: const Text('Salin soal dari pre-test'),
          onPressed: _busy ? null : () => _copyPreToPost(data),
        ),
      ],
      const SizedBox(height: 16),
    ];
  }
}
