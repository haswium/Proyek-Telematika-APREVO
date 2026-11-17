import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/material_file.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/teacher/new_material_screen.dart';
import 'package:aprevo/widgets/common.dart';

import 'fake_server.dart';

const int _mb = 1024 * 1024;

final _subject = Subject(id: 'ipa', name: 'IPA Kelas 5', accessCode: 'KXPRTA');

PickedFile _file(String name, int size, {bool failRead = false}) => PickedFile(
  name: name,
  size: size,
  readBytes: () async {
    if (failRead) throw Exception('tidak bisa dibaca');
    return Uint8List.fromList([80, 75, 3, 4]);
  },
);

final _uploadButton = find.widgetWithText(PrimaryButton, 'Unggah materi');

Map<String, dynamic> _conversion(
  String status, {
  String? step,
  String? error,
}) => {
  'material_id': 'm1',
  'source_type': 'docx',
  'status': status,
  'step': step,
  'error': error,
};

Map<String, dynamic> _uploaded() => {
  'material': {
    'id': 'm1',
    'title': 'Gaya dan Gerak',
    'subject_id': 'ipa',
    'is_published': false,
    'section_count': 0,
  },
  'conversion': _conversion('processing', step: 'Menunggu giliran diproses.'),
};

Widget _screen(Future<PickedFile?> Function() pick) => testApp(
  NewMaterialScreen(
    subject: _subject,
    pickFile: pick,
    pollInterval: const Duration(milliseconds: 10),
  ),
);

