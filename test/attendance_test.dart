import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/attendance_screen.dart';
import 'package:aprevo/screens/teacher/attendance_screen.dart';
import 'package:aprevo/screens/teacher/attendance_session_form_screen.dart';
import 'package:aprevo/screens/teacher/attendance_session_screen.dart';
import 'package:aprevo/models/attendance.dart';
import 'package:aprevo/services/time_format.dart';

import 'fake_server.dart';

final _subject = Subject(id: 's1', name: '7 Geografi');

// Waktu lokal, supaya "pukul 10.00" sama di zona waktu mana pun mesin tesnya.
final _server = DateTime(2026, 11, 10, 9, 30);
final _close = DateTime(2026, 11, 10, 10, 0);

Map<String, dynamic> _session(
  String id,
  String title, {
  String state = 'open',
  String? status,
  String? source,
  Map<String, int>? counts,
}) => {
  'id': id,
  'subject_id': 's1',
  'title': title,
  'opens_at': isoWithOffset(DateTime(2026, 11, 10, 9, 0)),
  'closes_at': isoWithOffset(_close),
  'state': state,
  'seconds_until_open': null,
  // Tanpa hitung mundur, supaya tes tidak bergantung pada timer.
  'seconds_until_close': null,
  'status': status,
  'source': source,
  'counts': ?counts,
};

List<String> _said(WidgetTester tester) => [
  for (final a in tester.takeAnnouncements()) a.message,
];

