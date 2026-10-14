import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';
import '../student/student_space_screen.dart';
import 'question_form_screen.dart';

/// Guru mengatur satu materi: memilih SATU jenis soal, lalu mengisi
/// pre-test dan post-test dengan jenis itu, manual atau lewat AI.
/// Soal dari AI masuk ke daftar yang sama, jadi tetap bisa direview,
/// diubah, dan dihapus sebelum dipublikasikan.
class MaterialEditorScreen extends StatefulWidget {
  const MaterialEditorScreen({
    super.key,
    required this.material,
  });

  final LessonMaterial material;

  @override
  State<MaterialEditorScreen> createState() => _MaterialEditorScreenState();
}

class _MaterialEditorScreenState extends State<MaterialEditorScreen> {
  TestKind? _generating;

  LessonMaterial get _m => widget.material;

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Simpan perubahan ke store dan gambar ulang layar ini.
  void _changed(VoidCallback change) {
    setState(change);
    store.touch();
  }

  Future<void> _addOrEdit(TestKind kind, {int? index}) async {
    final list = _m.questionsFor(kind);
    final result = await Navigator.push<Question>(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionFormScreen(
          type: _m.questionType,
          initial: index == null ? null : list[index],
        ),
      ),
    );
    if (result == null || !mounted) return;
    _changed(() {
      if (index == null) {
        list.add(result);
      } else {
        list[index] = result;
      }
    });
  }

  Future<void> _generate(TestKind kind) async {
    setState(() => _generating = kind);
    final generated = await store.generateQuestions(_m.questionType, _m);
    if (!mounted) return;
    _changed(() {
      _generating = null;
      _m.questionsFor(kind).addAll(generated);
    });
    Speech.announce(
      '${generated.length} soal ${kind.label} dibuat. Periksa sebelum '
      'dipublikasikan.',
    );
  }

  void _copyPreToPost() {
    _changed(() => _m.postTest.addAll(_m.preTest));
    _toast('Soal pre-test disalin ke post-test.');
  }

  void _setPublished(bool value) {
    if (value && (_m.preTest.isEmpty || _m.postTest.isEmpty)) {
      _toast('Isi dulu pre-test dan post-test, minimal satu soal.');
      return;
    }
    setState(() {});
    store.setPublished(_m, value);
    Speech.announce(value ? 'Materi dipublikasikan.' : 'Materi jadi draf.');
  }

  @override
  Widget build(BuildContext context) {
    final locked = _m.hasQuestions;
    return PurpleScaffold(
      appBar: aprevoAppBar(_m.title),
      body: SafeArea(
        child: ListView(
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
                        'Soal ${_m.questionType.label}',
                        icon: gameIcon(_m.questionType),
                        color: const Color(0x33FFFFFF),
                        textColor: AppColors.white,
                      ),
                      Pill(
                        _m.published ? 'Publik' : 'Draf',
                        color: _m.published
                            ? AppColors.accent
                            : const Color(0x33FFFFFF),
                        textColor:
                            _m.published ? AppColors.ink : AppColors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    child: Text(
                      _m.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _m.published
                        ? 'Bagikan kode akses ini ke siswa.'
                        : 'Kode baru bisa dipakai setelah materi '
                            'dipublikasikan.',
                    style: const TextStyle(color: AppColors.white),
                  ),
                  const SizedBox(height: 12),
                  CodeBox(code: _m.accessCode, onDark: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListRow(
              icon: Icons.menu_book_outlined,
              title: 'Baca materi',
              subtitle: _m.body.isEmpty
                  ? 'Isi materi masih kosong'
                  : (_m.body.length > 70
                      ? '${_m.body.substring(0, 70)}...'
                      : _m.body),
              semanticLabel: 'Baca materi ${_m.title}',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MaterialReaderScreen(material: _m),
                ),
              ),
            ),
            const SectionTitle('Jenis soal materi ini'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in GameType.values)
                  ChoiceChip(
                    avatar: Icon(gameIcon(t), size: 18),
                    label: Text(t.label),
                    selected: _m.questionType == t,
                    onSelected: locked
                        ? null
                        : (_) => _changed(() => _m.questionType = t),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                locked
                    ? 'Jenis soal terkunci karena sudah ada soal. Hapus semua '
                        'soal untuk menggantinya.'
                    : 'Satu materi memakai satu jenis soal untuk pre-test '
                        'dan post-test.',
                style: AppType.bodySmall,
              ),
            ),
            ..._testSection(TestKind.pre),
            ..._testSection(TestKind.post),
            const SizedBox(height: 16),
            AppCard(
              color: _m.published ? AppColors.mint : AppColors.soft,
              borderColor: AppColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: SwitchListTile(
                value: _m.published,
                onChanged: _setPublished,
                title: Text('Publikasikan ke siswa', style: AppType.titleMedium),
                subtitle: Text(
                  _m.published
                      ? 'Siswa di ruang ini bisa melihat materi ini'
                      : 'Masih draf, siswa belum bisa melihat',
                  style: AppType.bodySmall,
                ),
              ),
            ),
            SectionTitle('Siswa (${_m.students.length})'),
            if (_m.students.isEmpty)
              const EmptyState(
                message: 'Belum ada siswa yang bergabung ke materi ini.',
              ),
            for (final name in _m.students)
              ListRow(
                icon: Icons.person_outline,
                title: name,
                subtitle: _resultOf(name),
              ),
          ],
        ),
      ),
    );
  }

  /// Ringkasan hasil pre-test dan post-test seorang siswa.
  String _resultOf(String name) {
    String part(TestKind kind) {
      final a = store.latestAttempt(_m, name, kind);
      if (a == null) return '${kind.label} belum dikerjakan';
      return '${kind.label} benar ${a.score} dari ${a.total}, '
          '${a.stars} bintang';
    }

    return '${part(TestKind.pre)}. ${part(TestKind.post)}';
  }

  List<Widget> _testSection(TestKind kind) {
    final list = _m.questionsFor(kind);
    final busy = _generating != null;
    return [
      SectionTitle('${kind.label} (${list.length} soal)'),
      for (var i = 0; i < list.length; i++)
        ListRow(
          icon: gameIcon(_m.questionType),
          title: 'Soal ${i + 1}',
          subtitle: list[i].prompt,
          semanticLabel:
              '${kind.label} soal ${i + 1}. ${list[i].prompt}. '
              'Ketuk untuk ubah',
          onTap: () => _addOrEdit(kind, index: i),
          trailing: IconButton(
            tooltip: 'Hapus ${kind.label} soal ${i + 1}',
            color: AppColors.danger,
            constraints: const BoxConstraints(
              minWidth: kTouchTarget,
              minHeight: kTouchTarget,
            ),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _changed(() => list.removeAt(i)),
          ),
        ),
      if (_generating == kind)
        Semantics(
          liveRegion: true,
          label: 'AI sedang membuat soal',
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: Text('Tambah soal ${kind.label}'),
        onPressed: busy ? null : () => _addOrEdit(kind),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.auto_awesome),
        label: Text('Buat soal ${kind.label} dengan AI'),
        onPressed: busy ? null : () => _generate(kind),
      ),
      if (kind == TestKind.post && list.isEmpty && _m.preTest.isNotEmpty) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_all),
          label: const Text('Salin soal dari pre-test'),
          onPressed: busy ? null : _copyPreToPost,
        ),
      ],
      const SizedBox(height: 16),
    ];
  }
}
