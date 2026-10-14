import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/join_screen.dart';
import 'package:aprevo/screens/teacher/teacher_home_screen.dart';
import 'package:aprevo/theme/app_theme.dart';
import 'package:aprevo/widgets/common.dart';

/// Sama seperti AprevoApp, dengan animasi dimatikan (aturan APREVO:
/// animasi berhenti kalau disableAnimations aktif) supaya pumpAndSettle
/// tidak menunggu animasi berulang.
Widget _app(Widget home) => MaterialApp(
  theme: buildAprevoTheme(),
  locale: const Locale('id', 'ID'),
  supportedLocales: const [Locale('id', 'ID')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: home,
);

String _format(String typed) => AccessCodeFormatter()
    .formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      ),
    )
    .text;

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

  group('AppStore mata pelajaran', () {
    test('gabung dengan huruf kecil dan spasi tetap diterima', () {
      final store = AppStore();
      final result = store.joinSubject(' kx prta ', 'Budi');
      expect(result.status, JoinStatus.joined);
      expect(result.subject?.name, 'IPA Kelas 5');
      expect(store.subjectsOf('Budi').map((s) => s.name), ['IPA Kelas 5']);
    });

    test('gabung dua kali dikenali, kode salah ditolak', () {
      final store = AppStore();
      expect(
        store.joinSubject('KXPRTA', 'Dimas').status,
        JoinStatus.alreadyJoined,
      );
      final wrong = store.joinSubject('ZZZZZZ', 'Dimas');
      expect(wrong.status, JoinStatus.notFound);
      expect(wrong.subject, isNull);
    });

    test('materi draf tidak terlihat siswa', () {
      final store = AppStore();
      final bumi = store.subjects.firstWhere((s) => s.accessCode == 'BMRANT');
      expect(bumi.materials.map((m) => m.title), contains('Gerhana'));
      expect(
        store.publishedMaterials(bumi).map((m) => m.title),
        isNot(contains('Gerhana')),
      );
    });

    test('kode mata pelajaran baru 6 huruf A-Z dan unik', () {
      final store = AppStore();
      for (var i = 0; i < 20; i++) {
        store.createSubject('Mapel $i');
      }
      final codes = store.subjects.map((s) => s.accessCode).toList();
      for (final code in codes) {
        expect(code, matches(RegExp(r'^[A-Z]{6}$')));
      }
      expect(codes.toSet().length, codes.length);
    });

    test('materi baru masuk ke mata pelajarannya sebagai draf', () {
      final store = AppStore();
      final subject = store.createSubject('Matematika');
      final material = store.createMaterial(subject, 'Pecahan', '');
      expect(store.subjectOf(material), same(subject));
      expect(material.published, isFalse);
      expect(store.publishedMaterials(subject), isEmpty);
    });
  });

  group('Beranda siswa', () {
    testWidgets('kode diketik huruf kecil tampil kapital dan dieja', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const StudentHomeScreen(studentName: 'Tes Kapital')),
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
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const StudentHomeScreen(studentName: 'Tes Pendek')),
      );
      await tester.enterText(find.byType(TextField), 'kxpr');
      await tester.tap(find.text('Gabung'));
      await tester.pump();
      const message = 'Kode harus 6 huruf. Baru 4 huruf: K X P R.';
      expect(
        tester.getSemantics(find.bySemanticsLabel(message)),
        matchesSemantics(label: message, isLiveRegion: true),
      );
      handle.dispose();
    });

    testWidgets('kode benar membuka mata pelajaran tanpa materi draf', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const StudentHomeScreen(studentName: 'Tes Gabung')),
      );
      await tester.enterText(find.byType(TextField), 'bmrant');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Tata Surya'), findsOneWidget);
      expect(find.text('Gerhana'), findsNothing);
    });
  });

  testWidgets('guru: nama mata pelajaran kosong ditolak dengan liveRegion', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const TeacherHomeScreen()));
    await tester.tap(find.text('Buat Mata Pelajaran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat'));
    await tester.pump();
    const message = 'Nama mata pelajaran belum diisi.';
    expect(
      tester.getSemantics(find.bySemanticsLabel(message)),
      matchesSemantics(label: message, isLiveRegion: true),
    );
    handle.dispose();
  });
}
