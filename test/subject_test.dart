import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/join_screen.dart';
import 'package:aprevo/screens/teacher/teacher_home_screen.dart';
import 'package:aprevo/widgets/common.dart';

import 'fake_server.dart';

String _format(String typed) => AccessCodeFormatter()
    .formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      ),
    )
    .text;

Map<String, dynamic> _joined(bool already) => {
  'message': 'ok',
  'already_joined': already,
  'subject': {'id': 'bumi', 'name': 'Bumi dan Antariksa'},
};

/// Server siswa: belum ikut mata pelajaran apa pun, kode BMRANT ada.
FakeServer _studentServer() => FakeServer({
  'GET /student/subjects': (_) => {'subjects': []},
  'POST /student/subjects/join': (r) {
    final code = (jsonBody(r)['code'] as String);
    if (code != 'BMRANT') {
      return jsonResponse({'detail': 'Kode akses tidak ditemukan'}, 404);
    }
    return _joined(false);
  },
  'GET /student/subjects/bumi/materials': (_) => {
    'subject': {'id': 'bumi', 'name': 'Bumi dan Antariksa'},
    'materials': [
      {'id': 'm1', 'title': 'Tata Surya', 'section_count': 3, 'quizzes': []},
    ],
  },
});

void main() {
  group('AccessCodeFormatter', () {
    test('huruf kecil jadi kapital, selain huruf dibuang', () {
      expect(_format('kx-prta'), 'KXPRTA');
      expect(_format('k x 9 p'), 'KXP');
    });

    test('paling banyak 6 huruf', () {
      expect(_format('kxprtabc'), 'KXPRTA');
    });
  });

  group('AppStore gabung mata pelajaran', () {
    test('kode dirapikan sebelum dikirim', () async {
      final server = _studentServer()..install();
      final result = await store.joinSubject(' bm-rant ');
      expect(server.bodyOf('POST /student/subjects/join'), {'code': 'BMRANT'});
      expect(result.status, JoinStatus.joined);
      expect(result.subject?.name, 'Bumi dan Antariksa');
    });

    test('gabung ulang dikenali, kode salah menjadi notFound', () async {
      FakeServer({
        'POST /student/subjects/join': (r) => jsonBody(r)['code'] == 'KXPRTA'
            ? _joined(true)
            : jsonResponse({'detail': 'Kode akses tidak ditemukan'}, 404),
      }).install();
      expect(
        (await store.joinSubject('KXPRTA')).status,
        JoinStatus.alreadyJoined,
      );
      final wrong = await store.joinSubject('ZZZZZZ');
      expect(wrong.status, JoinStatus.notFound);
      expect(wrong.subject, isNull);
    });
  });

  group('Beranda siswa', () {
    testWidgets('kode diketik huruf kecil tampil kapital dan dieja', (
      tester,
    ) async {
      _studentServer().install();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(const StudentHomeScreen(studentName: 'Tes Kapital')),
      );
      await tester.enterText(find.byType(TextField), 'kxp');
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'KXP');
      expect(
        find.bySemanticsLabel('Kode yang diketik: K X P. 3 dari 6 huruf.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('kode kurang dari 6 huruf: error liveRegion, dieja', (
      tester,
    ) async {
      _studentServer().install();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(const StudentHomeScreen(studentName: 'Tes Pendek')),
      );
      await tester.enterText(find.byType(TextField), 'kxpr');
      await tester.tap(find.text('Gabung'));
      await tester.pump();
      expectLive(tester, 'Kode harus 6 huruf. Baru 4 huruf: K X P R.');
      handle.dispose();
    });

    testWidgets('kode tidak ada: error liveRegion dengan kode dieja', (
      tester,
    ) async {
      _studentServer().install();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(const StudentHomeScreen(studentName: 'Tes Salah')),
      );
      await tester.enterText(find.byType(TextField), 'zzzzzz');
      await tester.tap(find.text('Gabung'));
      await tester.pumpAndSettle();
      expectLive(
        tester,
        'Kode Z Z Z Z Z Z tidak ditemukan. Periksa lagi kode dari guru.',
      );
      handle.dispose();
    });

    testWidgets('kode benar membuka mata pelajaran dan materinya', (
      tester,
    ) async {
      _studentServer().install();
      await tester.pumpWidget(
        testApp(const StudentHomeScreen(studentName: 'Tes Gabung')),
      );
      await tester.enterText(find.byType(TextField), 'bmrant');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Tata Surya'), findsOneWidget);
      expect(find.text('3 sub bab, belum dimulai'), findsOneWidget);
    });

    testWidgets('server mati: error dibacakan dan bisa dicoba lagi', (
      tester,
    ) async {
      installUnreachableServer();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(const StudentHomeScreen(studentName: 'Tes Mati')),
      );
      expect(find.bySemanticsLabel('Memuat mata pelajaranmu.'), findsOneWidget);
      await tester.pumpAndSettle();
      expectLive(
        tester,
        'Tidak bisa terhubung ke server di $fakeBaseUrl. Pastikan backend '
        'menyala, lalu HP dan laptop memakai Wi-Fi yang sama.',
      );

      // Server menyala lagi: "Coba lagi" memuat ulang.
      _studentServer().install();
      await tapAndPump(tester, find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Mata pelajaran yang kamu ikuti (0)'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('guru: nama mata pelajaran kosong ditolak dengan liveRegion', (
    tester,
  ) async {
    FakeServer({
      'GET /teacher/subjects': (_) => {'subjects': []},
    }).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const TeacherHomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat Mata Pelajaran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat'));
    await tester.pump();
    expectLive(tester, 'Nama mata pelajaran belum diisi.');
    handle.dispose();
  });

  testWidgets('guru: mata pelajaran baru dibuat di server, kode dieja', (
    tester,
  ) async {
    final server = FakeServer({
      'GET /teacher/subjects': (_) => {'subjects': []},
      'POST /teacher/subjects': (_) => {
        'message': 'ok',
        'subject': {'id': 's1', 'name': 'IPA Kelas 5', 'access_code': 'KXPRTA'},
      },
      'GET /teacher/subjects/s1/materials': (_) => {'materials': []},
    })..install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const TeacherHomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat Mata Pelajaran'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  IPA Kelas 5 ');
    await tester.tap(find.text('Buat'));
    await tester.pumpAndSettle();
    expect(server.bodyOf('POST /teacher/subjects'), {'name': 'IPA Kelas 5'});
    expect(find.bySemanticsLabel('Kode akses: K X P R T A'), findsOneWidget);
    handle.dispose();
  });
}
