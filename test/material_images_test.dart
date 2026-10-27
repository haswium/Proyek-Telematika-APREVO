import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/screens/teacher/material_images_screen.dart';

import 'fake_server.dart';

Map<String, dynamic> _image(
  String id, {
  String? description,
  bool deco = false,
  int page = 2,
}) => {
  'id': id,
  'image_key': 'xref-$id',
  'page_number': page,
  'description': description,
  'is_decorative': deco,
};

Map<String, dynamic> _status({
  bool running = false,
  int total = 0,
  int done = 0,
  List<Map<String, dynamic>> failed = const [],
}) => {
  'running': running,
  'total': total,
  'done': done,
  'failed': failed,
  'error': null,
  'pending': total - done,
};

const _rateLimit =
    'Batas pemakaian Gemini tercapai. Coba lagi beberapa menit lagi';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    testApp(
      const MaterialImagesScreen(materialId: 'm1', materialTitle: 'Menabung'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Satu putaran pemeriksaan progres.
Future<void> _poll(WidgetTester tester) async {
  await tester.pump(kDescribePollInterval);
  await tester.pumpAndSettle();
}

List<String> _said(WidgetTester tester) => [
  for (final a in tester.takeAnnouncements()) a.message,
];

void main() {
  testWidgets('progres di latar belakang: diumumkan saat ada yang gagal dan '
      'saat selesai saja', (tester) async {
    tallScreen(tester);
    var images = [_image('1', page: 1), _image('2'), _image('3', page: 3)];
    // Urutan jawaban GET status: sebelum mulai, lalu tiap pemeriksaan.
    final statuses = [
      _status(),
      _status(running: true, total: 3, done: 1),
      _status(
        running: true,
        total: 3,
        done: 1,
        failed: [
          {'image_id': '2', 'page_number': 2, 'message': _rateLimit},
        ],
      ),
      _status(
        total: 3,
        done: 2,
        failed: [
          {'image_id': '2', 'page_number': 2, 'message': _rateLimit},
        ],
      ),
    ];
    final server = FakeServer({
      'GET /teacher/materials/m1/images': (_) => {'images': images},
      'GET /teacher/materials/m1/image-description': (_) =>
          statuses.length > 1 ? statuses.removeAt(0) : statuses.first,
      'POST /teacher/materials/m1/generate-image-description': (_) =>
          _status(running: true, total: 3),
      'POST /teacher/materials/m1/images/2/describe': (_) {
        images = [images[0], _image('2', description: 'Celengan.'), images[2]];
        return {'image': images[1]};
      },
    })..install();
    final handle = tester.ensureSemantics();
    await _open(tester);
    tester.takeAnnouncements();

    await tapAndPump(tester, find.text('Buat deskripsi gambar dengan AI'));
    await tester.pumpAndSettle();
    expect(_said(tester), [
      'AI mulai membuat deskripsi 3 gambar, satu per satu. Hasilnya '
          'diumumkan saat selesai atau saat ada yang gagal.',
    ]);
    expect(find.text('Sedang membuat deskripsi...'), findsOneWidget);

    // Progres berubah, tetapi tidak dibacakan.
    images = [_image('1', description: 'Budi.', page: 1), ...images.skip(1)];
    await _poll(tester);
    expect(find.text('Sedang berjalan: 1 dari 3 gambar selesai'), findsOne);
    expect(_said(tester), isEmpty);

    // Gambar gagal: diumumkan sekali, proses lanjut.
    await _poll(tester);
    expect(_said(tester), [
      'Satu gambar di halaman 2 gagal dideskripsikan: $_rateLimit. Gambar '
          'lain tetap diproses.',
    ]);
    await _poll(tester);
    expect(_said(tester), [
      'Deskripsi gambar selesai: 2 dari 3. 1 gambar gagal. Coba lagi satu '
          'per satu lewat tombol di kartu gambarnya.',
    ]);
    expect(find.text('Terakhir: 2 dari 3 gambar selesai'), findsOne);

    // Setelah selesai, progres tidak diperiksa lagi.
    final checks = server.requests.where(
      (r) => r.url.path.endsWith('/image-description'),
    );
    final before = checks.length;
    await tester.pump(kDescribePollInterval * 3);
    expect(checks.length, before);

    // Gambar yang gagal dicoba ulang dari kartunya.
    expect(find.text('Gagal: $_rateLimit.'), findsOneWidget);
    await tapAndPump(tester, find.text('Coba lagi untuk gambar ini'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Deskripsi gambar 2 dari 3, halaman 2 dibuat. Periksa '
        'hasilnya.',
      ),
      findsOneWidget,
    );
    expect(find.text('Celengan.'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('proses yang sudah berjalan sejak unggah langsung dipantau', (
    tester,
  ) async {
    tallScreen(tester);
    final statuses = [
      _status(running: true, total: 2, done: 1),
      _status(total: 2, done: 2),
    ];
    FakeServer({
      'GET /teacher/materials/m1/images': (_) => {
        'images': [_image('1'), _image('2')],
      },
      'GET /teacher/materials/m1/image-description': (_) =>
          statuses.length > 1 ? statuses.removeAt(0) : statuses.first,
    }).install();
    final handle = tester.ensureSemantics();
    await _open(tester);
    expect(find.text('Sedang berjalan: 1 dari 2 gambar selesai'), findsOne);
    expect(find.text('Sedang membuat deskripsi...'), findsOneWidget);
    tester.takeAnnouncements();

    await _poll(tester);
    expect(_said(tester), [
      'Deskripsi gambar selesai: 2 dari 2. Periksa setiap deskripsi.',
    ]);
    expect(find.text('Buat deskripsi gambar dengan AI'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('guru memperbaiki deskripsi dan menandai dekoratif', (
    tester,
  ) async {
    tallScreen(tester);
    final images = [_image('1', description: 'Budi menabung.')];
    final server = FakeServer({
      'GET /teacher/materials/m1/images': (_) => {'images': images},
      'GET /teacher/materials/m1/image-description': (_) => _status(),
      'PATCH /teacher/materials/m1/images/1': (r) => {
        'image': {...images.first, ...jsonBody(r)},
      },
    })..install();
    await _open(tester);
    expect(find.textContaining('Belum dideskripsikan'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Budi memasukkan koin.');
    await tapAndPump(tester, find.text('Simpan deskripsi'));
    await tester.pumpAndSettle();
    expect(server.bodyOf('PATCH /teacher/materials/m1/images/1'), {
      'description': 'Budi memasukkan koin.',
    });
    expect(
      find.text('Deskripsi gambar 1 dari 1, halaman 2 disimpan.'),
      findsOneWidget,
    );

    await tapAndPump(tester, find.text('Dekoratif, tidak dibacakan'));
    await tester.pumpAndSettle();
    expect(server.bodyOf('PATCH /teacher/materials/m1/images/1'), {
      'is_decorative': true,
    });
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('gambar yang belum dideskripsikan didaftar', (tester) async {
    tallScreen(tester);
    FakeServer({
      'GET /teacher/materials/m1/images': (_) => {
        'images': [_image('1'), _image('2', deco: true)],
      },
      'GET /teacher/materials/m1/image-description': (_) => _status(),
    }).install();
    await _open(tester);
    expect(find.text('Belum dideskripsikan (1)'), findsOneWidget);
    expect(find.text('• Gambar 1, halaman 2'), findsOneWidget);
  });
}
