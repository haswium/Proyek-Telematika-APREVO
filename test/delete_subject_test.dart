import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/subject_screen.dart';
import 'package:aprevo/screens/teacher/subject_detail_screen.dart';

import 'fake_server.dart';

final _subject = Subject(id: 's1', name: '7 Geografi', accessCode: 'KXPRTA');
const _warning =
    'Kelas 7 Geografi akan dihapus permanen beserta 4 materi, 6 kuis, nilai, '
    'dan 25 anggota. Tindakan ini tidak bisa dibatalkan.';
const _deleteKey = 'DELETE /teacher/subjects/s1';

List<String> _said(WidgetTester tester) => [
  for (final a in tester.takeAnnouncements()) a.message,
];

FakeServer _server({
  Object Function()? onDelete,
  Object Function()? onSummary,
}) => FakeServer({
  'GET /teacher/subjects/s1/materials': (_) => {
    'materials': [
      {'id': 'm1', 'title': 'Peta', 'is_published': true, 'quizzes': []},
    ],
  },
  'GET /teacher/subjects/s1/delete-summary': (_) =>
      onSummary?.call() ??
      {'material_count': 4, 'quiz_count': 6, 'student_count': 25},
  _deleteKey: (_) => onDelete?.call() ?? {'message': 'Kelas dihapus'},
});

/// Layar kelas di atas satu layar lain, seperti daftar kelas di aplikasi.
Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    testApp(
      Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              const Text('Daftar kelas'),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubjectDetailScreen(subject: _subject),
                  ),
                ),
                child: const Text('Buka'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka'));
  await tester.pumpAndSettle();
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Hapus kelas'));
  await tester.tap(find.text('Hapus kelas'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tombol Hapus kelas paling bawah, terpisah dari menu lain', (
    tester,
  ) async {
    tallScreen(tester);
    _server().install();
    await _open(tester);
    final button = tester.getTopLeft(find.text('Hapus kelas')).dy;
    final previous = tester.getBottomLeft(
      find.textContaining('Ketuk "Kelola materi"'),
    );
    expect(button - previous.dy, greaterThan(48));
    for (final other in [
      'Unggah Materi PDF',
      'Anggota kelas',
      'Kelola materi',
    ]) {
      expect(tester.getTopLeft(find.text(other)).dy, lessThan(button));
    }
  });

  testWidgets(
    'dialog menyebut jumlah isi, diumumkan, dan fokus awal di Batal',
    (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final server = _server()..install();
      await _open(tester);
      _said(tester);
      await _openDialog(tester);

      expect(find.text(_warning), findsOneWidget);
      expect(_said(tester), contains(_warning));

      final cancel = find.widgetWithText(TextButton, 'Batal');
      expect(tester.widget<TextButton>(cancel).autofocus, isTrue);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Ya, hapus kelas'),
            )
            .autofocus,
        isFalse,
      );
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.descendant(
          of: cancel,
          matching: find.byWidgetPredicate((w) => identical(w, focused.widget)),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(cancel).flagsCollection.isFocused,
        Tristate.isTrue,
      );

      // Batal lebih dulu dalam urutan tombol.
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(find.text('Hapus kelas'), findsOneWidget);
      expect(find.text('Daftar kelas'), findsNothing);
      handle.dispose();
    },
  );

  testWidgets('dialog tidak tertutup kalau mengetuk di luarnya', (
    tester,
  ) async {
    tallScreen(tester);
    _server().install();
    await _open(tester);
    await _openDialog(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('sesudah dihapus kembali ke daftar kelas dengan pengumuman', (
    tester,
  ) async {
    tallScreen(tester);
    final server = _server()..install();
    await _open(tester);
    await _openDialog(tester);
    _said(tester);

    await tester.tap(find.text('Ya, hapus kelas'));
    await tester.pumpAndSettle();

    expect(server.requests.where((r) => r.method == 'DELETE').length, 1);
    expect(find.text('Daftar kelas'), findsOneWidget);
    expect(find.byType(SubjectDetailScreen), findsNothing);
    expect(_said(tester), contains('Kelas 7 Geografi dihapus'));
  });

  testWidgets('gagal menghapus: pesan di dialog, kelas tetap, bisa diulang', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    var fail = true;
    _server(
      onDelete: () => fail
          ? jsonResponse({
              'detail': 'Kelas belum terhapus sepenuhnya. Coba lagi',
            }, 500)
          : {'message': 'Kelas dihapus'},
    ).install();
    await _open(tester);
    await _openDialog(tester);
    await tester.tap(find.text('Ya, hapus kelas'));
    await tester.pumpAndSettle();
    expectLive(tester, 'Kelas belum terhapus sepenuhnya. Coba lagi.');
    expect(find.text('Daftar kelas'), findsNothing);

    fail = false;
    await tester.tap(find.text('Ya, hapus kelas'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar kelas'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('ringkasan gagal dimuat: tidak bisa menghapus, Batal tetap ada', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    final server = _server(
      onSummary: () => jsonResponse({'detail': 'Kelas tidak ditemukan'}, 404),
    )..install();
    await _open(tester);
    await _openDialog(tester);
    expectLive(tester, 'Kelas tidak ditemukan.');
    await tester.tap(find.text('Ya, hapus kelas'));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Kelas tidak ditemukan.'), findsNothing);
    handle.dispose();
  });

  group('siswa', () {
    const key = 'GET /student/subjects/s1/materials';
    const message = 'Kelas ini sudah dihapus guru';

    Future<void> openStudent(WidgetTester tester) async {
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentSubjectScreen(
                    subject: _subject,
                    studentName: 'Andi',
                  ),
                ),
              ),
              child: const Text('Daftar kelas'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Daftar kelas'));
      await tester.pumpAndSettle();
    }

    testWidgets('kelas yang sudah dihapus: pesan jelas, bukan error', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        key: (_) => jsonResponse({'detail': message}, 410),
      }).install();
      await openStudent(tester);

      expectLive(tester, '$message.');
      expect(find.text('Coba lagi'), findsNothing);

      await tester.tap(find.text('Kembali ke daftar kelas'));
      await tester.pumpAndSettle();
      expect(find.text('Daftar kelas'), findsOneWidget);
      expect(find.byType(StudentSubjectScreen), findsNothing);
      handle.dispose();
    });

    testWidgets('kelas dihapus saat layarnya terbuka: isi lama diganti pesan', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      var deleted = false;
      FakeServer({
        key: (_) => deleted
            ? jsonResponse({'detail': message}, 410)
            : {
                'materials': [
                  {'id': 'm1', 'title': 'Peta', 'quizzes': []},
                ],
              },
      }).install();
      await openStudent(tester);
      expect(find.text('Peta'), findsOneWidget);

      deleted = true;
      store.notifyListeners();
      await tester.pumpAndSettle();
      expectLive(tester, '$message.');
      expect(find.text('Peta'), findsNothing);
      handle.dispose();
    });
  });

  test('kalimat peringatan', () {
    expect(
      const SubjectDeleteSummary(
        materials: 4,
        quizzes: 6,
        students: 25,
      ).warning('7 Geografi'),
      _warning,
    );
  });
}
