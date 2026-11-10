/// Presensi per pertemuan, dari endpoint `/…/attendance` backend.
///
/// Status sesi (belum dibuka, terbuka, ditutup) dihitung backend dengan jam
/// server. Aplikasi tidak membandingkan waktu dengan jam HP: kapan sesi
/// berubah dibaca dari `seconds_until_open` dan `seconds_until_close`.
library;

import '../services/time_format.dart';

enum AttendanceStatus {
  hadir('Hadir'),
  izin('Izin'),
  sakit('Sakit'),
  alpa('Alpa');

  const AttendanceStatus(this.label);

  /// "Hadir", untuk tombol dan judul.
  final String label;

  /// "hadir", untuk kalimat.
  String get word => name;

  static AttendanceStatus? parse(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

enum SessionState {
  upcoming,
  open,
  closed;

  static SessionState parse(Object? value) => switch (value) {
    'upcoming' => upcoming,
    'open' => open,
    _ => closed,
  };
}

/// Pilihan cepat waktu tutup. Dihitung backend dari jam server.
enum ClosePreset {
  min15('15m', '15 menit'),
  min30('30m', '30 menit'),
  hour1('1h', '1 jam'),
  endOfDay('end_of_day', 'Akhir hari');

  const ClosePreset(this.value, this.label);

  final String value;
  final String label;
}

int _int(Object? value) => value is num ? value.toInt() : 0;

/// Jumlah tiap status. [belum] hanya ada di rekap sesi yang masih terbuka.
class AttendanceCounts {
  const AttendanceCounts({
    this.hadir = 0,
    this.izin = 0,
    this.sakit = 0,
    this.alpa = 0,
    this.belum = 0,
  });

  factory AttendanceCounts.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return AttendanceCounts(
      hadir: _int(map['hadir']),
      izin: _int(map['izin']),
      sakit: _int(map['sakit']),
      alpa: _int(map['alpa']),
      belum: _int(map['belum']),
    );
  }

  final int hadir;
  final int izin;
  final int sakit;
  final int alpa;
  final int belum;

  int of(AttendanceStatus status) => switch (status) {
    AttendanceStatus.hadir => hadir,
    AttendanceStatus.izin => izin,
    AttendanceStatus.sakit => sakit,
    AttendanceStatus.alpa => alpa,
  };

  /// "hadir 5, izin 1, sakit 0, alpa 2"
  String get text => [
    for (final status in AttendanceStatus.values)
      '${status.word} ${of(status)}',
  ].join(', ');

  /// Seperti [text], ditambah "belum presensi 3" kalau ada.
  String get textWithPending =>
      belum == 0 ? text : '$text, belum presensi $belum';
}

/// "ditutup pukul 10.00" kalau di hari yang sama dengan [reference],
/// selain itu "ditutup Selasa, 11 November 2026 pukul 10.00".
String closingPhrase(DateTime closesAt, DateTime? reference) {
  final close = closesAt.toLocal();
  final ref = reference?.toLocal();
  final sameDay =
      ref != null &&
      ref.year == close.year &&
      ref.month == close.month &&
      ref.day == close.day;
  return sameDay
      ? 'ditutup pukul ${formatClock(close)}'
      : 'ditutup ${formatDateTime(close)}';
}

class AttendanceSession {
  AttendanceSession({
    required this.id,
    required this.title,
    required this.opensAt,
    required this.closesAt,
    required this.state,
    this.secondsUntilOpen,
    this.secondsUntilClose,
    this.counts,
    this.status,
    this.byTeacher = false,
  });

  factory AttendanceSession.fromJson(Map<String, dynamic> json) {
    int? seconds(Object? v) => v is num ? v.toInt() : null;
    return AttendanceSession(
      id: '${json['id']}',
      title: '${json['title'] ?? ''}',
      opensAt: parseTime(json['opens_at']) ?? DateTime(2000),
      closesAt: parseTime(json['closes_at']) ?? DateTime(2000),
      state: SessionState.parse(json['state']),
      secondsUntilOpen: seconds(json['seconds_until_open']),
      secondsUntilClose: seconds(json['seconds_until_close']),
      counts: json.containsKey('counts')
          ? AttendanceCounts.fromJson(json['counts'])
          : null,
      status: AttendanceStatus.parse(json['status']),
      byTeacher: json['source'] == 'guru',
    );
  }

  final String id;
  final String title;
  final DateTime opensAt;
  final DateTime closesAt;
  final SessionState state;
  final int? secondsUntilOpen;
  final int? secondsUntilClose;

  /// Rekap sesi, hanya di data guru.
  final AttendanceCounts? counts;

  /// Status siswa yang membuka, hanya di data siswa. `null` berarti belum
  /// presensi di sesi yang belum tutup.
  final AttendanceStatus? status;
  final bool byTeacher;

  bool get isOpen => state == SessionState.open;

  /// Kapan status sesi berubah menurut server (buka atau tutup).
  Duration? get nextChange {
    final seconds = state == SessionState.upcoming
        ? secondsUntilOpen
        : secondsUntilClose;
    return seconds == null ? null : Duration(seconds: seconds);
  }

