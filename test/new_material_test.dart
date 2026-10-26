import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/teacher/new_material_screen.dart';
import 'package:aprevo/widgets/common.dart';

import 'fake_server.dart';

const int _mb = 1024 * 1024;

final _subject = Subject(id: 'ipa', name: 'IPA Kelas 5', accessCode: 'KXPRTA');

PickedPdf _pdf(String name, int size, {bool failRead = false}) => PickedPdf(
  name: name,
  size: size,
  readBytes: () async {
    if (failRead) throw Exception('tidak bisa dibaca');
    return Uint8List.fromList([37, 80, 68, 70]);
  },
);

final _uploadButton = find.widgetWithText(PrimaryButton, 'Unggah PDF');

Map<String, dynamic> _uploaded() => {
  'message': 'PDF berhasil diunggah dan diekstraksi.',
  'material': {
    'id': 'm1',
    'title': 'Gaya dan Gerak',
    'subject_id': 'ipa',
    'is_published': false,
  },
  'sections': [
    {
      'id': 's1',
      'position': 1,
      'title': 'Pendahuluan',
      'page_start': 1,
      'page_end': 1,
    },
    {
      'id': 's2',
      'position': 2,
      'title': 'Gaya Gesek',
      'page_start': 2,
      'page_end': 3,
    },
  ],
};

void main() {
  group('pemeriksaan PDF', () {
    test('ukuran dibulatkan ke atas', () {
      expect(fileSizeLabel(850 * 1024), '850 KB');
      expect(fileSizeLabel(2 * _mb), '2,0 MB');
      expect(fileSizeLabel(20 * _mb + 40 * 1024), '20,1 MB');
    });

    test('hanya PDF sampai 20 MB', () {
      expect(pdfProblem('Modul.PDF', 20 * _mb), isNull);
      expect(pdfProblem('modul.docx', 1024), contains('bukan PDF'));
      expect(
        pdfProblem('besar.pdf', 25 * _mb),
        'File besar.pdf terlalu besar, 25,0 MB. Batas ukuran PDF 20 MB. '
        'Pilih file yang lebih kecil.',
      );
      expect(pdfProblem('modul.pdf', null), contains('tidak bisa dibaca'));
    });
  });

  testWidgets('unggah PDF: file besar ditolak, lalu unggah berhasil', (
    tester,
  ) async {
    tallScreen(tester);
    final server = FakeServer({
      'POST /teacher/materials/upload': (_) => _uploaded(),
    }, delay: const Duration(seconds: 1))..install();
    final handle = tester.ensureSemantics();
    var next = _pdf('besar.pdf', 25 * _mb);
    await tester.pumpWidget(
      testApp(NewMaterialScreen(subject: _subject, pickFile: () async => next)),
    );

    await tapAndPump(tester, find.text('Pilih file PDF'));
    expectLive(
      tester,
      'File besar.pdf terlalu besar, 25,0 MB. Batas ukuran PDF 20 MB. '
      'Pilih file yang lebih kecil.',
    );

    next = _pdf('modul.pdf', 2 * _mb);
    await tapAndPump(tester, find.text('Pilih file PDF'));
    expectLive(tester, 'File dipilih: modul.pdf, 2,0 MB.');
    expect(find.bySemanticsLabel('File PDF: modul.pdf, 2,0 MB'), findsOne);

    await tapAndPump(tester, _uploadButton);
    expectLive(tester, 'Judul materi belum diisi.');

    await tester.enterText(find.byType(TextField), 'Gaya dan Gerak');
    await tapAndPump(tester, _uploadButton);
    expectLive(
      tester,
      'Mengunggah modul.pdf dan memecahnya per sub bab. Tunggu sebentar.',
    );

    await tester.pump(const Duration(seconds: 2));
    expectLive(
      tester,
      'Berhasil. modul.pdf diproses menjadi 2 sub bab. Materi draf Gaya dan '
      'Gerak siap diberi jadwal dan soal.',
    );
    final upload = server.requests.single;
    final body = String.fromCharCodes(upload.bodyBytes);
    expect(upload.headers['content-type'], startsWith('multipart/form-data'));
    expect(body, contains('name="title"'));
    expect(body, contains('Gaya dan Gerak'));
    expect(body, contains('name="subject_id"'));
    expect(body, contains('filename="modul.pdf"'));
    expect(find.text('Sub bab 2: Gaya Gesek'), findsOneWidget);
    expect(find.text('Lanjut atur jadwal dan soal'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('file tidak terbaca: pesan dan tombol coba lagi', (tester) async {
    tallScreen(tester);
    final server = FakeServer({})..install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        NewMaterialScreen(
          subject: _subject,
          pickFile: () async => _pdf('rusak.pdf', _mb, failRead: true),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Materi Rusak');
    await tapAndPump(tester, find.text('Pilih file PDF'));
    await tapAndPump(tester, _uploadButton);
    await tester.pumpAndSettle();
    expectLive(
      tester,
      'File rusak.pdf tidak bisa dibaca. Pilih ulang filenya, lalu coba lagi.',
    );
    expect(find.text('Coba unggah lagi'), findsOneWidget);
    expect(server.requests, isEmpty);
    handle.dispose();
  });

  testWidgets('server menolak PDF: pesan dari backend dibacakan', (
    tester,
  ) async {
    tallScreen(tester);
    FakeServer({
      'POST /teacher/materials/upload': (_) =>
          jsonResponse({'detail': 'PDF tidak bisa diproses'}, 400),
    }).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        NewMaterialScreen(
          subject: _subject,
          pickFile: () async => _pdf('modul.pdf', _mb),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Magnet');
    await tapAndPump(tester, find.text('Pilih file PDF'));
    await tapAndPump(tester, _uploadButton);
    await tester.pumpAndSettle();
    expectLive(tester, 'Gagal mengunggah modul.pdf. PDF tidak bisa diproses.');
    expect(find.text('Coba unggah lagi'), findsOneWidget);
    handle.dispose();
  });
}
