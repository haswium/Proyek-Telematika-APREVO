import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/classmates_screen.dart';
import 'package:aprevo/screens/student/section_reader_screen.dart';
import 'package:aprevo/screens/student/subject_screen.dart';
import 'package:aprevo/screens/teacher/subject_detail_screen.dart';
import 'package:aprevo/screens/teacher/subject_members_screen.dart';
import 'package:aprevo/screens/teacher/teacher_home_screen.dart';
import 'package:aprevo/widgets/search_box.dart';

import 'fake_server.dart';

final _subject = Subject(id: 'k1', name: 'IPA', accessCode: 'KXPRTA');

Map<String, dynamic> _subjectJson(String id, String name) => {
  'id': id,
  'name': name,
  'access_code': 'KXPRTA',
  'student_count': 1,
  'material_count': 0,
  'created_at': '2026-10-01T00:00:00+00:00',
};

Map<String, dynamic> _materialJson(String id, String title) => {
  'id': id,
  'title': title,
  'is_published': true,
  'section_count': 1,
  'quizzes': const [],
};

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pump();
}

Future<void> _settleSearch(WidgetTester tester) async {
  await tester.pump(kSearchDelay);
  await tester.pumpAndSettle();
}

const _table =
    '[[tabel:{"title": "Bagian", "columns": ["Nama", "Fungsi"], '
    '"rows": [["Stomata", "Gas"], ["Klorofil", "Cahaya"]]}]]';

final _sections = [
  {'id': 's1', 'position': 1, 'title': 'Pembuka', 'content': 'Halo.'},
  {
    'id': 's2',
    'position': 2,
    'title': 'Fotosintesis',
    'content': [
      'Paragraf pertama.',
      '',
      'Daun memasak makanan.',
      '- Butir pertama',
      '- Butir kedua',
      '[[gambar:xref-1]]',
      '## Subjudul',
      _table,
    ].join('\n'),
  },
  {'id': 's3', 'position': 3, 'title': '', 'content': 'Penutup.'},
];

Map<String, dynamic> _hit(
  String section,
  int page,
  String title,
  String snippet, {
  int? line,
  int? row,
}) => {
  'section_id': section,
  'page_index': page,
  'title': title,
  'snippet': snippet,
  'line': line,
  'row': row,
};

FakeServer _contentServer(List<Map<String, dynamic>> hits) => FakeServer({
  'GET /materials/m1/sections': (_) => {
    'material': {'id': 'm1', 'title': 'Tumbuhan'},
    'sections': _sections,
    'images': [
      {
        'id': 'g1',
        'image_key': 'xref-1',
        'description': 'Daun hijau',
        'is_decorative': false,
      },
    ],
  },
  'GET /materials/m1/search': (_) => {'results': hits},
})..install();

const _sectionsScreen = MaterialSectionsScreen(
  materialId: 'm1',
  materialTitle: 'Tumbuhan',
);

/// Pengumuman selama [_watchFocusEvents] aktif. Handler itu menggantikan
/// penampung milik `takeAnnouncements`.
final _said = <String>[];

