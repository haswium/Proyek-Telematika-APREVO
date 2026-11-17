// Panduan di dalam aplikasi dan saklar efek bunyi di Profil.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/data/guide.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/guide_screen.dart';
import 'package:aprevo/screens/profile_tab.dart';
import 'package:aprevo/screens/teacher/teacher_shell.dart';
import 'package:aprevo/services/settings.dart';

import 'fake_server.dart';

Account _account(UserRole role) => Account(
  name: role == UserRole.teacher ? 'Bu Rina' : 'Dimas',
  email: role == UserRole.teacher ? 'guru@contoh.id' : 'siswa@contoh.id',
  role: role,
);

void _signIn(UserRole role) {
  store.currentUser = _account(role);
  addTearDown(() => store.currentUser = null);
}

void main() {
  for (final role in UserRole.values) {
    testWidgets(
      'panduan ${role.label}: satu judul per fitur, langkah bernomor',
      (tester) async {
        tallScreen(tester);
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(testApp(GuideScreen(role: role)));
        await tester.pumpAndSettle();

        final sections = guideFor(role);
        expect(sections.length, greaterThanOrEqualTo(5));
        for (final section in sections) {
          await tester.scrollUntilVisible(
            find.text(section.title),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            tester.getSemantics(find.text(section.title)),
            isSemantics(label: section.title, isHeader: true),
          );
          final total = section.steps.length;
          // Panduan panjang: langkah pertama bisa di bawah layar saat
          // judulnya terlihat.
          final firstStep = find.bySemanticsLabel(
            'Langkah 1 dari $total: ${section.steps.first}',
          );
          await tester.scrollUntilVisible(
            firstStep,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(firstStep, findsOneWidget);
        }
        handle.dispose();
      },
    );
  }

  test('panduan siswa membahas fitur yang dipakai siswa', () {
    final titles = studentGuide.map((s) => s.title).join(' | ');
    for (final word in ['kelas', 'materi', 'kuis', 'pembahasan', 'Presensi']) {
      expect(titles, contains(word));
    }
  });

  test('panduan guru membahas tempel teks dan presensi', () {
    final text = teacherGuide.expand((s) => s.steps).join(' ');
    expect(text, contains('Tempel teks'));
    expect(text, contains('Buka sesi presensi'));
  });

  testWidgets('Profil: menu Panduan membuka panduan sesuai peran', (
    tester,
  ) async {
    tallScreen(tester);
    _signIn(UserRole.teacher);
    await tester.pumpWidget(testApp(const ProfileTab()));
    await tester.pumpAndSettle();

    await tapAndPump(tester, find.text('Panduan'));
    await tester.pumpAndSettle();
    expect(find.text('Panduan APREVO untuk guru'), findsOneWidget);
    // Guru tidak mengerjakan kuis, jadi saklar bunyi hanya untuk siswa.
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Efek bunyi benar dan salah'), findsNothing);
  });

  testWidgets('Profil siswa: efek bunyi menyala bawaan dan bisa dimatikan', (
    tester,
  ) async {
    tallScreen(tester);
    _signIn(UserRole.student);
    addTearDown(() => Settings.setSoundEffects(true));
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const ProfileTab()));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(
      SwitchListTile,
      'Efek bunyi benar dan salah',
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      tester.getSemantics(toggle),
      isSemantics(hasToggledState: true, isToggled: true, hasTapAction: true),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(Settings.soundEffects, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    handle.dispose();
  });

  group('tawaran panduan pertama kali', () {
    setUp(() => Settings.offerGuide = true);
    tearDown(() => Settings.offerGuide = false);

    testWidgets('ditawarkan sekali, judul dialog dibacakan', (tester) async {
      tallScreen(tester);
      FakeServer({}).install();
      _signIn(UserRole.teacher);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(testApp(const TeacherShell()));
      await tester.pumpAndSettle();

      expect(find.text('Mau membaca panduan dulu?'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.namesRoute == true &&
              widget.properties.label == 'Mau membaca panduan dulu?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Buka panduan'));
      await tester.pumpAndSettle();
      expect(find.text('Panduan APREVO untuk guru'), findsOneWidget);

      // Dibuka lagi: tidak ditawarkan lagi untuk akun ini.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(testApp(const TeacherShell()));
      await tester.pumpAndSettle();
      expect(find.text('Mau membaca panduan dulu?'), findsNothing);
      handle.dispose();
    });

    testWidgets('Nanti saja menutup dialog dan tetap di beranda', (
      tester,
    ) async {
      tallScreen(tester);
      FakeServer({}).install();
      store.currentUser = Account(
        name: 'Bu Sari',
        email: 'sari@contoh.id',
        role: UserRole.teacher,
      );
      addTearDown(() => store.currentUser = null);
      await tester.pumpWidget(testApp(const TeacherShell()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nanti saja'));
      await tester.pumpAndSettle();
      expect(find.text('Mau membaca panduan dulu?'), findsNothing);
      expect(find.text('Panduan APREVO untuk guru'), findsNothing);
      expect(Settings.guideOffered('sari@contoh.id'), isTrue);
    });
  });
}
