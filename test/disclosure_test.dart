// Masukan uji coba SLB: "kadang buka tutup kurang, tidak dibaca screen
// reader". Elemen buka-tutup harus menyebut statusnya, dan dialog harus
// dibacakan dengan judulnya.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/login_screen.dart';
import 'package:aprevo/screens/teacher/attendance_session_form_screen.dart';
import 'package:aprevo/screens/teacher/teacher_home_screen.dart';
import 'package:aprevo/widgets/disclosure.dart';

import 'fake_server.dart';

Widget _disclosureApp() => testApp(
  Scaffold(
    body: ListView(
      children: [
        const Text('Sebelum'),
        Disclosure(
          title: 'Halaman 1: Iklim',
          summary: '2 paragraf, 12 kata',
          child: Column(
            children: [Text('Isi paragraf satu.'), Text('Isi paragraf dua.')],
          ),
        ),
        const Text('Sesudah'),
      ],
    ),
  ),
);

/// Label dalam urutan geser kanan TalkBack.
List<String> _labelsInOrder(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.label.isNotEmpty) node.label,
];

void main() {
  group('Disclosure', () {
    testWidgets('tertutup: label menyebut status, isinya tidak terbaca', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_disclosureApp());

      const label = 'Halaman 1: Iklim, tertutup. 2 paragraf, 12 kata';
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
          label: label,
          hint: 'Ketuk dua kali untuk membuka',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Isi paragraf satu.'), findsNothing);
      handle.dispose();
    });

    testWidgets('dibuka: status diumumkan, isi tepat setelah tombolnya', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_disclosureApp());

      await tester.tap(find.text('Halaman 1: Iklim'));
      await tester.pump();

      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Halaman 1: Iklim dibuka'),
      );
      const label = 'Halaman 1: Iklim, terbuka. 2 paragraf, 12 kata';
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
          label: label,
          hint: 'Ketuk dua kali untuk menutup',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
        ),
      );
      // Isi yang baru muncul bisa difokus, dan urutannya langsung setelah
      // tombol: satu geser ke kanan dari tombol sampai ke isi.
      final order = _labelsInOrder(tester);
      final button = order.indexOf(label);
      expect(order.sublist(button, button + 4), [
        label,
        'Isi paragraf satu.',
        'Isi paragraf dua.',
        'Sesudah',
      ]);

      await tester.tap(find.text('Halaman 1: Iklim'));
      await tester.pump();
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Halaman 1: Iklim ditutup'),
      );
      expect(find.bySemanticsLabel('Isi paragraf satu.'), findsNothing);
      handle.dispose();
    });

    testWidgets('bisa dibuka lewat aksi tap semantics (TalkBack)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_disclosureApp());
      tester.semantics.tap(
        find.semantics.byLabel(RegExp(r'^Halaman 1: Iklim, tertutup')),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Isi paragraf satu.'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('dialog dibacakan dengan judulnya, bukan "Peringatan"', (
    tester,
  ) async {
    FakeServer({
      'GET /teacher/subjects': (_) => {'subjects': []},
    }).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const TeacherHomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buat Kelas'));
    await tester.pumpAndSettle();

    // Node yang menamai route dialog berlabel judul dialog.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.namesRoute == true &&
            widget.properties.label == 'Kelas baru',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('tombol lihat password: status saklar dan pengumuman', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const LoginScreen()));
    await tester.pumpAndSettle();

    final toggle = find.byTooltip('Tampilkan password');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tampilkan password')),
      isSemantics(
        label: 'Tampilkan password',
        hasToggledState: true,
        isToggled: false,
        isButton: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(toggle);
    await tester.pump();
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Password terlihat'),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sembunyikan password')),
      isSemantics(
        label: 'Sembunyikan password',
        hasToggledState: true,
        isToggled: true,
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('pemilih tanggal terbuka dalam mode ketik, kalender opsional', (
    tester,
  ) async {
    tallScreen(tester);
    FakeServer({}).install();
    await tester.pumpWidget(
      testApp(
        AttendanceSessionFormScreen(
          subject: Subject(id: 's1', name: '7 Geografi'),
          suggestedTitle: 'Pertemuan 1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Atur sendiri').first);
    await tester.pumpAndSettle();

    // Kolom ketik tanggal, bukan kalender bertingkat dengan dropdown tahun.
    expect(find.text('Pilih tanggal buka'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Tanggal buka'), findsOneWidget);
    expect(find.byTooltip('Beralih ke kalender'), findsOneWidget);
  });
}