/// Id node semantik yang diminta menerima fokus TalkBack.
List<int> _watchFocusEvents(WidgetTester tester) {
  final focused = <int>[];
  _said.clear();
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map<Object?, Object?>;
      if (map['type'] == 'focus') focused.add(map['nodeId']! as int);
      if (map['type'] == 'announce') {
        final data = map['data']! as Map<Object?, Object?>;
        _said.add(data['message']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return focused;
}

List<String> _announced(WidgetTester tester) {
  final said = [
    for (final a in tester.takeAnnouncements()) a.message,
    ..._said,
  ];
  _said.clear();
  return said;
}

/// Mencari di layar daftar halaman, lalu membuka satu-satunya hasil.
Future<List<int>> _openOnlyHit(WidgetTester tester, String label) async {
  await tester.pumpWidget(testApp(_sectionsScreen));
  await tester.pumpAndSettle();
  await _type(tester, 'Cari isi materi', 'kata');
  await _settleSearch(tester);
  _announced(tester);
  final focused = _watchFocusEvents(tester);
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
  return focused;
}

void main() {
  group('filter di aplikasi', () {
    testWidgets('jeda 0,5 detik: daftar dan pengumuman berubah bersamaan', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final server = FakeServer({
        'GET /teacher/subjects': (_) => {
          'subjects': [
            _subjectJson('k1', '7A Geografi'),
            _subjectJson('k2', '7B Geografi'),
            _subjectJson('k3', 'Matematika'),
          ],
        },
      })..install();
      await tester.pumpWidget(testApp(const TeacherHomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Daftar kelas (3)'), findsOneWidget);
      expect(find.text('Hapus pencarian'), findsNothing);

      await _type(tester, 'Cari kelas', 'geo');
      await tester.pump(kSearchDelay - const Duration(milliseconds: 1));
      expect(find.text('Matematika'), findsOneWidget);
      expect(find.textContaining('ditemukan'), findsNothing);
      expect(find.text('Hapus pencarian'), findsOneWidget);

      // Ketikan baru mengulang jeda.
      await _type(tester, 'Cari kelas', 'GEOG');
      await tester.pump(kSearchDelay - const Duration(milliseconds: 1));
      expect(find.textContaining('ditemukan'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expectLive(tester, '2 kelas ditemukan');
      expect(find.text('Matematika'), findsNothing);
      expect(find.text('Daftar kelas (2 dari 3)'), findsOneWidget);
      // Disaring di aplikasi, tanpa permintaan baru.
      expect(server.requests.length, 1);
      handle.dispose();
    });

    testWidgets('tidak ada hasil, lalu tombol hapus mengembalikan semuanya', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /teacher/subjects': (_) => {
          'subjects': [_subjectJson('k1', 'IPA'), _subjectJson('k2', 'IPS')],
        },
      }).install();
      await tester.pumpWidget(testApp(const TeacherHomeScreen()));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari kelas', 'zzz');
      await _settleSearch(tester);
      expectLive(tester, 'Tidak ada kelas yang cocok');
      expect(find.text('IPA'), findsNothing);
      _announced(tester);

      await tester.tap(find.text('Hapus pencarian'));
      await tester.pumpAndSettle();
      expect(find.text('IPA'), findsOneWidget);
      expect(find.text('IPS'), findsOneWidget);
      expect(find.text('Hapus pencarian'), findsNothing);
      expect(find.textContaining('cocok'), findsNothing);
      expect(_announced(tester), contains('Pencarian dihapus'));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);
      handle.dispose();
    });

    testWidgets('jumlah sama untuk kata berbeda tetap membuat node baru', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /teacher/subjects': (_) => {
          'subjects': [_subjectJson('k1', 'IPA'), _subjectJson('k2', 'IPS')],
        },
      }).install();
      await tester.pumpWidget(testApp(const TeacherHomeScreen()));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari kelas', 'ipa');
      await _settleSearch(tester);
      final first = tester.getSemantics(
        find.bySemanticsLabel('1 kelas ditemukan'),
      );
      final firstId = first.id;

      await _type(tester, 'Cari kelas', 'ips');
      await _settleSearch(tester);
      final second = tester.getSemantics(
        find.bySemanticsLabel('1 kelas ditemukan'),
      );
      expect(second.id, isNot(firstId));
      handle.dispose();
    });

    testWidgets('kolom tidak tampil kalau daftar kosong', (tester) async {
      tallScreen(tester);
      FakeServer({
        'GET /teacher/subjects': (_) => {'subjects': const []},
      }).install();
      await tester.pumpWidget(testApp(const TeacherHomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Belum ada kelas.'), findsOneWidget);
    });

    testWidgets('isian tetap ada saat data dimuat ulang', (tester) async {
      tallScreen(tester);
      FakeServer({
        'GET /teacher/subjects': (_) => {
          'subjects': [_subjectJson('k1', 'IPA'), _subjectJson('k2', 'IPS')],
        },
      }).install();
      await tester.pumpWidget(testApp(const TeacherHomeScreen()));
      await tester.pumpAndSettle();
      await _type(tester, 'Cari kelas', 'ipa');
      await _settleSearch(tester);

      store.notifyListeners();
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ipa',
      );
      expect(find.text('1 kelas ditemukan'), findsOneWidget);
      expect(find.text('IPS'), findsNothing);
    });

    testWidgets('materi di kelas, guru', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /teacher/subjects/k1/materials': (_) => {
          'subject': _subjectJson('k1', 'IPA'),
          'materials': [
            _materialJson('m1', 'Tumbuhan'),
            _materialJson('m2', 'Hewan'),
          ],
        },
      }).install();
      await tester.pumpWidget(testApp(SubjectDetailScreen(subject: _subject)));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari materi', 'tumbuh');
      await _settleSearch(tester);
      expectLive(tester, '1 materi ditemukan');
      expect(find.text('Hewan'), findsNothing);
      expect(find.text('Tumbuhan'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('materi di kelas, siswa: tiap hasil satu label utuh', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /student/subjects/k1/materials': (_) => {
          'subject': _subjectJson('k1', 'IPA'),
          'materials': [
            _materialJson('m1', 'Tumbuhan'),
            _materialJson('m2', 'Hewan'),
          ],
        },
      }).install();
      await tester.pumpWidget(
        testApp(StudentSubjectScreen(subject: _subject, studentName: 'Budi')),
      );
      await tester.pumpAndSettle();

      await _type(tester, 'Cari materi', 'hewan');
      await _settleSearch(tester);
      expectLive(tester, '1 materi ditemukan');
      expect(find.bySemanticsLabel(RegExp(r'^Materi Hewan\.')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Materi Tumbuhan')), findsNothing);
      handle.dispose();
    });

    testWidgets('anggota kelas, guru', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /teacher/subjects/k1/members': (_) => {
          'subject': {'id': 'k1', 'name': 'IPA'},
          'student_count': 2,
          'students': [
            {'id': 'a', 'name': 'Andi', 'email': null, 'joined_at': null},
            {'id': 'b', 'name': 'Budi', 'email': null, 'joined_at': null},
          ],
        },
      }).install();
      await tester.pumpWidget(testApp(SubjectMembersScreen(subject: _subject)));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari siswa', 'bud');
      await _settleSearch(tester);
      expectLive(tester, '1 siswa ditemukan');
      expect(find.text('Keluarkan Andi'), findsNothing);
      expect(find.text('Keluarkan Budi'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('anggota kelas, siswa: guru tetap tampil', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /student/subjects/k1/members': (_) => {
          'subject': {'id': 'k1', 'name': 'IPA'},
          'teacher_name': 'Bu Rina',
          'student_count': 2,
          'classmates': [
            {'name': 'Andi', 'is_me': false},
            {'name': 'Budi', 'is_me': true},
          ],
        },
      }).install();
      await tester.pumpWidget(testApp(ClassmatesScreen(subject: _subject)));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari siswa', 'zzz');
      await _settleSearch(tester);
      expectLive(tester, 'Tidak ada siswa yang cocok');
      expect(find.bySemanticsLabel('Guru: Bu Rina'), findsOneWidget);
      expect(find.bySemanticsLabel('Andi'), findsNothing);
      handle.dispose();
    });
  });

  group('pencarian isi materi', () {
    testWidgets('lewat backend setelah jeda, dengan label utuh', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final server = _contentServer([
        _hit('s2', 1, 'Fotosintesis', '...daun memasak...', line: 2),
        _hit('s3', 2, '', 'Penutup.', line: 0),
      ]);
      await tester.pumpWidget(testApp(_sectionsScreen));
      await tester.pumpAndSettle();
      server.requests.clear();

      await _type(tester, 'Cari isi materi', 'Da');
      await _type(tester, 'Cari isi materi', 'Daun Memasak');
      await tester.pump(kSearchDelay - const Duration(milliseconds: 1));
      expect(server.requests, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(server.requests.length, 1);
      expect(server.requests.single.url.queryParameters['q'], 'daun memasak');
      expectLive(tester, '2 halaman ditemukan');
      expect(
        find.bySemanticsLabel('Halaman 2, Fotosintesis: ...daun memasak...'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Halaman 3: Penutup.'), findsOneWidget);
      // Daftar halaman biasa digantikan selama mencari.
      expect(find.bySemanticsLabel(RegExp(r'dari 3')), findsNothing);
      handle.dispose();
    });

    testWidgets('satu huruf tidak dikirim, dan hapus mengembalikan daftar', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final server = _contentServer(const []);
      await tester.pumpWidget(testApp(_sectionsScreen));
      await tester.pumpAndSettle();
      server.requests.clear();

      await _type(tester, 'Cari isi materi', 'd');
      await _settleSearch(tester);
      expect(server.requests, isEmpty);
      expectLive(tester, 'Ketik minimal 2 huruf');

      await _type(tester, 'Cari isi materi', 'zzz');
      await _settleSearch(tester);
      expectLive(tester, 'Tidak ada halaman yang cocok');

      await tester.tap(find.text('Hapus pencarian'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Halaman 1 dari 3: Pembuka'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('jawaban lama yang datang terlambat diabaikan', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /materials/m1/sections': (_) => {
          'material': {'id': 'm1', 'title': 'Tumbuhan'},
          'sections': _sections,
          'images': const [],
        },
        'GET /materials/m1/search': (request) => {
          'results': [
            _hit('s1', 0, 'Pembuka', request.url.queryParameters['q']!),
          ],
        },
      }, delay: const Duration(milliseconds: 700)).install();
      await tester.pumpWidget(testApp(_sectionsScreen));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari isi materi', 'lama');
      await tester.pump(kSearchDelay);
      expect(find.text('Mencari...'), findsOneWidget);
      // Pesan menunggu tidak dibacakan otomatis.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Mencari...'))
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );

      await _type(tester, 'Cari isi materi', 'baru');
      await tester.pump(kSearchDelay);
      await tester.pump(const Duration(milliseconds: 250));
      // Jawaban "lama" sudah datang, tetapi tidak dipakai.
      expect(find.bySemanticsLabel('Halaman 1, Pembuka: lama'), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Halaman 1, Pembuka: baru'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('gagal: pesan dibacakan, Coba lagi mengulang', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      var fail = true;
      FakeServer({
        'GET /materials/m1/sections': (_) => {
          'material': {'id': 'm1', 'title': 'Tumbuhan'},
          'sections': _sections,
          'images': const [],
        },
        'GET /materials/m1/search': (_) => fail
            ? jsonResponse({'detail': 'Server sibuk'}, 500)
            : {'results': const []},
      }).install();
      await tester.pumpWidget(testApp(_sectionsScreen));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari isi materi', 'daun');
      await _settleSearch(tester);
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.textContaining('ditemukan'), findsNothing);

      fail = false;
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Coba lagi'), findsNothing);
      expectLive(tester, 'Tidak ada halaman yang cocok');
      handle.dispose();
    });

    testWidgets('kelas terhapus: pesannya, bukan error', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      FakeServer({
        'GET /materials/m1/sections': (_) => {
          'material': {'id': 'm1', 'title': 'Tumbuhan'},
          'sections': _sections,
          'images': const [],
        },
        'GET /materials/m1/search': (_) =>
            jsonResponse({'detail': 'Kelas ini sudah dihapus guru'}, 410),
      }).install();
      await tester.pumpWidget(testApp(_sectionsScreen));
      await tester.pumpAndSettle();

      await _type(tester, 'Cari isi materi', 'daun');
      await _settleSearch(tester);
      expect(
        find.textContaining('Kelas ini sudah dihapus guru'),
        findsOneWidget,
      );
      expect(find.text('Kembali ke beranda'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
      handle.dispose();
    });
  });

  group('membuka hasil pencarian', () {
    Future<void> expectFocus(
      WidgetTester tester,
      String hitSnippet, {
      int? line,
      int? row,
      required Finder target,
    }) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      _contentServer([
        _hit('s2', 1, 'Fotosintesis', hitSnippet, line: line, row: row),
      ]);
      final focused = await _openOnlyHit(
        tester,
        'Halaman 2, Fotosintesis: $hitSnippet',
      );
      expect(focused, [tester.getSemantics(target).id]);
      final said = _announced(tester);
      expect(said, ['Halaman 2, hasil pencarian: $hitSnippet']);
      handle.dispose();
    }

    testWidgets('paragraf', (tester) async {
      await expectFocus(
        tester,
        'cuplikan paragraf',
        line: 2,
        target: find.bySemanticsLabel('Daun memasak makanan.'),
      );
    });

    testWidgets('butir daftar', (tester) async {
      await expectFocus(
        tester,
        'cuplikan butir',
        line: 4,
        target: find.bySemanticsLabel('Butir 2 dari 2: Butir kedua'),
      );
    });

    testWidgets('gambar', (tester) async {
      await expectFocus(
        tester,
        'Gambar: cuplikan',
        line: 5,
        target: find.bySemanticsLabel('Gambar: Daun hijau'),
      );
    });

    testWidgets('subjudul', (tester) async {
      await expectFocus(
        tester,
        'cuplikan subjudul',
        line: 6,
        target: find.bySemanticsLabel('Subjudul'),
      );
    });

    testWidgets('baris tabel yang memuat sel itu', (tester) async {
      await expectFocus(
        tester,
        'cuplikan sel',
        line: 7,
        row: 1,
        target: find.bySemanticsLabel(RegExp(r'^Baris 2\. Nama: Klorofil')),
      );
    });

    testWidgets('judul tabel', (tester) async {
      await expectFocus(
        tester,
        'cuplikan judul tabel',
        line: 7,
        target: find.bySemanticsLabel(RegExp(r'^Tabel: Bagian')),
      );
    });

    testWidgets('hanya judul halaman yang cocok: fokus ke judul halaman', (
      tester,
    ) async {
      await expectFocus(
        tester,
        'Fotosintesis',
        target: find.bySemanticsLabel('Halaman 2 dari 3: Fotosintesis'),
      );
    });

    testWidgets('blok sudah tidak ada: fokus ke judul halaman', (tester) async {
      await expectFocus(
        tester,
        'teks lama',
        line: 99,
        target: find.bySemanticsLabel('Halaman 2 dari 3: Fotosintesis'),
      );
    });

    testWidgets('pindah halaman kembali ke perilaku biasa', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      _contentServer([_hit('s2', 1, 'Fotosintesis', 'cuplikan', line: 2)]);
      final focused = await _openOnlyHit(
        tester,
        'Halaman 2, Fotosintesis: cuplikan',
      );
      _announced(tester);
      focused.clear();

      await tester.tap(find.text('Halaman sebelumnya'));
      await tester.pumpAndSettle();
      expect(_announced(tester), ['Halaman 1 dari 3: Pembuka']);
      expect(focused, isEmpty);

      await tester.tap(find.text('Halaman berikutnya'));
      await tester.pumpAndSettle();
      // Halaman yang sama dibuka lagi tanpa pengumuman hasil pencarian.
      expect(_announced(tester), ['Halaman 2 dari 3: Fotosintesis']);
      expect(focused, isEmpty);
      handle.dispose();
    });

    testWidgets('dibuka biasa tanpa pencarian: tidak meminta fokus', (
      tester,
    ) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      _contentServer(const []);
      await tester.pumpWidget(testApp(_sectionsScreen));
      await tester.pumpAndSettle();
      _announced(tester);
      final focused = _watchFocusEvents(tester);

      await tester.tap(find.bySemanticsLabel('Halaman 2 dari 3: Fotosintesis'));
      await tester.pumpAndSettle();
      expect(focused, isEmpty);
      expect(_announced(tester), ['Halaman 2 dari 3: Fotosintesis']);
      handle.dispose();
    });

    testWidgets('kata pencarian masih ada setelah kembali', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      _contentServer([_hit('s2', 1, 'Fotosintesis', 'cuplikan', line: 2)]);
      await _openOnlyHit(tester, 'Halaman 2, Fotosintesis: cuplikan');

      Navigator.of(tester.element(find.byType(SectionReaderScreen))).pop();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Halaman 2, Fotosintesis: cuplikan'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'kata',
      );
      handle.dispose();
    });
  });
}
