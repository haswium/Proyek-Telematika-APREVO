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
  int _errorSerial = 0;

  @override
  void initState() {
    super.initState();
    store.loadStudentMaterials();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() {
      _error = message;
      _errorSerial++;
    });
    Speech.feedback(context, message);
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
    return 'Soal ${m.questionTypeLabel}, belum dimulai';
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
                  text:
                      'Halo, ${widget.studentName}! Aku Odi. Masukkan '
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
                  // liveRegion: TalkBack langsung membacakan pesan ini. Key
                  // baru tiap kali supaya pesan yang sama tetap dibacakan.
                  Semantics(
                    key: ValueKey('join-error-$_errorSerial'),
                    container: true,
                    liveRegion: true,
                    label: _error,
                    excludeSemantics: true,
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
                if (store.studentMaterialsLoading)
                  const _LoadingMaterials()
                else if (store.studentMaterialsError != null)
                  _LoadError(
                    message: store.studentMaterialsError!,
                    onRetry: store.loadStudentMaterials,
                  )
                else ...[
                  SectionTitle('Materi yang kamu ikuti (${materials.length})'),
                  if (materials.isEmpty)
                    const EmptyState(
                      message: 'Belum ada materi. Masukkan kode akses di atas.',
                    ),
                ],
                if (!store.studentMaterialsLoading)
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

/// Ditampilkan selama daftar materi diambil dari server.
/// `liveRegion` membuat TalkBack langsung membacakan pesannya.
class _LoadingMaterials extends StatelessWidget {
  const _LoadingMaterials();

  static const _message = 'Sedang memuat materimu. Tunggu sebentar.';

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Semantics(
      container: true,
      liveRegion: true,
      label: _message,
      excludeSemantics: true,
      child: AppCard(
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: still
                  ? const Icon(Icons.hourglass_top, color: AppColors.primary)
                  : const CircularProgressIndicator(
                      strokeWidth: 4,
                      color: AppColors.primary,
                    ),
            ),
            const SizedBox(width: 16),
            const Expanded(child: Text(_message, style: AppType.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// Pesan gagal memuat materi, dengan tombol untuk mencoba lagi.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: 'Gagal memuat materi. $message',
          excludeSemantics: true,
          child: AppCard(
            color: AppColors.dangerBg,
            borderColor: AppColors.danger,
            child: Text(
              'Gagal memuat materi. $message',
              style: AppType.bodyMedium.copyWith(color: AppColors.danger),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Coba lagi',
          icon: Icons.refresh,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