  /// "Terbuka, ditutup pukul 10.30", "Belum dibuka, dibuka Senin, ... pukul
  /// 09.00", atau "Ditutup Senin, ... pukul 10.30".
  String stateText(DateTime? reference) => switch (state) {
    SessionState.open => 'Terbuka, ${closingPhrase(closesAt, reference)}',
    SessionState.upcoming =>
      'Belum dibuka, dibuka ${formatDateTime(opensAt)}, '
          '${closingPhrase(closesAt, opensAt)}',
    SessionState.closed => 'Ditutup ${formatDateTime(closesAt)}',
  };

  /// Status siswa dalam kalimat, untuk riwayat siswa.
  String get myStatusText {
    final status = this.status;
    if (status == null) {
      return state == SessionState.upcoming ? 'Belum dibuka' : 'Belum presensi';
    }
    return byTeacher ? '${status.label}, dicatat guru' : status.label;
  }
}

class StudentAttendance {
  StudentAttendance({
    required this.serverTime,
    required this.counts,
    required this.sessions,
  });

  factory StudentAttendance.fromJson(Map<String, dynamic> json) =>
      StudentAttendance(
        serverTime: parseTime(json['server_time']),
        counts: AttendanceCounts.fromJson(json['counts']),
        sessions: [
          for (final s in json['sessions'] as List? ?? const [])
            AttendanceSession.fromJson(s as Map<String, dynamic>),
        ],
      );

  final DateTime? serverTime;
  final AttendanceCounts counts;
  final List<AttendanceSession> sessions;

  /// Sesi yang bisa diisi sekarang: terbuka dan belum ada catatan.
  List<AttendanceSession> get waiting => [
    for (final s in sessions)
      if (s.isOpen && s.status == null) s,
  ];
}

class TeacherAttendance {
  TeacherAttendance({required this.serverTime, required this.sessions});

  factory TeacherAttendance.fromJson(Map<String, dynamic> json) =>
      TeacherAttendance(
        serverTime: parseTime(json['server_time']),
        sessions: [
          for (final s in json['sessions'] as List? ?? const [])
            AttendanceSession.fromJson(s as Map<String, dynamic>),
        ],
      );

  final DateTime? serverTime;
  final List<AttendanceSession> sessions;
}

class AttendanceStudentRow {
  AttendanceStudentRow({
    required this.studentId,
    required this.name,
    this.status,
    this.byTeacher = false,
  });

  factory AttendanceStudentRow.fromJson(Map<String, dynamic> json) =>
      AttendanceStudentRow(
        studentId: '${json['student_id']}',
        name: '${json['name'] ?? ''}',
        status: AttendanceStatus.parse(json['status']),
        byTeacher: json['source'] == 'guru',
      );

  final String studentId;
  final String name;
  final AttendanceStatus? status;
  final bool byTeacher;

  String get statusText {
    final status = this.status;
    if (status == null) return 'belum presensi';
    return byTeacher ? '${status.word}, diubah guru' : status.word;
  }

  /// "Andi: hadir"
  String get label => '$name: $statusText';
}

class AttendanceSessionDetail {
  AttendanceSessionDetail({required this.session, required this.students});

  factory AttendanceSessionDetail.fromJson(Map<String, dynamic> json) =>
      AttendanceSessionDetail(
        session: AttendanceSession.fromJson(
          json['session'] as Map<String, dynamic>,
        ),
        students: [
          for (final s in json['students'] as List? ?? const [])
            AttendanceStudentRow.fromJson(s as Map<String, dynamic>),
        ],
      );

  final AttendanceSession session;
  final List<AttendanceStudentRow> students;
}

class AttendanceSummaryRow {
  AttendanceSummaryRow({
    required this.studentId,
    required this.name,
    required this.counts,
  });

  factory AttendanceSummaryRow.fromJson(Map<String, dynamic> json) =>
      AttendanceSummaryRow(
        studentId: '${json['student_id']}',
        name: '${json['name'] ?? ''}',
        counts: AttendanceCounts.fromJson(json['counts']),
      );

  final String studentId;
  final String name;
  final AttendanceCounts counts;

  /// "Andi: hadir 5, izin 1, sakit 0, alpa 2"
  String get label => '$name: ${counts.text}';
}

class AttendanceSummary {
  AttendanceSummary({required this.sessionCount, required this.students});

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) =>
      AttendanceSummary(
        sessionCount: _int(json['session_count']),
        students: [
          for (final s in json['students'] as List? ?? const [])
            AttendanceSummaryRow.fromJson(s as Map<String, dynamic>),
        ],
      );

  final int sessionCount;
  final List<AttendanceSummaryRow> students;
}

/// Waktu terdekat sesi mana pun berubah status menurut server, untuk memuat
/// ulang layar tepat saat sesi dibuka atau ditutup.
Duration? nextChangeOf(Iterable<AttendanceSession> sessions) {
  Duration? soonest;
  for (final session in sessions) {
    final change = session.nextChange;
    if (change == null) continue;
    if (soonest == null || change < soonest) soonest = change;
  }
  return soonest;
}
