import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';
import '../../widgets/mascot.dart';
import 'student_space_screen.dart';

/// Beranda siswa: memasukkan kode akses untuk menambah materi, dan daftar
/// materi yang sudah diikuti. Satu kode akses membuka satu materi.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key, required this.studentName});

  final String studentName;

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _error = message);
    Speech.announce(message);
  }

  void _open(LessonMaterial material) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialJourneyScreen(
          material: material,
          studentName: widget.studentName,
        ),
      ),
    );
  }

  void _join() {
    if (_code.text.trim().isEmpty) {
      _showError('Kode akses belum diisi.');
      return;
    }
    final material = store.joinMaterial(_code.text, widget.studentName);
    if (material == null) {
      _showError('Kode akses tidak ditemukan. Periksa lagi kode dari guru.');
      return;
    }
    FocusScope.of(context).unfocus();
    _code.clear();
    setState(() => _error = null);
    Speech.announce('Materi ${material.title} ditambahkan.');
    _open(material);
  }

  String _progress(LessonMaterial m) {
    final name = widget.studentName;
    final post = store.latestAttempt(m, name, TestKind.post);
    if (post != null) return 'Selesai, ${post.stars} dari 3 bintang';
    final pre = store.latestAttempt(m, name, TestKind.pre);
    if (pre != null) return 'Pre-test selesai, lanjut dengarkan materi';
    return 'Soal ${m.questionType.label}, belum dimulai';
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Materi Saya'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final materials = store.materialsOf(widget.studentName);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                MascotBubble(
                  text: 'Halo, ${widget.studentName}! Aku Odi. Masukkan '
                      'kode akses dari gurumu untuk membuka materi.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  style: AppType.bodyLarge,
                  decoration: fieldDecoration(
                    'Kode akses materi',
                    hint: 'Contoh: APV-7K29',
                  ),
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  // liveRegion: TalkBack langsung membacakan pesan ini.
                  Semantics(
                    liveRegion: true,
                    child: AppCard(
                      color: AppColors.dangerBg,
                      borderColor: AppColors.danger,
                      child: Text(
                        _error!,
                        style: AppType.bodyMedium.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                PrimaryButton(
                  label: 'Buka materi',
                  icon: Icons.key,
                  onPressed: _join,
                ),
                const SizedBox(height: 16),
                SectionTitle('Materi yang kamu ikuti (${materials.length})'),
                if (materials.isEmpty)
                  const EmptyState(
                    message: 'Belum ada materi. Masukkan kode akses di atas.',
                  ),
                for (final m in materials)
                  ListRow(
                    icon: gameIcon(m.questionType),
                    title: m.title,
                    subtitle: _progress(m),
                    semanticLabel: 'Materi ${m.title}. ${_progress(m)}',
                    onTap: () => _open(m),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
