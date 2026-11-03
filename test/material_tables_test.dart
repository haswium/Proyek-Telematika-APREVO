import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/screens/teacher/material_tables_screen.dart';

import 'fake_server.dart';

const _marker =
    '[[tabel:{"title": "Detektif", "columns": ["Masalah", "Perbaikan"], '
    '"rows": [["Sprite diam", "Samakan warna"]]}]]';

const _patch = 'PATCH /teacher/materials/m1/sections/s9/tables/0';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    testApp(
      const MaterialTablesScreen(materialId: 'm1', materialTitle: 'ScratchJR'),
    ),
  );
  await tester.pumpAndSettle();
}

FakeServer _server({String content = _marker, Object Function()? onPatch}) =>
    FakeServer({
      'GET /materials/m1/sections': (_) => {
        'material': {'id': 'm1', 'title': 'ScratchJR'},
        'sections': [
          {
            'id': 's9',
            'position': 9,
            'title': 'Detektif',
            'content': content,
            'page_start': 9,
          },
        ],
        'images': [],
      },
      _patch: (_) => onPatch?.call() ?? {'message': 'Tabel disimpan'},
    });

void main() {
  testWidgets('guru mengedit sel tabel dan hasilnya dikirim utuh', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    final server = _server()..install();
    await _open(tester);

    expect(find.text('Tabel di halaman 9, 2 kolom, 1 baris'), findsOneWidget);
    final cell = find.widgetWithText(TextField, 'Sprite diam');
    expect(
      tester.widget<TextField>(cell).decoration?.labelText,
      'Baris 1, Masalah',
    );

    await tester.enterText(cell, 'Sprite tidak bergerak');
    await tester.tap(find.text('Simpan tabel'));
    await tester.pumpAndSettle();

    expect(server.bodyOf(_patch), {
      'title': 'Detektif',
      'columns': ['Masalah', 'Perbaikan'],
      'rows': [
        ['Sprite tidak bergerak', 'Samakan warna'],
      ],
    });
    expectLive(tester, 'Tabel disimpan.');
    handle.dispose();
  });

  testWidgets('penolakan server dibacakan', (tester) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    _server(
      onPatch: () =>
          jsonResponse({'detail': 'Semua kolom tabel harus punya nama.'}, 400),
    ).install();
    await _open(tester);
    await tester.tap(find.text('Simpan tabel'));
    await tester.pumpAndSettle();
    expectLive(tester, 'Semua kolom tabel harus punya nama.');
    handle.dispose();
  });

  testWidgets('materi tanpa tabel', (tester) async {
    tallScreen(tester);
    _server(content: 'Isi biasa.').install();
    await _open(tester);
    expect(find.text('Materi ini tidak punya tabel.'), findsOneWidget);
    expect(find.text('Simpan tabel'), findsNothing);
  });
}
