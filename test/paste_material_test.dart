// Guru membuat materi dengan menempel teks, lewat pratinjau pembagian halaman.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/models.dart';
import 'package:aprevo/models/pasted_text.dart';
import 'package:aprevo/screens/teacher/material_editor_screen.dart';
import 'package:aprevo/screens/teacher/paste_material_screen.dart';

import 'fake_server.dart';

final _subject = Subject(id: 's1', name: '7 Geografi');

const _preview = 'POST /teacher/materials/text/preview';
const _create = 'POST /teacher/materials/text';

const _text = 'Musim\n\nAda dua musim:\n- kemarau\n- hujan';

Map<String, dynamic> _page(String title, String content) => {
  'title': title,
  'content': content,
  'paragraph_count': 1,
  'subheading_count': 0,
  'list_item_count': 2,
  'word_count': 5,
};

FakeServer _server() => FakeServer({
  _preview: (_) => {
    'pages': [
      _page('Musim', 'Ada dua musim:\n- kemarau\n- hujan'),
      _page('Iklim', 'Iklim adalah rata-rata cuaca.'),
    ],
  },
  _create: (_) => {
    'material': {
      'id': 'm9',
      'title': 'Cuaca',
      'subject_id': 's1',
      'is_published': false,
      'file_url': '',
    },
    'sections': [
      {'id': 'x1', 'position': 1, 'title': 'Musim'},
      {'id': 'x2', 'position': 2, 'title': 'Iklim'},
    ],
  },
})..install();

Future<void> _open(WidgetTester tester) async {
  tallScreen(tester);
  await tester.pumpWidget(testApp(PasteMaterialScreen(subject: _subject)));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {String text = _text}) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Judul materi'),
    'Cuaca',
  );
  await tester.enterText(find.widgetWithText(TextField, 'Isi materi'), text);
  await tester.pump();
}

const _summary = 'Pratinjau: teks terbagi menjadi 2 halaman: Musim, Iklim.';

void main() {
  testWidgets('aturan pembagian halaman tertulis dan dibaca', (tester) async {
    _server();
    final handle = tester.ensureSemantics();
    await _open(tester);
    expect(find.bySemanticsLabel(kPasteRule), findsOneWidget);
    // Simpan baru muncul setelah ada pratinjau.
    expect(find.text('Simpan sebagai draf'), findsNothing);
    handle.dispose();
  });

  testWidgets('teks kosong: error dibacakan, tidak ke server', (tester) async {
    final server = _server();
    final handle = tester.ensureSemantics();
    await _open(tester);

    await tapAndPump(tester, find.text('Lihat pratinjau halaman'));
    expectLive(tester, 'Tempel isi materi dulu di kolom teks.');
    expect(server.requests, isEmpty);
    handle.dispose();
  });

  testWidgets('pratinjau: ringkasan difokus, tiap halaman bisa dibuka', (
    tester,
  ) async {
    final server = _server();
    final handle = tester.ensureSemantics();
    await _open(tester);
    await _fill(tester);
    final reader = watchScreenReader(tester);

    await tapAndPump(tester, find.text('Lihat pratinjau halaman'));
    await tester.pumpAndSettle();

    expect(server.bodyOf(_preview), {'title': 'Cuaca', 'text': _text});
    // Ringkasan menyebut jumlah dan judul halaman, dan fokus TalkBack pindah
    // ke sana.
    expect(
      tester.getSemantics(find.bySemanticsLabel(_summary)),
      isSemantics(label: _summary, isHeader: true),
    );
    expect(reader.focusedOn(tester, find.bySemanticsLabel(_summary)), isTrue);

    const closed =
        'Halaman 1: Musim, tertutup. 1 paragraf, 2 butir daftar, 5 kata';
    expect(find.bySemanticsLabel(closed), findsOneWidget);
    expect(find.bySemanticsLabel('Butir: kemarau'), findsNothing);

    await tapAndPump(tester, find.text('Halaman 1: Musim'));
    expect(reader.said, contains('Halaman 1: Musim dibuka'));
    expect(
      find.bySemanticsLabel(RegExp(r'^Halaman 1: Musim, terbuka')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Ada dua musim:'), findsOneWidget);
    expect(find.bySemanticsLabel('Butir: kemarau'), findsOneWidget);
    expect(find.bySemanticsLabel('Butir: hujan'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('teks diubah setelah pratinjau: simpan dikunci', (tester) async {
    final server = _server();
    final handle = tester.ensureSemantics();
    await _open(tester);
    await _fill(tester);
    await tapAndPump(tester, find.text('Lihat pratinjau halaman'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Isi materi'),
      '$_text\n\nTambahan.',
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel(
        'Pratinjau lama. Teks sudah berubah, lihat pratinjau halaman lagi.',
      ),
      findsOneWidget,
    );
    final save = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Simpan sebagai draf'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(save.onPressed, isNull);
    expect(server.requests.where((r) => r.url.path.endsWith('/text')), isEmpty);
    handle.dispose();
  });

  testWidgets('simpan: materi draf dibuat lalu editor terbuka', (tester) async {
    final server = _server();
    await _open(tester);
    await _fill(tester);
    await tapAndPump(tester, find.text('Lihat pratinjau halaman'));
    await tester.pumpAndSettle();

    await tapAndPump(tester, find.text('Simpan sebagai draf'));
    await tester.pump();
    await tester.pump();

    expect(server.bodyOf(_create), {
      'title': 'Cuaca',
      'subject_id': 's1',
      'text': _text,
    });
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MaterialEditorScreen), findsOneWidget);
    expect(find.byType(PasteMaterialScreen), findsNothing);
  });
}
