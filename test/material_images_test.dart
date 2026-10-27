import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/screens/teacher/material_images_screen.dart';

import 'fake_server.dart';

Map<String, dynamic> _image(
  String id, {
  String? description,
  bool deco = false,
}) => {
  'id': id,
  'image_key': 'xref-$id',
  'page_number': 2,
  'description': description,
  'is_decorative': deco,
};

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    testApp(
      const MaterialImagesScreen(materialId: 'm1', materialTitle: 'Menabung'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guru melihat gambar yang belum dideskripsikan, lalu AI '
      'mendeskripsikannya dan guru memperbaikinya', (tester) async {
    tallScreen(tester);
    // Setelah unggah: gambar sudah tersimpan, deskripsinya belum ada.
    var images = [_image('1'), _image('2', deco: true)];
    final server = FakeServer({
      'GET /teacher/materials/m1/images': (_) => {'images': images},
      'POST /teacher/materials/m1/generate-image-description': (_) {
        images = [_image('1', description: 'Budi menabung.'), images[1]];
        return {'total_pending': 0, 'images': images};
      },
      'PATCH /teacher/materials/m1/images/1': (r) => {
        'image': {...images.first, ...jsonBody(r)},
      },
    })..install();
    final handle = tester.ensureSemantics();
    await _open(tester);
    expect(find.text('Belum dideskripsikan (1)'), findsOneWidget);
    expect(find.text('• Gambar 1, halaman 2'), findsOneWidget);

    await tapAndPump(tester, find.text('Buat deskripsi gambar dengan AI'));
    await tester.pumpAndSettle();
    expect(
      find.text('Deskripsi gambar selesai dibuat. Periksa setiap deskripsi.'),
      findsOneWidget,
    );
    expect(find.textContaining('Belum dideskripsikan'), findsNothing);
    expect(
      find.text('Semua gambar sudah punya deskripsi atau ditandai dekoratif.'),
      findsOneWidget,
    );
    expect(find.text('Gambar 1 dari 2, halaman 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Budi memasukkan koin.');
    await tapAndPump(tester, find.text('Simpan deskripsi'));
    await tester.pumpAndSettle();
    expect(server.bodyOf('PATCH /teacher/materials/m1/images/1'), {
      'description': 'Budi memasukkan koin.',
    });
    expect(
      find.text('Deskripsi gambar 1 dari 2, halaman 2 disimpan.'),
      findsOneWidget,
    );

    await tapAndPump(tester, find.text('Dekoratif, tidak dibacakan').first);
    await tester.pumpAndSettle();
    expect(server.bodyOf('PATCH /teacher/materials/m1/images/1'), {
      'is_decorative': true,
    });
    // Gambar dekoratif tidak perlu deskripsi.
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('Ditandai dekoratif, tidak dibacakan ke siswa.'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('gambar yang masih belum dideskripsikan disebutkan', (
    tester,
  ) async {
    tallScreen(tester);
    FakeServer({
      'GET /teacher/materials/m1/images': (_) => {
        'images': [_image('1'), _image('2')],
      },
      'POST /teacher/materials/m1/generate-image-description': (_) => {
        'total_pending': 2,
      },
    }).install();
    await _open(tester);
    expect(find.text('Belum dideskripsikan (2)'), findsOneWidget);
    await tapAndPump(tester, find.text('Buat deskripsi gambar dengan AI'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 gambar masih belum punya deskripsi'),
      findsOneWidget,
    );
  });
}
