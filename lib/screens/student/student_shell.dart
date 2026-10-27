import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/mascot.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/playful.dart';
import '../profile_tab.dart';
import 'join_screen.dart';

/// Kerangka siswa dengan menu bawah: Belajar, Progres, Profil.
///
/// Di Figma ada tab "Games". Tab itu tidak ada di sini karena pre-test dan
/// post-test dibuka dari dalam materinya, jadi siswa cukup mengingat tiga tab.
class StudentShell extends StatefulWidget {
  const StudentShell({super.key, required this.studentName});

  final String studentName;

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: IndexedStack(
        index: _index,
        children: [
          StudentHomeScreen(studentName: widget.studentName),
          StudentProgressTab(studentName: widget.studentName),
          const ProfileTab(),
        ],
      ),
      bottomNavigationBar: AprevoNavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
        items: const [
          NavItem(
            label: 'Belajar',
            icon: Icons.headphones_outlined,
            selectedIcon: Icons.headphones,
          ),
          NavItem(
            label: 'Progres',
            icon: Icons.star_outline_rounded,
            selectedIcon: Icons.star_rounded,
          ),
          NavItem(
            label: 'Profil',
            icon: Icons.account_circle_outlined,
            selectedIcon: Icons.account_circle,
          ),
        ],
      ),
    );
  }
}

/// Tab Progres: bintang yang sudah dikumpulkan siswa di tiap materi,
/// dikelompokkan per kelas.
class StudentProgressTab extends StatelessWidget {
  const StudentProgressTab({super.key, required this.studentName});

  final String studentName;

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Progres'),
      body: SafeArea(
        child: LoadView<List<(Subject, List<LessonMaterial>)>>(
          loadingMessage: 'Memuat progres belajarmu.',
          load: store.studentProgress,
          builder: (context, groups, _) {
            var stars = 0;
            var finished = 0;
            var count = 0;
            for (final (_, materials) in groups) {
              for (final m in materials) {
                count++;
                final post = m.quiz(TestKind.post)?.latestAttempt;
                if (post != null) {
                  finished++;
                  stars += post.stars;
                }
              }
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                MascotBubble(
                  mood: stars > 0 ? MascotMood.cheer : MascotMood.happy,
                  text: groups.isEmpty
                      ? 'Belum ada kelas. Buka tab Belajar dan '
                            'masukkan kode dari gurumu.'
                      : 'Kamu sudah mengumpulkan $stars bintang dan '
                            'menyelesaikan $finished dari $count materi.',
                ),
                const SizedBox(height: 8),
                for (final (subject, materials) in groups) ...[
                  SectionTitle(subject.name),
                  if (materials.isEmpty)
                    const EmptyState(message: 'Belum ada materi.'),
                  for (final m in materials)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ProgressCard(
                        title: m.title,
                        pre: m.quiz(TestKind.pre)?.latestAttempt,
                        post: m.quiz(TestKind.post)?.latestAttempt,
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.pre,
    required this.post,
  });

  final String title;
  final Attempt? pre;
  final Attempt? post;

  String _line(String label, Attempt? attempt) => attempt == null
      ? '$label belum dikerjakan'
      : '$label: benar ${attempt.score} dari ${attempt.total}';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppType.titleLarge),
          ),
          const SizedBox(height: 8),
          Text(_line('Pre-test', pre), style: AppType.bodyMedium),
          Text(_line('Post-test', post), style: AppType.bodyMedium),
          const SizedBox(height: 10),
          StarRow(stars: post?.stars ?? 0, size: 40),
        ],
      ),
    );
  }
}
