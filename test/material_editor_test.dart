import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/teacher/material_editor_screen.dart';
import 'package:aprevo/screens/teacher/material_images_screen.dart';
import 'package:aprevo/screens/teacher/subject_detail_screen.dart';

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

FakeServer _server(
  List<Map<String, dynamic>> images, {
  bool published = false,
  int hidden = 0,
}) => FakeServer({
  'GET /teacher/subjects/s1/materials': (_) => {
    'materials': [
      {
        'id': 'm1',
        'title': 'ScratchJR',
        'is_published': published,
        'hidden_image_count': hidden,
        'quizzes': [],
      },
    ],
  },
  'GET /teacher/materials/m1/images': (_) => {'images': images},
  'GET /teacher/materials/m1/image-description': (_) => {
    'running': false,
    'total': 0,
    'done': 0,
    'failed': [],
    'error': null,
    'pending': 0,
  },
});

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    testApp(
      MaterialEditorScreen(
        subject: Subject(id: 's1', name: 'Kelas 2'),
        material: LessonMaterial(
          id: 'm1',
          title: 'ScratchJR',
          published: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gambar belum dideskripsikan didaftar dan menghalangi terbit', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    final server = _server([
      _image('1', description: 'Budi memberi amplop.'),
      _image('2'),
      _image('3', deco: true),
      _image('4', description: '   '),
    ])..install();
    await _open(tester);

    expect(find.text('Belum dideskripsikan (2)'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Butir 1 dari 2: Gambar 2, halaman 2'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Butir 2 dari 2: Gambar 4, halaman 2'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Belum bisa terbit: 2 gambar belum dideskripsikan atau ditandai '
        'dekoratif.',
      ),
      findsOneWidget,
    );
    expect(server.requests.where((r) => r.method == 'PATCH'), isEmpty);
    handle.dispose();
  });

  testWidgets('tombol Lengkapi gambar membuka layar gambar', (tester) async {
    tallScreen(tester);
    _server([_image('1')]).install();
    await _open(tester);
    await tester.ensureVisible(find.text('Lengkapi gambar'));
    await tester.tap(find.text('Lengkapi gambar'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialImagesScreen), findsOneWidget);
  });

  const warning =
      '2 gambar di materi ini belum dideskripsikan dan disembunyikan dari '
      'siswa';

  testWidgets('materi terbit: peringatan gambar tersembunyi, lalu tombolnya '
      'membuka layar gambar', (tester) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    _server([_image('1'), _image('2')], published: true, hidden: 2).install();
    await _open(tester);

    expect(find.bySemanticsLabel(warning), findsOneWidget);
    // Syarat terbit tidak relevan lagi di materi yang sudah terbit.
    expect(find.textContaining('Belum dideskripsikan'), findsNothing);

    tester.semantics.tap(
      find.semantics.byLabel('Lengkapi gambar materi ScratchJR'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MaterialImagesScreen), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tombol di peringatan juga bisa diketuk langsung', (
    tester,
  ) async {
    tallScreen(tester);
    _server([_image('1'), _image('2')], published: true, hidden: 2).install();
    await _open(tester);
    await tester.tap(find.text('Lengkapi gambar'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialImagesScreen), findsOneWidget);
  });

  testWidgets('kartu materi di daftar kelas ikut memperingatkan', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    _server([_image('1'), _image('2')], published: true, hidden: 2).install();
    await tester.pumpWidget(
      testApp(
        SubjectDetailScreen(
          subject: Subject(id: 's1', name: 'Kelas 2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(warning), findsOneWidget);
    expect(
      find.bySemanticsLabel('Lengkapi gambar materi ScratchJR'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('materi terbit tanpa gambar tersembunyi: tanpa peringatan', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    _server([_image('1', description: 'Budi.')], published: true).install();
    await _open(tester);
    expect(find.textContaining('disembunyikan dari siswa'), findsNothing);
    expect(find.text('Lengkapi gambar'), findsNothing);
    handle.dispose();
  });

  testWidgets('semua gambar lengkap: daftar tidak muncul', (tester) async {
    tallScreen(tester);
    _server([
      _image('1', description: 'Budi memberi amplop.'),
      _image('2', deco: true),
    ]).install();
    await _open(tester);
    expect(find.textContaining('Belum dideskripsikan'), findsNothing);
    expect(find.text('Lengkapi gambar'), findsNothing);
  });
}
