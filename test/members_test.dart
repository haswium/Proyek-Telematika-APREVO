import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/classmates_screen.dart';
import 'package:aprevo/screens/teacher/subject_members_screen.dart';

import 'fake_server.dart';

final _subject = Subject(id: 's1', name: '7 Geografi');
const _members = 'GET /teacher/subjects/s1/members';
const _remove = 'DELETE /teacher/subjects/s1/members/u1';

Map<String, dynamic> _student(String id, String name, {String? email}) => {
  'id': id,
  'name': name,
  'email': email,
  'joined_at': '2026-11-03T05:00:00+00:00',
};

List<String> _said(WidgetTester tester) => [
  for (final a in tester.takeAnnouncements()) a.message,
];

void main() {
  group('guru', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(testApp(SubjectMembersScreen(subject: _subject)));
      await tester.pumpAndSettle();
    }

    FakeServer server({Object Function()? onRemove}) {
      var students = [
        _student('u1', 'Andi', email: 'andi@contoh.test'),
        _student('u2', 'Budi'),
      ];
      return FakeServer({
        _members: (_) => {
          'student_count': students.length,
          'students': students,
        },
        _remove: (_) {
          final result = onRemove?.call();
          if (result != null) return result;
          students = [students.last];
          return {'student_count': 1};
        },
      });
    }

    testWidgets('tiap baris satu label utuh, jumlah diumumkan sekali', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      server().install();
      await open(tester);

      expect(_said(tester).where((m) => m.contains('siswa')), [
        'Anggota kelas 7 Geografi: 2 siswa',
      ]);
      expect(
        find.bySemanticsLabel(
          'Andi, andi@contoh.test, bergabung 3 November 2026',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Budi, email tidak tersedia, bergabung 3 November 2026',
        ),
        findsOneWidget,
      );
      expect(find.text('2 siswa'), findsOneWidget);

      // Muat ulang tidak mengumumkan lagi.
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(_said(tester), isEmpty);
      handle.dispose();
    });

    testWidgets('batal di dialog tidak mengirim apa pun', (tester) async {
      tallScreen(tester);
      final fake = server()..install();
      await open(tester);

      await tester.tap(find.text('Keluarkan Andi'));
      await tester.pumpAndSettle();
      expect(find.text('Keluarkan Andi dari kelas?'), findsOneWidget);
      expect(find.textContaining('bergabung lagi'), findsOneWidget);
      expect(find.textContaining('tetap tersimpan'), findsOneWidget);

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(fake.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(find.text('Andi'), findsOneWidget);
    });

    testWidgets(
      'sesudah dikeluarkan ada pesan liveRegion dan barisnya hilang',
      (tester) async {
        tallScreen(tester);
        final handle = tester.ensureSemantics();
        final fake = server()..install();
        await open(tester);

        await tester.tap(find.text('Keluarkan Andi'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ya, keluarkan'));
        await tester.pumpAndSettle();

        expect(fake.requests.where((r) => r.method == 'DELETE').length, 1);
        expectLive(tester, 'Andi dikeluarkan dari kelas. Sisa 1 siswa.');
        expect(find.text('Keluarkan Andi'), findsNothing);
        expect(find.text('1 siswa'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('gagal mengeluarkan: alasan lewat liveRegion, baris tetap', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      server(
        onRemove: () =>
            jsonResponse({'detail': 'Siswa bukan anggota kelas ini'}, 404),
      ).install();
      await open(tester);
      await tester.tap(find.text('Keluarkan Andi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya, keluarkan'));
      await tester.pumpAndSettle();
      expectLive(tester, 'Siswa bukan anggota kelas ini.');
      expect(find.text('Keluarkan Andi'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('kelas kosong', (tester) async {
      tallScreen(tester);
      FakeServer({
        _members: (_) => {'student_count': 0, 'students': []},
      }).install();
      await open(tester);
      expect(find.text('Belum ada siswa di kelas ini.'), findsOneWidget);
      expect(_said(tester), contains('Anggota kelas 7 Geografi: 0 siswa'));
    });
  });

  group('siswa', () {
    testWidgets('nama guru dan teman, tanpa email', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /student/subjects/s1/members': (_) => {
          'teacher_name': 'Bu Rina',
          'student_count': 2,
          'classmates': [
            {'name': 'Andi', 'is_me': true},
            {'name': 'Budi', 'is_me': false},
          ],
        },
      }).install();
      await tester.pumpWidget(testApp(ClassmatesScreen(subject: _subject)));
      await tester.pumpAndSettle();

      expect(_said(tester).where((m) => m.contains('siswa')), [
        'Anggota kelas 7 Geografi: 2 siswa',
      ]);
      expect(find.bySemanticsLabel('Guru: Bu Rina'), findsOneWidget);
      expect(find.bySemanticsLabel('Andi, ini kamu'), findsOneWidget);
      expect(find.bySemanticsLabel('Budi'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('Keluarkan'), findsNothing);
      handle.dispose();
    });

    testWidgets('bukan anggota: pesan dibacakan', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /student/subjects/s1/members': (_) =>
            jsonResponse({'detail': 'Kamu belum bergabung di kelas ini'}, 403),
      }).install();
      await tester.pumpWidget(testApp(ClassmatesScreen(subject: _subject)));
      await tester.pumpAndSettle();
      expect(find.text('Kamu belum bergabung di kelas ini.'), findsOneWidget);
      handle.dispose();
    });
  });

  test('label anggota tanpa tanggal bergabung', () {
    expect(
      SubjectMember(id: 'u', name: 'Andi', email: 'a@b.c').label,
      'Andi, a@b.c',
    );
  });
}
