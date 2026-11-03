import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import 'material_editor_screen.dart';
import 'quiz_schedule_screen.dart';

const int _minQuestions = 1;
const int _maxQuestions = 30;

class _FormData {
  _FormData(this.materials, {this.material, this.savedType});

  final List<LessonMaterial> materials;

  /// Materi terpilih versi terbaru dari server.
  final LessonMaterial? material;
  final GameType? savedType;
}

/// Guru memilih materi, pre-test atau post-test, jenis soal, dan jumlah soal,
/// lalu AI membuat draf soal dari teks materi di latar belakang.
///
/// Prosesnya dipantau [store], jadi guru boleh meninggalkan layar ini. Hasilnya
/// masuk ke draf di Kelola materi, untuk diperiksa sebelum disimpan.
class GenerateQuestionsScreen extends StatefulWidget {
  const GenerateQuestionsScreen({
    super.key,
    required this.subject,
    this.material,
    this.kind = TestKind.pre,
  });

  final Subject subject;

  /// Terisi kalau dibuka dari Kelola materi.
  final LessonMaterial? material;
  final TestKind kind;

  @override
  State<GenerateQuestionsScreen> createState() =>
      _GenerateQuestionsScreenState();
}

class _GenerateQuestionsScreenState extends State<GenerateQuestionsScreen> {
  late String? _materialId = widget.material?.id;
  late TestKind _kind = widget.kind;
  GameType? _chosenType;
  final _count = TextEditingController(text: '5');
  bool _starting = false;
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<_FormData> _load() async {
    final materials = await store.teacherMaterials(widget.subject.id);
    final id = _materialId;
    final material = materials.where((m) => m.id == id).firstOrNull;
    if (material == null) return _FormData(materials);
    await store.resumeQuestionGeneration(material.id);
    final quizzes = await Future.wait([
      for (final kind in TestKind.values)
        if (material.quiz(kind) case final info?) store.teacherQuiz(info),
    ]);
    return _FormData(
      materials,
      material: material,
      savedType: quizzes.map((q) => q.type).nonNulls.firstOrNull,
    );
  }

  void _pick(LessonMaterial material) {
    setState(() {
      _materialId = material.id;
      _chosenType = null;
      _error = null;
    });
    // Baris yang difokus TalkBack ikut hilang, jadi beri tahu.
    announce('Materi ${material.title} dipilih.');
  }

  Future<void> _start(LessonMaterial material, GameType type) async {
    final count = int.tryParse(_count.text.trim());
    if (count == null || count < _minQuestions || count > _maxQuestions) {
      setState(
        () =>
            _error = 'Jumlah soal harus $_minQuestions sampai $_maxQuestions.',
      );
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    String? error;
    try {
      await store.startQuestionGeneration(
        materialId: material.id,
        kind: _kind,
        type: type,
        count: count,
      );
    } on ApiException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = error;
    });
  }

  void _openDrafts(LessonMaterial material) {
    if (widget.material != null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MaterialEditorScreen(subject: widget.subject, material: material),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Buat soal dengan AI'),
      body: SafeArea(
        child: LoadView<_FormData>(
          // Muat ulang saat materi terpilih berganti.
          key: ValueKey(_materialId),
          loadingMessage: 'Memuat materi ${widget.subject.name}.',
          load: _load,
          builder: (context, data, _) {
            final material = data.material;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: material == null
                  ? _picker(data.materials)
                  : _form(data, material),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _picker(List<LessonMaterial> materials) {
    return [
      Semantics(
        header: true,
        child: Text('Pilih materi', style: AppType.headlineMedium),
      ),
      const SizedBox(height: 6),
      Text(
        'AI membuat soal dari teks materi yang sudah dikonversi.',
        style: AppType.bodyMedium,
      ),
      const SizedBox(height: 16),
      if (materials.isEmpty)
        const EmptyState(message: 'Belum ada materi di kelas ini.'),
      for (final m in materials)
        ListRow(
          icon: Icons.menu_book_outlined,
          title: m.title,
          semanticLabel: 'Pilih materi ${m.title}',
          onTap: () => _pick(m),
        ),
    ];
  }

  List<Widget> _form(_FormData data, LessonMaterial material) {
    final id = material.id;
    final typeLocked =
        data.savedType != null ||
        store.hasQuestionDrafts(id) ||
        store.isGeneratingQuestions(id);
    final type =
        data.savedType ?? store.draftType(id) ?? _chosenType ?? GameType.quiz;
    final generation = store.questionGeneration(id, _kind);
    final running = generation?.running ?? false;
    final hasSchedule = material.quiz(_kind) != null;
    final label = _kind.label;
    return [
      Semantics(
        header: true,
        child: Text(material.title, style: AppType.headlineMedium),
      ),
      const SizedBox(height: 6),
      Text(
        'AI membuat soal dari teks materi. AI bisa salah, jadi periksa setiap '
        'draf sebelum disimpan.',
        style: AppType.bodyMedium,
      ),
      if (widget.material == null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Ganti materi'),
          onPressed: () => setState(() {
            _materialId = null;
            _error = null;
          }),
        ),
      ],
      const SectionTitle('Untuk'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final kind in TestKind.values)
            AppChoiceChip(
              label: kind.label,
              selected: _kind == kind,
              onSelected: (_) => setState(() {
                _kind = kind;
                _error = null;
              }),
            ),
        ],
      ),
      const SectionTitle('Jenis soal'),
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
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          typeLocked
              ? 'Jenis soal terkunci karena materi ini sudah punya soal.'
              : 'Satu materi memakai satu jenis soal untuk pre-test dan '
                    'post-test.',
          style: AppType.bodySmall,
        ),
      ),
      const SectionTitle('Jumlah soal'),
      TextField(
        controller: _count,
        keyboardType: TextInputType.number,
        style: AppType.bodyLarge,
        decoration: fieldDecoration(
          'Jumlah soal, $_minQuestions sampai $_maxQuestions',
        ),
      ),
      const SizedBox(height: 20),
      if (!hasSchedule) ...[
        AppCard(
          color: AppColors.highlight,
          child: Text(
            '$label belum punya jadwal. Atur jadwalnya dulu supaya soal bisa '
            'disimpan.',
            style: AppType.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text('Atur jadwal $label'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QuizScheduleScreen(materialId: id, kind: _kind),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          label: running ? 'Sedang membuat soal...' : 'Buat soal $label',
          icon: Icons.auto_awesome,
          onPressed: !hasSchedule || running || _starting
              ? null
              : () => _start(material, type),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(_error!, style: AppType.bodyMedium),
        ),
      ],
      // Status sudah diumumkan oleh store, jadi bukan liveRegion.
      if (running || generation?.message != null) ...[
        const SizedBox(height: 12),
        Semantics(
          container: true,
          child: Text(
            running ? 'Sedang membuat soal $label' : generation!.message!,
            style: AppType.bodyMedium,
          ),
        ),
      ],
      if (!running && store.questionDrafts(id, _kind).isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_note),
            label: Text('Periksa draf $label'),
            onPressed: () => _openDrafts(material),
          ),
        ),
      ],
    ];
  }
}
