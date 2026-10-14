import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/screens/teacher/new_material_screen.dart';
import 'package:aprevo/theme/app_theme.dart';
import 'package:aprevo/widgets/common.dart';

/// Sama seperti AprevoApp, dengan animasi dimatikan supaya pumpAndSettle
/// tidak menunggu animasi berulang.
Widget _app(Widget home) => MaterialApp(
  theme: buildAprevoTheme(),
  locale: const Locale('id', 'ID'),
  supportedLocales: const [Locale('id', 'ID')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: home,
);

const int _mb = 1024 * 1024;

PickedPdf _pdf(String name, int size, {bool failRead = false}) => PickedPdf(
  name: name,
  size: size,
  readBytes: () async {
    if (failRead) throw Exception('tidak bisa dibaca');
    return Uint8List(0);
  },
);

/// Pesan di liveRegion: TalkBack membacakannya begitu muncul.
void _expectLive(WidgetTester tester, String message) {
  expect(
    tester.getSemantics(find.bySemanticsLabel(message)),
    matchesSemantics(label: message, isLiveRegion: true),
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

final _uploadButton = find.widgetWithText(PrimaryButton, 'Unggah PDF');

/// Layar tes dibuat tinggi supaya ListView membangun semua tombol.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

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
    _tallScreen(tester);
    final handle = tester.ensureSemantics();
    final subject = store.createSubject('Uji Unggah');
    var next = _pdf('besar.pdf', 25 * _mb);
    await tester.pumpWidget(
      _app(NewMaterialScreen(subject: subject, pickFile: () async => next)),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Sumber materi: Unggah PDF')),
      matchesSemantics(
        label: 'Sumber materi: Unggah PDF',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );

    await _tap(tester, find.text('Pilih file PDF'));
    _expectLive(
      tester,
      'File besar.pdf terlalu besar, 25,0 MB. Batas ukuran PDF 20 MB. '
      'Pilih file yang lebih kecil.',
    );

    next = _pdf('modul.pdf', 2 * _mb);
    await _tap(tester, find.text('Pilih file PDF'));
    _expectLive(tester, 'File dipilih: modul.pdf, 2,0 MB.');
    expect(find.bySemanticsLabel('File PDF: modul.pdf, 2,0 MB'), findsOne);

    await _tap(tester, _uploadButton);
    _expectLive(tester, 'Judul materi belum diisi.');

    await tester.enterText(find.byType(TextField), 'Gaya dan Gerak');
    await _tap(tester, _uploadButton);
    _expectLive(tester, 'Mengunggah modul.pdf. Tunggu sebentar.');

    await tester.pump(const Duration(seconds: 2));
    _expectLive(
      tester,
      'Berhasil. modul.pdf diunggah sebagai materi draf Gaya dan Gerak.',
    );
    final material = subject.materials.single;
    expect(material.sourceFileName, 'modul.pdf');
    expect(material.published, isFalse);

    await _tap(tester, find.text('Lanjut buat soal'));
    await tester.pumpAndSettle();
    expect(find.text('Dari PDF: modul.pdf'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('unggah PDF gagal: pesan gagal dan tombol coba lagi', (
    tester,
  ) async {
    _tallScreen(tester);
    final handle = tester.ensureSemantics();
    final subject = store.createSubject('Uji Gagal');
    await tester.pumpWidget(
      _app(
        NewMaterialScreen(
          subject: subject,
          pickFile: () async => _pdf('rusak.pdf', _mb, failRead: true),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Materi Rusak');
    await _tap(tester, find.text('Pilih file PDF'));
    await _tap(tester, _uploadButton);
    await tester.pump(const Duration(seconds: 2));
    _expectLive(
      tester,
      'Gagal mengunggah rusak.pdf. Periksa sambungan internet, lalu coba '
      'lagi.',
    );
    expect(find.text('Coba unggah lagi'), findsOneWidget);
    expect(subject.materials, isEmpty);
    handle.dispose();
  });

  testWidgets('ketik materi: judul wajib, lalu masuk ke editor', (
    tester,
  ) async {
    _tallScreen(tester);
    final handle = tester.ensureSemantics();
    final subject = store.createSubject('Uji Ketik');
    await tester.pumpWidget(_app(NewMaterialScreen(subject: subject)));

    await _tap(tester, find.text('Ketik materi'));
    await _tap(tester, find.text('Lanjut buat soal'));
    _expectLive(tester, 'Judul materi belum diisi.');

    await tester.enterText(find.byType(TextField).first, 'Magnet');
    await tester.enterText(
      find.byType(TextField).last,
      'Magnet menarik benda dari besi.',
    );
    await _tap(tester, find.text('Lanjut buat soal'));
    await tester.pumpAndSettle();
    expect(subject.materials.single.sourceFileName, isNull);
    expect(find.text('Magnet menarik benda dari besi.'), findsOneWidget);
    handle.dispose();
  });
}
