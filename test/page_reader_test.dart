import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/models.dart';
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

  testWidgets('halaman 2 ScratchJR: daftar bertitik dan bernomor digambar '
      'aplikasi, tiap butir satu fokus', (tester) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        SectionReaderScreen(
          materialTitle: 'ScratchJR',
          sections: [
            MaterialSection(
              id: 's2',
              position: 2,
              title: '2. Send Message dan Receive Message',
              content:
                  'Pada hari ini kamu akan belajar:\n'
                  '- Membuka modul pembelajaran CodeJR.\n'
                  '- Mengenal code block Send Message di CodeJR.\n'
                  '- Mengenal code block Receive Message di CodeJR.\n'
                  '- Membuat satu project CodeJR dengan tema Amplop Ajaib.\n'
                  'Langkah pembuatan:\n'
                  '10. Klik icon gambar.\n'
                  '11. Masukkan 2 sprite.\n'
                  '12. Simpan proyekmu.\n'
                  'a) Sprite Budi\n'
                  'b) Sprite Gia',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final intro = find.bySemanticsLabel('Pada hari ini kamu akan belajar:');
    final first = find.bySemanticsLabel(
      'Butir 1 dari 4: Membuka modul pembelajaran CodeJR.',
    );
    final last = find.bySemanticsLabel(
      'Butir 4 dari 4: Membuat satu project CodeJR dengan tema Amplop Ajaib.',
    );
    expect(intro, findsOneWidget);
    expect(first, findsOneWidget);
    expect(last, findsOneWidget);
    expect(tester.getTopLeft(intro).dy, lessThan(tester.getTopLeft(first).dy));
    // Tanda butir digambar, bukan teks.
    expect(find.textContaining('•'), findsNothing);
    expect(find.textContaining('- '), findsNothing);
    expect(find.text('Membuka modul pembelajaran CodeJR.'), findsOneWidget);

    // Daftar bernomor memakai nomor aslinya, dibacakan kalau berbeda dari
    // urutannya.
    expect(find.text('10.'), findsOneWidget);
    expect(find.text('Klik icon gambar.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Butir 1 dari 3, nomor 10: Klik icon gambar.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Butir 3 dari 3, nomor 12: Simpan proyekmu.'),
      findsOneWidget,
    );
    expect(find.text('a)'), findsOneWidget);
    expect(find.bySemanticsLabel('Butir 2 dari 2: Sprite Gia'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tabel: ringkasan dibacakan dulu, tiap baris satu fokus yang '
      'menyebut nama kolom', (tester) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        SectionReaderScreen(
          materialTitle: 'ScratchJR',
          sections: [
            MaterialSection(
              id: 's9',
              position: 9,
              title: '7. Detektif Code',
              content:
                  'Pengantar tabel.\n'
                  '[[tabel:{"title": "7. Detektif Code", '
                  '"columns": ["Masalah", "Penyebab", "Perbaikan"], '
                  '"rows": [["Sprite diam", "1. Warna beda\\n2. Belum '
                  'tersambung", "Samakan warna."], ["Salah arah", "", '
                  '"Ganti blok"]]}]]\n'
                  'Sudah selesai.',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summary = find.bySemanticsLabel(
      'Tabel: 7. Detektif Code, 3 kolom, 2 baris',
    );
    final first = find.bySemanticsLabel(
      'Baris 1. Masalah: Sprite diam. Penyebab: 1. Warna beda. 2. Belum '
      'tersambung. Perbaikan: Samakan warna.',
    );
    final second = find.bySemanticsLabel(
      'Baris 2. Masalah: Salah arah. Perbaikan: Ganti blok.',
    );
    expect(summary, findsOneWidget);
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getSemantics(summary).flagsCollection.isHeader, isTrue);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(summary), lessThan(top(first)));
    expect(top(first), lessThan(top(second)));
    // Tabel tampil sebagai tabel, dan nama kolom tidak difokus sendiri.
    expect(find.text('Perbaikan'), findsOneWidget);
    expect(find.bySemanticsLabel('Perbaikan'), findsNothing);
    expect(find.textContaining('[[tabel'), findsNothing);
    handle.dispose();
  });

  testWidgets('penanda tabel yang rusak tidak dibacakan', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(
      testApp(
        SectionReaderScreen(
          materialTitle: 'ScratchJR',
          sections: [
            MaterialSection(
              id: 's',
              position: 1,
              title: 'Hal',
              content: 'Isi.\n[[tabel:{"title": 1}]]',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Isi.'), findsOneWidget);
    expect(find.textContaining('tabel'), findsNothing);
  });

  test('label butir menyebut nomor asli hanya kalau berbeda', () {
    expect(listItemLabel(0, 2, null, 'Satu'), 'Butir 1 dari 2: Satu');
    expect(listItemLabel(1, 2, '2.', 'Dua'), 'Butir 2 dari 2: Dua');
    expect(listItemLabel(0, 2, '3)', 'Tiga'), 'Butir 1 dari 2, nomor 3: Tiga');
    expect(listItemLabel(1, 2, 'b.', 'Bola'), 'Butir 2 dari 2: Bola');
  });
}
