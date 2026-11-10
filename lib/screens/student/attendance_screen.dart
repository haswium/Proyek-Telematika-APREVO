import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/attendance.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';
import '../../widgets/reload_timer.dart';

/// Label tombol Hadir, misalnya "Hadir untuk Pertemuan 3, ditutup pukul
/// 10.00". Jam tutup disebut supaya siswa tahu batasnya tanpa melihat layar.
String presentButtonLabel(AttendanceSession session, DateTime? serverTime) =>
    'Hadir untuk ${session.title}, '
    '${closingPhrase(session.closesAt, serverTime)}';

/// "Pertemuan 3: Hadir. Ditutup Senin, 9 November 2026 pukul 10.00"
String historyLabel(AttendanceSession session, DateTime? serverTime) =>
    '${session.title}: ${session.myStatusText}. '
    '${session.stateText(serverTime)}';

/// Presensi siswa di satu kelas: tombol Hadir untuk sesi yang terbuka, rekap
/// jumlah tiap status, dan riwayat tiap sesi.
///
/// Tidak ada gestur geser. Hasil menekan Hadir (berhasil atau ditolak)
/// dibacakan lewat liveRegion, karena tombolnya ikut hilang.
class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  String? _busyId;
  String? _feedback;
  int _feedbackSerial = 0;

  void _say(String message) {
    setState(() {
      _feedback = message;
      _feedbackSerial++;
    });
  }

  Future<void> _present(AttendanceSession session, VoidCallback reload) async {
    if (_busyId != null) return;
    setState(() => _busyId = session.id);
    try {
      await store.markPresent(session.id);
      if (!mounted) return;
      _say('Presensi tercatat: hadir di ${session.title}.');
    } on ApiException catch (e) {
      if (!mounted) return;
      _say('Presensi belum tercatat. ${e.message}');
      // Status sesi mungkin sudah berubah (ditutup, atau diisi guru).
      reload();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    return PurpleScaffold(
      appBar: aprevoAppBar('Presensi'),
      body: SafeArea(
        child: LoadView<StudentAttendance>(
          loadingMessage: 'Memuat presensi ${subject.name}.',
          load: () => store.studentAttendance(subject.id),
          builder: (context, data, reload) {
            final waiting = data.waiting;
            return ReloadTimer(
              after: nextChangeOf(data.sessions),
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
                  const SizedBox(height: 8),
                  const SectionTitle('Sesi terbuka'),
                  if (waiting.isEmpty)
                    const EmptyState(
                      message: 'Tidak ada sesi presensi yang menunggu kamu.',
                    ),
                  for (final session in waiting)
                    Padding(
                      key: ValueKey('hadir-${session.id}'),
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Semantics(
                        label: _busyId == session.id
                            ? 'Mengirim presensi ${session.title}'
                            : presentButtonLabel(session, data.serverTime),
                        button: true,
                        enabled: _busyId == null,
                        onTap: _busyId == null
                            ? () => _present(session, reload)
                            : null,
                        excludeSemantics: true,
                        child: PrimaryButton(
                          label: _busyId == session.id
                              ? 'Mengirim...'
                              : presentButtonLabel(session, data.serverTime),
                          icon: Icons.front_hand_outlined,
                          onPressed: _busyId == null
                              ? () => _present(session, reload)
                              : null,
                        ),
                      ),
                    ),
                  const SectionTitle('Rekap kamu'),
                  _CountsRow(counts: data.counts),
                  const SizedBox(height: 16),
                  SectionTitle('Riwayat presensi (${data.sessions.length})'),
                  if (data.sessions.isEmpty)
                    const EmptyState(
                      message: 'Guru belum membuka sesi presensi.',
                    ),
                  for (final session in data.sessions)
                    ListRow(
                      key: ValueKey(session.id),
                      icon: _iconFor(session.status),
                      title: '${session.title}: ${session.myStatusText}',
                      subtitle: session.stateText(data.serverTime),
                      semanticLabel: historyLabel(session, data.serverTime),
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

IconData _iconFor(AttendanceStatus? status) => switch (status) {
  AttendanceStatus.hadir => Icons.check_circle_outline,
  AttendanceStatus.izin => Icons.mail_outline,
  AttendanceStatus.sakit => Icons.healing_outlined,
  AttendanceStatus.alpa => Icons.cancel_outlined,
  null => Icons.schedule,
};

/// Empat kotak jumlah, dibaca sebagai satu kalimat: "Rekap kamu: hadir 5,
/// izin 1, sakit 0, alpa 2".
class _CountsRow extends StatelessWidget {
  const _CountsRow({required this.counts});

  final AttendanceCounts counts;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Rekap kamu: ${counts.text}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final status in AttendanceStatus.values) ...[
            if (status != AttendanceStatus.values.first)
              const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                value: '${counts.of(status)}',
                label: status.label,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Menu Presensi di halaman kelas siswa. Kalau ada sesi yang menunggu,
/// labelnya menyebutkan, misalnya "Presensi. 1 sesi terbuka, tekan Hadir".
/// Kalau presensi gagal dimuat, menu tetap tampil tanpa jumlah: halaman kelas
/// tidak ikut gagal.
class StudentAttendanceMenuRow extends StatefulWidget {
  const StudentAttendanceMenuRow({super.key, required this.subject});

  final Subject subject;

  @override
  State<StudentAttendanceMenuRow> createState() =>
      _StudentAttendanceMenuRowState();
}

class _StudentAttendanceMenuRowState extends State<StudentAttendanceMenuRow> {
  int? _waiting;
  Duration? _nextChange;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    store.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    store.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++_serial;
    try {
      final data = await store.studentAttendance(widget.subject.id);
      if (!mounted || serial != _serial) return;
      setState(() {
        _waiting = data.waiting.length;
        _nextChange = nextChangeOf(data.sessions);
      });
    } catch (_) {
      if (!mounted || serial != _serial) return;
      setState(() {
        _waiting = null;
        _nextChange = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _waiting ?? 0;
    final subtitle = waiting > 0
        ? '$waiting sesi terbuka, tekan Hadir'
        : 'Tekan Hadir saat guru membuka sesi, dan lihat riwayatmu';
    return ReloadTimer(
      after: _nextChange,
      reload: _load,
      child: ListRow(
        icon: Icons.how_to_reg_outlined,
        title: 'Presensi',
        subtitle: subtitle,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentAttendanceScreen(subject: widget.subject),
          ),
        ),
      ),
    );
  }
}
