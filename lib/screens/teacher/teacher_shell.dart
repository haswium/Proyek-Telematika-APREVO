import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/playful.dart';
import '../profile_tab.dart';
import 'results_screen.dart';
import 'teacher_home_screen.dart';

/// Kerangka guru dengan menu bawah: Kelas, Siswa, Hasil, Profil.
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
            label: 'Kelas',
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

/// Satu siswa di semua kelas guru, disusun dari data hasil.
class _StudentSummary {
  _StudentSummary(this.name);

  final String name;
  final Set<String> subjects = {};
  int finished = 0;
  int stars = 0;
}

List<_StudentSummary> _students(List<SubjectResults> overview) {
  final byId = <String, _StudentSummary>{};
  for (final r in overview) {
    for (final m in r.materials) {
      for (final q in m.quizzes) {
        for (final s in q.students) {
          final summary = byId.putIfAbsent(
            s.studentId,
            () => _StudentSummary(s.name),
          );
          summary.subjects.add(r.subject.id);
          final latest = s.latest;
          if (q.kind == TestKind.post && latest != null) {
            summary.finished++;
            summary.stars += latest.stars;
          }
        }
      }
    }
  }
  return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Tab Siswa: semua siswa dari seluruh kelas guru.
///
/// Backend belum punya daftar anggota kelas, jadi siswa diambil dari data
/// hasil: siswa muncul setelah ada pre-test atau post-test di kelasnya.
class TeacherStudentsTab extends StatelessWidget {
  const TeacherStudentsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Siswa'),
      body: SafeArea(
        child: LoadView<List<SubjectResults>>(
          loadingMessage: 'Memuat daftar siswa.',
          load: store.teacherOverview,
          builder: (context, overview, _) {
            final students = _students(overview);
            final joined = overview.fold<int>(
              0,
              (sum, r) => sum + r.studentCount,
            );
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SectionTitle('${students.length} siswa'),
                Text(
                  'Total keanggotaan di semua kelas: $joined.',
                  style: AppType.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (students.isEmpty)
                  const EmptyState(
                    message:
                        'Belum ada siswa. Bagikan kode akses kelas ke '
                        'siswamu, lalu buat pre-test atau post-test.',
                  ),
                for (final s in students)
                  ListRow(
                    icon: Icons.person_outline,
                    title: s.name,
                    subtitle:
                        'Ikut ${s.subjects.length} kelas, '
                        'selesai ${s.finished} materi, ${s.stars} bintang',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tab Hasil: ringkasan pre-test dan post-test tiap materi, dikelompokkan
/// per kelas.
class TeacherResultsTab extends StatelessWidget {
  const TeacherResultsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Hasil'),
      body: SafeArea(
        child: LoadView<List<SubjectResults>>(
          loadingMessage: 'Memuat hasil siswa.',
          load: store.teacherOverview,
          builder: (context, overview, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Rata-rata nilai tiap materi dari siswa yang sudah '
                'mengumpulkan.',
                style: AppType.bodyMedium,
              ),
              const SizedBox(height: 8),
              if (overview.isEmpty)
                const EmptyState(message: 'Belum ada kelas.'),
              for (final r in overview) ...[
                SectionTitle(r.subject.name),
                if (r.materials.isEmpty)
                  const EmptyState(message: 'Belum ada materi.'),
                for (final m in r.materials)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: MaterialResultCard(
                      material: m,
                      studentCount: r.studentCount,
                      onOpen: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MaterialResultScreen(
                            subjectId: r.subject.id,
                            materialId: m.id,
                            materialTitle: m.title,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
