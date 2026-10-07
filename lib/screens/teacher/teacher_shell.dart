import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/playful.dart';
import '../profile_tab.dart';
import 'teacher_home_screen.dart';

/// Kerangka guru dengan menu bawah: Materi, Siswa, Hasil, Profil.
///
/// Di Figma ada tab "Games". Tab itu tidak ada di sini karena soal sekarang
/// dikelola di dalam tiap materi (satu materi, satu jenis soal).
class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: IndexedStack(
        index: _index,
        children: const [
          TeacherHomeScreen(),
          TeacherStudentsTab(),
          TeacherResultsTab(),
          ProfileTab(),
        ],
      ),
      bottomNavigationBar: AprevoNavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
        items: const [
          NavItem(
            label: 'Materi',
            icon: Icons.menu_book_outlined,
            selectedIcon: Icons.menu_book,
          ),
          NavItem(
            label: 'Siswa',
            icon: Icons.groups_outlined,
            selectedIcon: Icons.groups,
          ),
          NavItem(
            label: 'Hasil',
            icon: Icons.insights_outlined,
            selectedIcon: Icons.insights,
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

/// Rata-rata nilai (0 sampai 100) satu tes untuk satu materi, atau `null`
/// kalau belum ada siswa yang mengerjakannya.
int? _average(LessonMaterial m, TestKind kind) {
  var sum = 0.0;
  var count = 0;
  for (final name in m.students) {
    final attempt = store.latestAttempt(m, name, kind);
    if (attempt == null || attempt.total == 0) continue;
    sum += attempt.score / attempt.total;
    count++;
  }
  return count == 0 ? null : (sum / count * 100).round();
}

/// Tab Siswa: semua siswa dari seluruh materi guru.
class TeacherStudentsTab extends StatelessWidget {
  const TeacherStudentsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Siswa'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final names = <String>{
              for (final m in store.materials) ...m.students,
            }.toList()
              ..sort();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SectionTitle('${names.length} siswa bergabung'),
                if (names.isEmpty)
                  const EmptyState(
                    message: 'Belum ada siswa. Bagikan kode akses materi '
                        'ke siswamu.',
                  ),
                for (final name in names)
                  ListRow(
                    icon: Icons.person_outline,
                    title: name,
                    subtitle: _summary(name),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _summary(String name) {
    var joined = 0;
    var finished = 0;
    var stars = 0;
    for (final m in store.materials) {
      if (!m.students.contains(name)) continue;
      joined++;
      final post = store.latestAttempt(m, name, TestKind.post);
      if (post != null) {
        finished++;
        stars += post.stars;
      }
    }
    return 'Mengikuti $joined materi, selesai $finished, $stars bintang';
  }
}

/// Tab Hasil: ringkasan pre-test dan post-test tiap materi.
class TeacherResultsTab extends StatelessWidget {
  const TeacherResultsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Hasil'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SectionTitle('Rata-rata nilai tiap materi'),
              if (store.materials.isEmpty)
                const EmptyState(message: 'Belum ada materi.'),
              for (final m in store.materials)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ResultCard(material: m),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.material});

  final LessonMaterial material;

  @override
  Widget build(BuildContext context) {
    final pre = _average(material, TestKind.pre);
    final post = _average(material, TestKind.post);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(material.title, style: AppType.titleLarge),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${material.students.length}',
                  label: 'Siswa',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: pre == null ? 'Belum ada' : '$pre',
                  label: 'Nilai pre-test',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: post == null ? 'Belum ada' : '$post',
                  label: 'Nilai post-test',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_change(pre, post), style: AppType.bodyMedium),
        ],
      ),
    );
  }

  String _change(int? pre, int? post) {
    if (pre == null || post == null) {
      return 'Perbandingan muncul setelah siswa mengerjakan pre-test dan '
          'post-test.';
    }
    final diff = post - pre;
    if (diff > 0) return 'Nilai naik $diff poin setelah belajar.';
    if (diff < 0) return 'Nilai turun ${-diff} poin. Materinya perlu diulang.';
    return 'Nilai pre-test dan post-test sama.';
  }
}
