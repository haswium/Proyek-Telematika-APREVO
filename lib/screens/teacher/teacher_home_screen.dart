import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';
import 'material_editor_screen.dart';

/// Beranda guru, mengikuti desain Figma: kartu sambutan, tombol buat materi,
/// lalu kartu tiap materi dengan kode aksesnya sendiri.
class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({super.key});

  void _open(BuildContext context, LessonMaterial material) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialEditorScreen(material: material),
      ),
    );
  }

  Future<void> _createMaterial(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Materi baru'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: fieldDecoration('Judul materi'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                maxLines: 6,
                decoration: fieldDecoration('Isi materi'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lanjut buat soal'),
          ),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    // Kode akses materi dibuat otomatis di dalam createMaterial.
    final material = store.createMaterial(title.text.trim(), body.text.trim());
    if (!context.mounted) return;
    _open(context, material);
  }

  @override
  Widget build(BuildContext context) {
    final teacher = store.currentUser?.name ?? 'Guru';
    return PurpleScaffold(
      appBar: aprevoAppBar('Materi Saya'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final materials = store.materials;
            final published = materials.where((m) => m.published).length;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Pill(
                        '$published dari ${materials.length} materi publik',
                        color: const Color(0x33FFFFFF),
                        textColor: AppColors.white,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Selamat datang kembali',
                        style: TextStyle(color: AppColors.white, fontSize: 15),
                      ),
                      Semantics(
                        header: true,
                        child: Text(
                          teacher,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Satu materi, satu kode akses. Siswa bergabung '
                        'lewat kode materinya.',
                        style: TextStyle(color: AppColors.white, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Buat Materi Baru',
                  icon: Icons.add_circle_outline,
                  onPressed: () => _createMaterial(context),
                ),
                const SizedBox(height: 8),
                SectionTitle('Daftar materi (${materials.length})'),
                if (materials.isEmpty)
                  const EmptyState(message: 'Belum ada materi.'),
                for (var i = 0; i < materials.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 60 * (i > 5 ? 5 : i)),
                      child: _MaterialCard(
                        material: materials[i],
                        onOpen: () => _open(context, materials[i]),
                      ),
                    ),
                  ),
                if (materials.isNotEmpty)
                  Text(
                    'Ketuk "Kelola materi" untuk mengatur soal, melihat siswa, '
                    'dan hasil.',
                    style: AppType.bodySmall,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material, required this.onOpen});

  final LessonMaterial material;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final m = material;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(m.questionType.label, icon: gameIcon(m.questionType)),
              Pill(
                m.published ? 'Publik' : 'Draf',
                color: m.published ? AppColors.primary : AppColors.highlight,
                textColor: m.published ? AppColors.white : AppColors.ink,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              m.title,
              style: AppType.titleLarge,
            ),
          ),
          const SizedBox(height: 10),
          CodeBox(code: m.accessCode),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${m.students.length}',
                  label: 'Siswa',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '${m.preTest.length}',
                  label: 'Soal pre-test',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '${m.postTest.length}',
                  label: 'Soal post-test',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Bouncy(
            child: FilledButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Kelola materi'),
              onPressed: onOpen,
            ),
          ),
        ],
      ),
    );
  }
}