void main() {
  group('siswa', () {
    const list = 'GET /student/subjects/s1/attendance';
    const present = 'POST /student/attendance/sessions/p3/present';

    FakeServer server({Object Function()? onPresent}) {
      var marked = false;
      return FakeServer({
        list: (_) => {
          'server_time': isoWithOffset(_server),
          'counts': {'hadir': marked ? 6 : 5, 'izin': 1, 'sakit': 0, 'alpa': 2},
          'sessions': [
            _session(
              'p3',
              'Pertemuan 3',
              status: marked ? 'hadir' : null,
              source: marked ? 'siswa' : null,
            ),
            _session(
              'p2',
              'Pertemuan 2',
              state: 'closed',
              status: 'izin',
              source: 'guru',
            ),
          ],
        },
        present: (_) {
          final result = onPresent?.call();
          if (result != null) return result;
          marked = true;
          return {
            'session': _session(
              'p3',
              'Pertemuan 3',
              status: 'hadir',
              source: 'siswa',
            ),
          };
        },
      });
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        testApp(StudentAttendanceScreen(subject: _subject)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tombol Hadir menyebut judul dan jam tutup', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      server().install();
      await open(tester);

      const label = 'Hadir untuk Pertemuan 3, ditutup pukul 10.00';
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        matchesSemantics(
          label: label,
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      expect(
        find.bySemanticsLabel('Rekap kamu: hadir 5, izin 1, sakit 0, alpa 2'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Pertemuan 2: Izin, dicatat guru\. Ditutup '),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Pertemuan 3: Belum presensi. Terbuka, ditutup pukul 10.00',
        ),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('setelah Hadir, hasilnya di liveRegion dan tombol hilang', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final fake = server()..install();
      await open(tester);

      await tester.tap(find.textContaining('Hadir untuk Pertemuan 3'));
      await tester.pumpAndSettle();

      expect(fake.requests.where((r) => r.url.path.endsWith('/present')), [
        isA<Object>(),
      ]);
      expectLive(tester, 'Presensi tercatat: hadir di Pertemuan 3.');
      expect(find.textContaining('Hadir untuk'), findsNothing);
      expect(
        find.text('Tidak ada sesi presensi yang menunggu kamu.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Rekap kamu: hadir 6, izin 1, sakit 0, alpa 2'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('penolakan server dibacakan lewat liveRegion', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      server(
        onPresent: () =>
            jsonResponse({'detail': 'Sesi presensi sudah ditutup'}, 409),
      ).install();
      await open(tester);

      await tester.tap(find.textContaining('Hadir untuk Pertemuan 3'));
      await tester.pumpAndSettle();

      expectLive(
        tester,
        'Presensi belum tercatat. Sesi presensi sudah ditutup.',
      );
      handle.dispose();
    });
  });

  group('guru', () {
    const sessions = 'GET /teacher/subjects/s1/attendance/sessions';
    const summary = 'GET /teacher/subjects/s1/attendance/summary';
    const create = 'POST /teacher/subjects/s1/attendance/sessions';
    const detail = 'GET /teacher/attendance/sessions/p3';
    const setStatus = 'PUT /teacher/attendance/sessions/p3/students/u1';
    const close = 'PATCH /teacher/attendance/sessions/p3';

    testWidgets('rekap per siswa satu label utuh tiap baris', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        sessions: (_) => {
          'server_time': isoWithOffset(_server),
          'sessions': [
            _session(
              'p3',
              'Pertemuan 3',
              counts: {
                'hadir': 1,
                'izin': 0,
                'sakit': 0,
                'alpa': 0,
                'belum': 1,
              },
            ),
          ],
        },
        summary: (_) => {
          'session_count': 8,
          'students': [
            {
              'student_id': 'u1',
              'name': 'Andi',
              'counts': {'hadir': 5, 'izin': 1, 'sakit': 0, 'alpa': 2},
            },
          ],
        },
      }).install();
      await tester.pumpWidget(
        testApp(TeacherAttendanceScreen(subject: _subject)),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Andi: hadir 5, izin 1, sakit 0, alpa 2'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Pertemuan 3. Terbuka, ditutup pukul 10.00. hadir 1, izin 0, '
          'sakit 0, alpa 0, belum presensi 1',
        ),
        findsOneWidget,
      );
      expect(find.text('Buka sesi presensi'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('pilihan cepat dikirim sebagai close_preset', (tester) async {
      tallScreen(tester);
      final fake = FakeServer({
        create: (_) => {'session': _session('p4', 'Pertemuan 4')},
      })..install();
      await tester.pumpWidget(
        testApp(
          AttendanceSessionFormScreen(
            subject: _subject,
            suggestedTitle: 'Pertemuan 4',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapAndPump(tester, find.text('30 menit'));
      await tapAndPump(tester, find.text('Buka sesi'));
      await tester.pumpAndSettle();

      expect(fake.bodyOf(create), {
        'title': 'Pertemuan 4',
        'close_preset': '30m',
      });
      expect(
        _said(tester),
        contains('Sesi Pertemuan 4 dibuka, ditutup pukul 10.00.'),
      );
    });

    testWidgets('Atur sendiri tanpa waktu tutup tidak dikirim', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final fake = FakeServer({})..install();
      await tester.pumpWidget(
        testApp(
          AttendanceSessionFormScreen(
            subject: _subject,
            suggestedTitle: 'Pertemuan 4',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Memilih "Atur sendiri" membuka pemilih tanggal; dibatalkan.
      await tester.tap(find.text('Atur sendiri').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      await tapAndPump(tester, find.text('Buka sesi'));

      expect(fake.requests, isEmpty);
      expectLive(tester, 'Pilih waktu tutup dengan tombol Atur waktu tutup.');
      handle.dispose();
    });

    group('detail sesi', () {
      FakeServer server() {
        var status = 'hadir';
        var state = 'open';
        return FakeServer({
          detail: (_) => {
            'session': _session(
              'p3',
              'Pertemuan 3',
              state: state,
              counts: {'hadir': 1, 'izin': 0, 'sakit': 0, 'alpa': 0},
            ),
            'students': [
              {
                'student_id': 'u1',
                'name': 'Andi',
                'status': status,
                'source': status == 'hadir' ? 'siswa' : 'guru',
              },
            ],
          },
          setStatus: (request) {
            status = jsonBody(request)['status'] as String;
            return {
              'student': {
                'student_id': 'u1',
                'name': 'Andi',
                'status': status,
                'source': 'guru',
              },
            };
          },
          close: (_) {
            state = 'closed';
            return {'session': _session('p3', 'Pertemuan 3', state: state)};
          },
        });
      }

      Future<void> open(WidgetTester tester) async {
        await tester.pumpWidget(
          testApp(
            AttendanceSessionScreen(
              subject: _subject,
              session: AttendanceSession.fromJson(
                _session('p3', 'Pertemuan 3'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('guru mengubah status siswa lewat pilihan', (tester) async {
        tallScreen(tester);
        final handle = tester.ensureSemantics();
        final fake = server()..install();
        await open(tester);

        await tester.tap(find.bySemanticsLabel('Andi: hadir. Ubah status'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Hadir, status sekarang'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Izin'));
        await tester.pumpAndSettle();

        expect(fake.bodyOf(setStatus), {'status': 'izin'});
        expectLive(tester, 'Status Andi diubah menjadi izin.');
        expect(
          find.bySemanticsLabel('Andi: izin, diubah guru. Ubah status'),
          findsOneWidget,
        );
        handle.dispose();
      });

      testWidgets('tutup sekarang mengirim close_now', (tester) async {
        tallScreen(tester);
        final handle = tester.ensureSemantics();
        final fake = server()..install();
        await open(tester);

        await tapAndPump(tester, find.text('Tutup sesi sekarang'));
        await tester.pumpAndSettle();

        expect(fake.bodyOf(close), {'close_now': true});
        expectLive(
          tester,
          'Sesi Pertemuan 3 ditutup. Siswa yang belum presensi tercatat '
          'alpa.',
        );
        expect(find.text('Tutup sesi sekarang'), findsNothing);
        handle.dispose();
      });
    });
  });

  test('label rekap per siswa', () {
    final row = AttendanceSummaryRow.fromJson({
      'student_id': 'u1',
      'name': 'Andi',
      'counts': {'hadir': 5, 'izin': 1, 'sakit': 0, 'alpa': 2},
    });
    expect(row.label, 'Andi: hadir 5, izin 1, sakit 0, alpa 2');
  });

  testWidgets('menu Presensi siswa menyebut sesi yang menunggu', (
    tester,
  ) async {
    FakeServer({
      'GET /student/subjects/s1/attendance': (_) => {
        'server_time': isoWithOffset(_server),
        'counts': {'hadir': 0, 'izin': 0, 'sakit': 0, 'alpa': 0},
        'sessions': [_session('p3', 'Pertemuan 3')],
      },
    }).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(Scaffold(body: StudentAttendanceMenuRow(subject: _subject))),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Presensi. 1 sesi terbuka, tekan Hadir'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
