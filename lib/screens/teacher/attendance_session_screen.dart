import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/attendance.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../../widgets/reload_timer.dart';

/// Satu sesi presensi untuk guru: rekap sesi, status tiap siswa yang bisa
/// diubah, tombol tutup sekarang, dan hapus sesi.
class AttendanceSessionScreen extends StatefulWidget {
  const AttendanceSessionScreen({
    super.key,
    required this.subject,
    required this.session,
  });

  final Subject subject;

  /// Sesi dari daftar, untuk judul layar. Datanya dimuat ulang.
  final AttendanceSession session;

  @override
  State<AttendanceSessionScreen> createState() =>
      _AttendanceSessionScreenState();
}

class _AttendanceSessionScreenState extends State<AttendanceSessionScreen> {
  bool _busy = false;
  String? _feedback;
  int _feedbackSerial = 0;

  String get _id => widget.session.id;

  void _say(String message) {
    setState(() {
      _busy = false;
      _feedback = message;
      _feedbackSerial++;
    });
  }

  Future<void> _changeStatus(AttendanceStudentRow student) async {
    final status = await showDialog<AttendanceStatus>(
      context: context,
      builder: (_) => _StatusDialog(student: student),
    );
    if (status == null || !mounted || status == student.status) return;
    setState(() => _busy = true);
    try {
      await store.setAttendanceStatus(_id, student.studentId, status);
      if (!mounted) return;
      _say('Status ${student.name} diubah menjadi ${status.word}.');
    } on ApiException catch (e) {
      if (!mounted) return;
      _say('Status ${student.name} belum diubah. ${e.message}');
    }
  }

  Future<void> _close(AttendanceSession session) async {
    setState(() => _busy = true);
    try {
      await store.closeAttendanceSession(_id);
      if (!mounted) return;
      _say(
        'Sesi ${session.title} ditutup. Siswa yang belum presensi '
        'tercatat alpa.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _say('Sesi belum ditutup. ${e.message}');
    }
  }

  Future<void> _delete(AttendanceSession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final style = TextButton.styleFrom(
          minimumSize: const Size(kTouchTarget, kTouchTarget),
        );
        return AlertDialog(
          title: Text('Hapus sesi ${session.title}?'),
          content: const Text(
            'Semua catatan presensi di sesi ini ikut terhapus dan tidak '
            'dihitung di rekap.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              style: style,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            TextButton(
              style: style,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ya, hapus sesi'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await store.deleteAttendanceSession(_id);
      if (!mounted) return;
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => announce('Sesi ${session.title} dihapus'),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _say('Sesi belum dihapus. ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar(widget.session.title),
      body: SafeArea(
        child: LoadView<AttendanceSessionDetail>(
          loadingMessage: 'Memuat presensi ${widget.session.title}.',
          load: () => store.attendanceSession(_id),
          builder: (context, data, reload) {
            final session = data.session;
            final counts = session.counts;
            return ReloadTimer(
              after: session.nextChange,
              reload: reload,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      session.title,
                      style: AppType.headlineMedium.copyWith(
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    container: true,
                    label: [
                      session.stateText(null),
                      if (counts != null) 'Rekap: ${counts.textWithPending}',
                    ].join('. '),
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.stateText(null),
                          style: AppType.bodyLarge.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                        if (counts != null)
                          Text(
                            'Rekap: ${counts.textWithPending}',
                            style: AppType.bodyMedium.copyWith(
                              color: AppColors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      key: ValueKey('feedback-$_feedbackSerial'),
                      container: true,
                      liveRegion: true,
                      label: _feedback,
                      excludeSemantics: true,
                      child: AppCard(
                        color: AppColors.highlight,
                        child: Text(_feedback!, style: AppType.titleMedium),
                      ),
                    ),
                  ],
                  if (session.isOpen) ...[
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Tutup sesi sekarang',
                      icon: Icons.lock_outline,
                      onPressed: _busy ? null : () => _close(session),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SectionTitle('Siswa (${data.students.length})'),
                  if (data.students.isEmpty)
                    const EmptyState(
                      message: 'Belum ada siswa yang dihitung di sesi ini.',
                    ),
                  for (final student in data.students)
                    ListRow(
                      key: ValueKey(student.studentId),
                      icon: Icons.person_outline,
                      title: student.name,
                      subtitle: student.statusText,
                      semanticLabel: '${student.label}. Ubah status',
                      onTap: _busy ? null : () => _changeStatus(student),
                    ),
                  // Paling bawah dan berjarak, supaya tidak tertekan tanpa
                  // sengaja.
                  const SizedBox(height: 48),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus sesi'),
                    onPressed: _busy ? null : () => _delete(session),
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

/// Pilihan status untuk satu siswa. Empat tombol biasa, status sekarang
/// ditandai terpilih.
class _StatusDialog extends StatelessWidget {
  const _StatusDialog({required this.student});

  final AttendanceStudentRow student;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('Status ${student.name}'),
      children: [
        for (final status in AttendanceStatus.values)
          Semantics(
            label: status == student.status
                ? '${status.label}, status sekarang'
                : status.label,
            button: true,
            selected: status == student.status,
            onTap: () => Navigator.pop(context, status),
            excludeSemantics: true,
            child: SimpleDialogOption(
              onPressed: () => Navigator.pop(context, status),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kTouchTarget),
                child: Row(
                  children: [
                    Icon(
                      status == student.status
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(status.label, style: AppType.titleMedium),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kTouchTarget, kTouchTarget),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ),
      ],
    );
  }
}