void main() {
  group('pemeriksaan file sebelum unggah', () {
    test('ukuran dibulatkan ke atas', () {
      expect(fileSizeLabel(850 * 1024), '850 KB');
      expect(fileSizeLabel(2 * _mb), '2,0 MB');
      expect(fileSizeLabel(20 * _mb + 40 * 1024), '20,1 MB');
    });

    test('semua format yang didukung diterima sampai batasnya', () {
      for (final name in [
        'Modul.PDF',
        'a.docx',
        'a.pptx',
        'a.xlsx',
        'a.csv',
        'a.txt',
        'a.md',
        'foto.JPG',
        'a.jpeg',
        'a.png',
        'a.mp3',
        'a.m4a',
        'a.wav',
        'a.ogg',
      ]) {
        expect(uploadProblem(name, 1024), isNull, reason: name);
      }
      expect(uploadProblem('a.mp3', 25 * _mb), isNull);
      expect(
        uploadProblem('besar.xlsx', 11 * _mb),
        'File besar.xlsx terlalu besar, 11,0 MB. Batas ukuran Excel 10 MB. '
        'Pilih file yang lebih kecil.',
      );
      expect(
        uploadProblem('a.wav', 26 * _mb),
        contains('Batas ukuran audio 25 MB'),
      );
      expect(uploadProblem('modul.pdf', null), contains('tidak bisa dibaca'));
    });

    test('format lama: petunjuk menyimpan ulang', () {
      expect(
        uploadProblem('lama.doc', 1024),
        'Format .doc lama tidak didukung. Simpan ulang lama.doc sebagai .docx '
        'lalu unggah lagi.',
      );
      expect(uploadProblem('lama.ppt', 1024), contains('sebagai .pptx'));
      expect(uploadProblem('lama.xls', 1024), contains('sebagai .xlsx'));
      expect(uploadProblem('film.mp4', 1024), contains('tidak didukung'));
    });

    test('content type unggahan sesuai format', () {
      expect(contentTypeFor('a.pdf'), 'application/pdf');
      expect(contentTypeFor('a.m4a'), 'audio/mp4');
      expect(
        contentTypeFor('a.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(contentTypeFor('a.xyz'), 'application/octet-stream');
    });
  });

  testWidgets('teks bantuan satu kalimat, tanpa rincian ukuran', (
    tester,
  ) async {
    FakeServer({}).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_screen(() async => null));
    const help =
        'Bisa unggah materi dalam bentuk apa pun: dokumen, presentasi, tabel, '
        'teks, foto, atau audio.';
    expect(kUploadHelp, help);
    expect(find.bySemanticsLabel(help), findsOneWidget);
    expect(find.textContaining('MB'), findsNothing);
    handle.dispose();
  });

  testWidgets('unggah DOCX: status konversi diumumkan sampai selesai', (
    tester,
  ) async {
    tallScreen(tester);
    var checks = 0;
    final server = FakeServer({
      'POST /teacher/materials/files': (_) => _uploaded(),
      'GET /teacher/materials/m1/conversion': (_) {
        checks++;
        if (checks == 1) {
          return _conversion('processing', step: 'Membaca dokumen Word.');
        }
        if (checks == 2) {
          // Langkah sama: tidak diumumkan ulang.
          return _conversion('processing', step: 'Membaca dokumen Word.');
        }
        return _conversion('ready', step: 'Selesai: 3 halaman, 1 gambar.');
      },
      'POST /teacher/materials/m1/generate-image-description': (_) => {
        'running': true,
        'total': 1,
        'done': 0,
      },
    }, delay: const Duration(milliseconds: 20))..install();
    final handle = tester.ensureSemantics();
    var next = _file('besar.docx', 25 * _mb);
    await tester.pumpWidget(_screen(() async => next));

    await tapAndPump(tester, find.text('Pilih file materi'));
    expectLive(
      tester,
      'File besar.docx terlalu besar, 25,0 MB. Batas ukuran Word 20 MB. '
      'Pilih file yang lebih kecil.',
    );

    next = _file('gaya.docx', 2 * _mb);
    await tapAndPump(tester, find.text('Pilih file materi'));
    expectLive(tester, 'File dipilih: gaya.docx, 2,0 MB.');
    expect(find.bySemanticsLabel('File Word: gaya.docx, 2,0 MB'), findsOne);

    await tester.enterText(find.byType(TextField), 'Gaya dan Gerak');
    await tapAndPump(tester, _uploadButton);
    expectLive(tester, 'Mengunggah gaya.docx. Tunggu sebentar.');

    // Pantau sampai selesai (jeda server 20 ms, jeda pantau 10 ms).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();

    final upload = server.requests.first;
    final body = String.fromCharCodes(upload.bodyBytes);
    expect(upload.url.path, '/teacher/materials/files');
    expect(body, contains('filename="gaya.docx"'));
    expect(
      body,
      contains(
        'content-type: application/vnd.openxmlformats-officedocument.'
        'wordprocessingml.document',
      ),
    );
    expect(checks, 3);
    expectLive(
      tester,
      'Selesai: 3 halaman, 1 gambar. AI sedang membuat deskripsi 1 gambar di '
      'latar belakang. Periksa hasilnya di menu Gambar dan deskripsi sebelum '
      'terbit. Materi draf Gaya dan Gerak siap diperiksa, diberi jadwal, dan '
      'soal.',
    );
    expect(
      find.text('Lanjut periksa materi, jadwal, dan soal'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('konversi gagal: pesan dibacakan, materi gagal dihapus', (
    tester,
  ) async {
    tallScreen(tester);
    final server = FakeServer({
      'POST /teacher/materials/files': (_) => _uploaded(),
      'GET /teacher/materials/m1/conversion': (_) =>
          _conversion('failed', error: 'Dokumen Word tidak bisa dibaca.'),
      'DELETE /teacher/materials/m1': (_) => {'message': 'Materi dihapus'},
    })..install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_screen(() async => _file('rusak.docx', _mb)));
    await tester.enterText(find.byType(TextField), 'Rusak');
    await tapAndPump(tester, find.text('Pilih file materi'));
    await tapAndPump(tester, _uploadButton);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expectLive(
      tester,
      'rusak.docx gagal diproses. Dokumen Word tidak bisa dibaca.',
    );
    expect(
      server.requests.map((r) => '${r.method} ${r.url.path}'),
      contains('DELETE /teacher/materials/m1'),
    );
    expect(find.text('Coba unggah lagi'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('file tidak terbaca: pesan dan tombol coba lagi', (tester) async {
    tallScreen(tester);
    final server = FakeServer({})..install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _screen(() async => _file('rusak.pdf', _mb, failRead: true)),
    );
    await tester.enterText(find.byType(TextField), 'Materi Rusak');
    await tapAndPump(tester, find.text('Pilih file materi'));
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

  testWidgets('server menolak file: pesan dari backend dibacakan', (
    tester,
  ) async {
    tallScreen(tester);
    FakeServer({
      'POST /teacher/materials/files': (_) => jsonResponse({
        'detail': 'Format .ppt lama tidak didukung. Simpan ulang sebagai .pptx lalu unggah lagi.',
      }, 400),
    }).install();
    final handle = tester.ensureSemantics();
    // Nama .pptx padahal isinya format lama: hanya backend yang tahu.
    await tester.pumpWidget(_screen(() async => _file('slide.pptx', _mb)));
    await tester.enterText(find.byType(TextField), 'Magnet');
    await tapAndPump(tester, find.text('Pilih file materi'));
    await tapAndPump(tester, _uploadButton);
    await tester.pumpAndSettle();
    expectLive(
      tester,
      'Gagal mengunggah slide.pptx. Format .ppt lama tidak didukung. Simpan '
      'ulang sebagai .pptx lalu unggah lagi.',
    );
    expect(find.text('Coba unggah lagi'), findsOneWidget);
    handle.dispose();
  });
}
