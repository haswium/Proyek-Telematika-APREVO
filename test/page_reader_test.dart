import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/screens/student/section_reader_screen.dart';
import 'package:aprevo/widgets/common.dart';

import 'fake_server.dart';

void _serve() {
  FakeServer({
    'GET /materials/m1/sections': (_) => {
      'material': {'id': 'm1', 'title': 'ScratchJr'},
      'sections': [
        {
          'id': 's1',
          'position': 1,
          'title': 'Ayo Menabung',
          'content':
              'Budi mengeluarkan amplop coklat.\n'
              '## Mengenal Uang\n'
              'Uang dipakai untuk membeli barang.',
          'page_start': 1,
          'page_end': 1,
        },
        {
          'id': 's2',
          'position': 2,
          'title': '',
          'content':
              'Isi halaman dua.\n'
              '[[gambar:xref-7]]\n'
              '[[gambar:xref-8]]\n'
              'Pada hari ini kamu akan belajar:\n'
              '- Mengenal ScratchJr\n'
              '- Membuat karakter bergerak\n'
              'Budi pulang.\n'
              '[[gambar:xref-9]]',
          'page_start': 2,
          'page_end': 2,
        },
        {
          'id': 's3',
          'position': 3,
          'title': 'Penutup',
          // Hanya gambar dekoratif: halaman dianggap tanpa teks.
          'content': '[[gambar:xref-8]]',
          'page_start': 3,
          'page_end': 3,
        },
      ],
      'images': [
        {
          'id': 'i7',
          'image_key': 'xref-7',
          'description': 'Budi memegang celengan.',
          'is_decorative': false,
        },
        {
          'id': 'i8',
          'image_key': 'xref-8',
          'description': 'Bunga hiasan.',
          'is_decorative': true,
        },
        {
          'id': 'i9',
          'image_key': 'xref-9',
          'description': null,
          'is_decorative': false,
        },
      ],
    },
  }).install();
}

/// Daftar materi (rute bernama) > daftar halaman, seperti alur siswa.
Future<void> _openPages(WidgetTester tester) async {
  await tester.pumpWidget(testApp(const Text('Beranda')));
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute(
      settings: kMaterialListRoute,
      builder: (_) => const Text('Daftar materi'),
    ),
  );
  await tester.pumpAndSettle();
  navigator.push(
    MaterialPageRoute(
      builder: (_) => const MaterialSectionsScreen(
        materialId: 'm1',
        materialTitle: 'ScratchJr',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('daftar halaman dibaca dengan posisi dan judulnya', (
    tester,
  ) async {
    tallScreen(tester);
    _serve();
    final handle = tester.ensureSemantics();
    await _openPages(tester);
    expect(
      find.bySemanticsLabel('Halaman 1 dari 3: Ayo Menabung'),
      findsOneWidget,
    );
    // Halaman tanpa judul cukup disebut posisinya.
    expect(find.bySemanticsLabel('Halaman 2 dari 3'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('halaman: header, paragraf terpisah, lalu tombol di bawah', (
    tester,
  ) async {
    tallScreen(tester);
    _serve();
    final handle = tester.ensureSemantics();
    await _openPages(tester);
    tester.takeAnnouncements();

    await tapAndPump(tester, find.text('Halaman 1: Ayo Menabung'));
    await tester.pumpAndSettle();
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Halaman 1 dari 3: Ayo Menabung'),
    );

    final header = find.text('Halaman 1 dari 3: Ayo Menabung');
    expect(
      tester.getSemantics(header),
      isSemantics(
        label: 'Halaman 1 dari 3: Ayo Menabung',
        isHeader: true,
        isFocusable: true,
      ),
    );
    // Tiap paragraf dan subjudul satu fokus sendiri.
    expect(
      find.bySemanticsLabel('Budi mengeluarkan amplop coklat.'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('Mengenal Uang')),
      isSemantics(label: 'Mengenal Uang', isHeader: true),
    );
    expect(
      find.bySemanticsLabel('Uang dipakai untuk membeli barang.'),
      findsOneWidget,
    );

    // Halaman pertama: tidak ada tombol sebelumnya. Tombol di bawah isi.
    expect(find.text('Halaman sebelumnya'), findsNothing);
    final next = find.text('Halaman berikutnya');
    expect(
      tester.getTopLeft(next).dy,
      greaterThan(
        tester.getTopLeft(find.text('Uang dipakai untuk membeli barang.')).dy,
      ),
    );
    handle.dispose();
  });

  testWidgets('pindah halaman: fokus ke header dan diumumkan', (tester) async {
    tallScreen(tester);
    _serve();
    final handle = tester.ensureSemantics();
    await _openPages(tester);
    await tapAndPump(tester, find.text('Halaman 1: Ayo Menabung'));
    await tester.pumpAndSettle();
    tester.takeAnnouncements();

    await tapAndPump(tester, find.text('Halaman berikutnya'));
    await tester.pump();
    expect(find.text('Halaman 2 dari 3'), findsOneWidget);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Halaman 2 dari 3'),
    );
    expect(
      tester.getSemantics(find.text('Halaman 2 dari 3')),
      isSemantics(
        label: 'Halaman 2 dari 3',
        isHeader: true,
        isFocusable: true,
        isFocused: true,
      ),
    );
    // Gambar dibacakan di posisinya, di antara paragraf. Gambar dekoratif
    // tidak muncul sama sekali.
    final image = find.bySemanticsLabel('Gambar: Budi memegang celengan.');
    expect(image, findsOneWidget);
    expect(find.textContaining('Bunga hiasan'), findsNothing);
    // Gambar tanpa deskripsi tidak pernah sampai ke siswa.
    expect(find.textContaining('Gambar belum'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Gambar')), findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(find.text('Isi halaman dua.')), lessThan(top(image)));
    expect(top(image), lessThan(top(find.text('Budi pulang.'))));

    // Kalimat pengantar terpisah dari butir; tiap butir satu fokus tanpa
    // tanda butir di teksnya.
    final intro = find.bySemanticsLabel('Pada hari ini kamu akan belajar:');
    final first = find.bySemanticsLabel('Butir 1 dari 2: Mengenal ScratchJr');
    final second = find.bySemanticsLabel(
      'Butir 2 dari 2: Membuat karakter bergerak',
    );
    expect(intro, findsOneWidget);
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(top(intro), lessThan(top(first)));
    expect(top(first), lessThan(top(second)));
    expect(find.textContaining('- Mengenal'), findsNothing);
    expect(find.text('Halaman sebelumnya'), findsOneWidget);

    await tapAndPump(tester, find.text('Halaman sebelumnya'));
    await tester.pump();
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Halaman 1 dari 3: Ayo Menabung'),
    );
    handle.dispose();
  });

  testWidgets('halaman terakhir: Selesai kembali ke daftar materi', (
    tester,
  ) async {
    tallScreen(tester);
    _serve();
    await _openPages(tester);
    await tapAndPump(tester, find.text('Halaman 3: Penutup'));
    await tester.pumpAndSettle();

    expect(find.text('Halaman berikutnya'), findsNothing);
    expect(find.text('Halaman ini tidak berisi teks.'), findsOneWidget);
    await tapAndPump(tester, find.text('Selesai, kembali ke daftar materi'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar materi'), findsOneWidget);
    expect(find.byType(MaterialSectionsScreen), findsNothing);
  });
}
