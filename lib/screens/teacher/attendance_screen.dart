import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/attendance.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../../widgets/reload_timer.dart';
import 'attendance_session_form_screen.dart';
import 'attendance_session_screen.dart';

/// "Pertemuan 3. Terbuka, ditutup pukul 10.00. hadir 5, izin 0, sakit 0,
/// alpa 0, belum presensi 3"
String sessionRowLabel(AttendanceSession session, DateTime? serverTime) {
  final counts = session.counts;
  return [
    session.title,
    session.stateText(serverTime),
    ?counts?.textWithPending,
  ].join('. ');
}

class _TeacherAttendanceData {
  _TeacherAttendanceData(this.sessions, this.summary);

  final TeacherAttendance sessions;
  final AttendanceSummary summary;
}

/// Presensi satu kelas untuk guru: membuka sesi, daftar sesi dengan
/// rekapnya, dan rekap per siswa (jumlah tiap status).
class TeacherAttendanceScreen extends StatelessWidget {
  const TeacherAttendanceScreen({super.key, required this.subject});

  final Subject subject;

  Future<_TeacherAttendanceData> _load() async {
    final results = await Future.wait([
      store.attendanceSessions(subject.id),
      store.attendanceSummary(subject.id),
    ]);
    return _TeacherAttendanceData(
      results[0] as TeacherAttendance,
      results[1] as AttendanceSummary,
    );
  }

  void _create(BuildContext context, int sessionCount) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceSessionFormScreen(
          subject: subject,
          suggestedTitle: 'Pertemuan ${sessionCount + 1}',
        ),
      ),
    );
  }

  void _open(BuildContext context, AttendanceSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AttendanceSessionScreen(subject: subject, session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Presensi'),
      body: SafeArea(
        child: LoadView<_TeacherAttendanceData>(
          loadingMessage: 'Memuat presensi ${subject.name}.',
          load: _load,
          builder: (context, data, reload) {
            final sessions = data.sessions.sessions;
            final serverTime = data.sessions.serverTime;
            final students = data.summary.students;
            return ReloadTimer(
              after: nextChangeOf(sessions),
              reload: reload,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Presensi ${subject.name}',
                      style: AppType.headlineMedium.copyWith(
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Siswa yang tidak menekan Hadir sampai sesi ditutup '
                    'tercatat alpa. Kamu bisa mengubah status tiap siswa.',
                    style: AppType.bodyMedium.copyWith(color: AppColors.white),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Buka sesi presensi',
                    icon: Icons.add_circle_outline,
                    onPressed: () => _create(context, sessions.length),
                  ),
                  const SizedBox(height: 16),
                  SectionTitle('Sesi presensi (${sessions.length})'),
                  if (sessions.isEmpty)
                    const EmptyState(message: 'Belum ada sesi presensi.'),
                  for (final session in sessions)
                    ListRow(
                      key: ValueKey(session.id),
                      icon: session.isOpen
                          ? Icons.lock_open_outlined
                          : Icons.event_note_outlined,
                      title: session.title,
                      subtitle: [
                        session.stateText(serverTime),
                        ?session.counts?.textWithPending,
                      ].join('\n'),
                      semanticLabel: sessionRowLabel(session, serverTime),
                      onTap: () => _open(context, session),
                    ),
                  const SizedBox(height: 8),
                  SectionTitle('Rekap per siswa (${students.length})'),
                  if (students.isEmpty)
                    const EmptyState(message: 'Belum ada siswa di kelas ini.'),
                  for (final row in students)
                    ListRow(
                      key: ValueKey('rekap-${row.studentId}'),
                      icon: Icons.person_outline,
                      title: row.name,
                      subtitle: row.counts.text,
                      semanticLabel: row.label,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
