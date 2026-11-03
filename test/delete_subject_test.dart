import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/play_game_screen.dart';
import 'package:aprevo/screens/student/section_reader_screen.dart';
import 'package:aprevo/screens/student/subject_screen.dart';
import 'package:aprevo/screens/teacher/subject_detail_screen.dart';
import 'package:aprevo/screens/teacher/teacher_home_screen.dart';
import 'package:aprevo/widgets/load_view.dart';

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

PlayGameScreen _play() => PlayGameScreen(
  quiz: QuizInfo(
    id: 'k1',
    kind: TestKind.pre,
    title: 'Pre-test',
    status: QuizStatus.open,
  ),
  materialTitle: 'Peta',
  studentName: 'Andi',
);

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

      await tester.tap(find.text('Kembali ke beranda'));
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

  testWidgets('gagal lalu guru menutup dialog: kembali ke daftar kelas, dan '
      'diberi tahu belum selesai', (tester) async {
    tallScreen(tester);
    _server(
      onDelete: () => jsonResponse({
        'detail': 'Kelas belum terhapus sepenuhnya. Coba lagi',
      }, 500),
    ).install();
    await _open(tester);
    await _openDialog(tester);
    await tester.tap(find.text('Ya, hapus kelas'));
    await tester.pumpAndSettle();
    _said(tester);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar kelas'), findsOneWidget);
    expect(_said(tester), [
      'Penghapusan kelas 7 Geografi belum selesai. Lanjutkan dari daftar kelas.',
    ]);
  });

  group('penghapusan yang berhenti di tengah di daftar kelas', () {
    FakeServer server({
      required List<Map<String, dynamic>> unfinished,
      bool fail = false,
    }) {
      return FakeServer({
        'GET /teacher/subjects': (_) => {
          'subjects': [],
          'unfinished_deletions': unfinished,
        },
        _deleteKey: (_) {
          if (fail) {
            return jsonResponse({
              'detail': 'Kelas belum terhapus sepenuhnya. Coba lagi',
            }, 500);
          }
          unfinished.clear();
          return {'message': 'Kelas dihapus'};
        },
      });
    }

    testWidgets('bisa dilanjutkan tanpa dialog, lalu kartunya hilang', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final fake = server(
        unfinished: [
          {'id': 's1', 'name': '7 Geografi'},
        ],
      )..install();
      await tester.pumpWidget(testApp(const TeacherHomeScreen()));
      await tester.pumpAndSettle();
      _said(tester);

      expect(
        find.bySemanticsLabel('Penghapusan kelas 7 Geografi belum selesai'),
        findsOneWidget,
      );
      await tester.tap(find.text('Lanjutkan hapus kelas 7 Geografi'));
      await tester.pumpAndSettle();
      expect(fake.requests.where((r) => r.method == 'DELETE').length, 1);
      expect(_said(tester), contains('Kelas 7 Geografi dihapus'));
      expect(find.textContaining('belum selesai'), findsNothing);
      handle.dispose();
    });

    testWidgets('gagal lagi: alasan lewat liveRegion dan bisa dicoba lagi', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      server(
        unfinished: [
          {'id': 's1', 'name': '7 Geografi'},
        ],
        fail: true,
      ).install();
      await tester.pumpWidget(testApp(const TeacherHomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan hapus kelas 7 Geografi'));
      await tester.pumpAndSettle();
      expectLive(tester, 'Kelas belum terhapus sepenuhnya. Coba lagi.');
      expect(find.text('Lanjutkan hapus kelas 7 Geografi'), findsOneWidget);
      handle.dispose();
    });
  });

  group('layar yang sedang terbuka saat kelas dihapus', () {
    const gone = 'Kelas ini sudah dihapus guru.';
    final session = {
      'quiz': {'title': 'Pre-test'},
      'questions': [
        {'id': 'q1', 'type': 'true_false', 'question': 'Bumi bulat?'},
      ],
    };

    /// `deleted`: mulai sekarang kelas s1 menjawab 410, dan materi serta kuisnya
    /// tidak ditemukan.
    FakeServer server(bool Function() deleted) {
      Object guard(Object body) => deleted()
          ? jsonResponse({'detail': 'Materi tidak ditemukan'}, 404)
          : body;
      return FakeServer({
        'GET /student/subjects/s1/materials': (_) => deleted()
            ? jsonResponse({'detail': 'Kelas ini sudah dihapus guru'}, 410)
            : {
                'materials': [
                  {'id': 'm1', 'title': 'Peta', 'quizzes': []},
                ],
              },
        'GET /materials/m1/sections': (_) => guard({
          'sections': [
            {'id': 'a', 'position': 1, 'title': 'Satu', 'content': 'Isi satu.'},
            {'id': 'b', 'position': 2, 'title': 'Dua', 'content': 'Isi dua.'},
          ],
        }),
        'GET /student/quizzes/k1': (_) => guard(session),
        'POST /quizzes/k1/attempts': (_) => guard({
          'attempt': {'id': 'a1'},
        }),
        'PUT /student/attempts/a1/answers/q1': (_) =>
            guard({'is_correct': true}),
      });
    }

    /// Siswa membuka materi lewat jalur biasa, di atas layar beranda.
    Future<void> openOver(WidgetTester tester, Widget screen) async {
      await store.studentMaterial('s1', 'm1');
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => screen),
              ),
              child: const Text('Beranda'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Beranda'));
      await tester.pumpAndSettle();
    }

    final pages = [
      MaterialSection(
        id: 'a',
        position: 1,
        title: 'Satu',
        content: 'Isi satu.',
      ),
      MaterialSection(id: 'b', position: 2, title: 'Dua', content: 'Isi dua.'),
    ];

    testWidgets('layar baca: terdeteksi saat pindah halaman, lalu ke beranda', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      var deleted = false;
      server(() => deleted).install();
      await openOver(
        tester,
        SectionReaderScreen(materialTitle: 'Peta', sections: pages),
      );
      expect(find.text('Isi satu.'), findsOneWidget);

      deleted = true;
      await tester.tap(find.text('Halaman berikutnya'));
      await tester.pumpAndSettle();

      expectLive(tester, gone);
      expect(find.text('Isi dua.'), findsNothing);
      expect(find.text('Coba lagi'), findsNothing);
      await tester.tap(find.text('Kembali ke beranda'));
      await tester.pumpAndSettle();
      expect(find.text('Beranda'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('layar baca: terdeteksi tanpa menekan apa pun', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      var deleted = false;
      server(() => deleted).install();
      await openOver(
        tester,
        SectionReaderScreen(materialTitle: 'Peta', sections: pages),
      );
      deleted = true;
      await tester.pump(kSubjectCheckInterval);
      await tester.pumpAndSettle();
      expectLive(tester, gone);
      handle.dispose();
    });

    testWidgets('daftar halaman: bukan error materi tidak ditemukan', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      var deleted = false;
      server(() => deleted).install();
      await store.studentMaterial('s1', 'm1');
      deleted = true;
      await tester.pumpWidget(
        testApp(
          const MaterialSectionsScreen(materialId: 'm1', materialTitle: 'Peta'),
        ),
      );
      await tester.pumpAndSettle();
      expectLive(tester, gone);
      expect(find.textContaining('tidak ditemukan'), findsNothing);
      expect(find.text('Coba lagi'), findsNothing);
      handle.dispose();
    });

    testWidgets('kuis: mulai mengerjakan setelah kelas dihapus', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      var deleted = false;
      server(() => deleted).install();
      await store.studentMaterial('s1', 'm1');
      deleted = true;
      await tester.pumpWidget(testApp(_play()));
      await tester.pumpAndSettle();
      expectLive(tester, gone);
      expect(find.textContaining('tidak ditemukan'), findsNothing);
      handle.dispose();
    });

    testWidgets('kuis: mengirim jawaban setelah kelas dihapus', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      var deleted = false;
      server(() => deleted).install();
      await openOver(tester, _play());
      expect(find.text('Soal 1 dari 1'), findsOneWidget);

      deleted = true;
      await tester.tap(find.bySemanticsLabel(RegExp('Benar')).first);
      await tester.pump();
      await tester.tap(find.text('Periksa Jawaban'));
      await tester.pumpAndSettle();

      expectLive(tester, gone);
      expect(find.textContaining('Jawaban belum terkirim'), findsNothing);
      await tester.tap(find.text('Kembali ke beranda'));
      await tester.pumpAndSettle();
      expect(find.text('Beranda'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('materi hilang tetapi kelas masih ada: tetap pesan aslinya', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /student/subjects/s1/materials': (_) => {
          'materials': [
            {'id': 'm1', 'title': 'Peta', 'quizzes': []},
          ],
        },
        'GET /materials/m1/sections': (_) =>
            jsonResponse({'detail': 'Materi tidak ditemukan'}, 404),
      }).install();
      await store.studentMaterial('s1', 'm1');
      await tester.pumpWidget(
        testApp(
          const MaterialSectionsScreen(materialId: 'm1', materialTitle: 'Peta'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Materi tidak ditemukan.'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('layar baca guru tidak memeriksa kelas apa pun', (
      tester,
    ) async {
      tallScreen(tester);
      final fake = FakeServer({})..install();
      await tester.pumpWidget(
        testApp(SectionReaderScreen(materialTitle: 'Peta', sections: pages)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Halaman berikutnya'));
      await tester.pump(kSubjectCheckInterval);
      await tester.pumpAndSettle();
      expect(fake.requests, isEmpty);
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
