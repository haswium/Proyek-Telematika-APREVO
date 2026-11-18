// Panduan sebagai buku interaktif, dan saklar efek bunyi di Profil.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/data/guide.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/guide_screen.dart';
import 'package:aprevo/screens/profile_tab.dart';
import 'package:aprevo/screens/teacher/teacher_shell.dart';
import 'package:aprevo/services/settings.dart';
import 'package:aprevo/widgets/mascot.dart';

import 'fake_server.dart';
import 'fake_sound.dart';

Account _account(UserRole role) => Account(
  name: role == UserRole.teacher ? 'Bu Rina' : 'Dimas',
  email: role == UserRole.teacher ? 'guru@contoh.id' : 'siswa@contoh.id',
  role: role,
);

void _signIn(UserRole role) {
  store.currentUser = _account(role);
  addTearDown(() => store.currentUser = null);
}

int _pageCount(UserRole role) =>
    1 + guideFor(role).fold<int>(0, (sum, c) => sum + c.pages.length);

/// Buku panduan di atas satu layar lain, supaya tombol Selesai bisa kembali.
Future<void> _openBook(
  WidgetTester tester,
  UserRole role, {
  bool animations = false,
}) async {
  tallScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openGuide(context, role),
            child: const Text('Buka buku'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka buku'));
  // Dengan animasi, Odi bergerak terus: pumpAndSettle tidak pernah selesai.
  if (animations) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  } else {
    await tester.pumpAndSettle();
  }
}

Finder _heading(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.header == true &&
      widget.child is Text &&
      (widget.child! as Text).data == text,
);

void main() {
  test('bab sesuai peran', () {
    expect(studentGuide.map((c) => c.title), [
      'Masuk dan daftar',
      'Kelas',
      'Baca materi',
      'Kuis',
      'Presensi',
    ]);
    expect(teacherGuide.map((c) => c.title), [
      'Masuk dan daftar',
      'Kelas',
      'Baca materi',
      'Kuis',
      'Presensi',
      'Unggah materi',
      'Buat soal',
      'Progres siswa',
    ]);
    for (final chapter in [...studentGuide, ...teacherGuide]) {
      expect(chapter.pages, isNotEmpty, reason: chapter.title);
    }
  });

  testWidgets('halaman 1 daftar isi, bab bisa langsung dipilih', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openBook(tester, UserRole.student);
    final total = _pageCount(UserRole.student);

    expect(_heading('Daftar isi'), findsOneWidget);
    expect(find.text('Halaman 1 dari $total'), findsOneWidget);
    const label = 'Bab 4: Kuis. 4 halaman, mulai halaman 12';
    expect(
      tester.getSemantics(find.bySemanticsLabel(label)),
      isSemantics(label: label, isButton: true, hasTapAction: true),
    );
    final reader = watchScreenReader(tester);

    await tester.tap(find.bySemanticsLabel(label));
    await tester.pumpAndSettle();
    expect(_heading('Pre-test dan post-test'), findsOneWidget);
    expect(_heading('Bab 4: Kuis'), findsOneWidget);
    expect(reader.said, ['Halaman 12 dari $total: Pre-test dan post-test']);
    expect(
      reader.focusedOn(tester, find.text('Pre-test dan post-test')),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('tombol sebelumnya, berikutnya, dan daftar isi', (tester) async {
    final handle = tester.ensureSemantics();
    await _openBook(tester, UserRole.student);
    final total = _pageCount(UserRole.student);
    final reader = watchScreenReader(tester);

    // Di daftar isi, tombol sebelumnya dan daftar isi tidak aktif.
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Halaman sebelumnya'),
          )
          .onPressed,
      isNull,
    );

    await tapAndPump(tester, find.text('Halaman berikutnya'));
    await tester.pumpAndSettle();
    expect(reader.said.last, 'Halaman 2 dari $total: Membuka APREVO');
    expect(reader.focusedOn(tester, find.text('Membuka APREVO')), isTrue);

    await tapAndPump(tester, find.text('Halaman berikutnya'));
    await tester.pumpAndSettle();
    expect(reader.said.last, 'Halaman 3 dari $total: Daftar akun baru');

    await tapAndPump(tester, find.text('Halaman sebelumnya'));
    await tester.pumpAndSettle();
    expect(reader.said.last, 'Halaman 2 dari $total: Membuka APREVO');

    await tapAndPump(tester, find.text('Daftar isi'));
    await tester.pumpAndSettle();
    expect(reader.said.last, 'Halaman 1 dari $total: Daftar isi');
    expect(reader.focusedOn(tester, find.text('Daftar isi').first), isTrue);
    handle.dispose();
  });

  testWidgets('halaman terakhir: Selesai menutup buku', (tester) async {
    await _openBook(tester, UserRole.student);
    final total = _pageCount(UserRole.student);
    for (var i = 1; i < total; i++) {
      await tapAndPump(tester, find.text('Halaman berikutnya'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Halaman $total dari $total'), findsOneWidget);
    expect(find.text('Halaman berikutnya'), findsNothing);
    await tapAndPump(tester, find.text('Selesai membaca panduan'));
    await tester.pumpAndSettle();
    expect(find.text('Buka buku'), findsOneWidget);
  });

  testWidgets('panah kiri dan kanan di keyboard', (tester) async {
    await _openBook(tester, UserRole.teacher);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_heading('Daftar sebagai guru'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_heading('Bergerak dengan TalkBack'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_heading('Daftar sebagai guru'), findsOneWidget);
    // Panah kiri di halaman 1 tidak melakukan apa-apa.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_heading('Daftar isi'), findsOneWidget);
  });

  testWidgets('geser juga bisa, sebagai tambahan tombol', (tester) async {
    await _openBook(tester, UserRole.student);
    await tester.fling(
      find.text('Daftar isi').first,
      const Offset(-400, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(_heading('Membuka APREVO'), findsOneWidget);
  });

  testWidgets('animasi membalik halaman, berhenti kalau animasi dimatikan', (
    tester,
  ) async {
    await _openBook(tester, UserRole.student, animations: true);
    await tapAndPump(tester, find.text('Halaman berikutnya'));
    await tester.pump(const Duration(milliseconds: 100));
    // Selama dibalik, halaman lama dan baru sama-sama tampil.
    expect(
      find.text('Halaman 1 dari ${_pageCount(UserRole.student)}'),
      findsOne,
    );
    expect(find.text('Membuka APREVO'), findsOneWidget);
    await tester.pump(kPageFlipDuration);
    expect(
      find.text('Halaman 1 dari ${_pageCount(UserRole.student)}'),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    await _openBook(tester, UserRole.student);
    await tapAndPump(tester, find.text('Halaman berikutnya'));
    // Tanpa animasi: halaman lama langsung hilang.
    expect(
      find.text('Halaman 1 dari ${_pageCount(UserRole.student)}'),
      findsNothing,
    );
    expect(find.text('Membuka APREVO'), findsOneWidget);
  });

  testWidgets('ilustrasi disembunyikan dari screen reader', (tester) async {
    await _openBook(tester, UserRole.student);
    await tapAndPump(tester, find.text('Halaman berikutnya'));
    await tester.pumpAndSettle();
    final odi = find.byType(Mascot);
    expect(odi, findsOneWidget);
    expect(
      find.ancestor(of: odi, matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
  });

  testWidgets('suara membalik halaman ikut saklar efek bunyi', (tester) async {
    fakeSound.played.clear();
    await _openBook(tester, UserRole.student);
    await tapAndPump(tester, find.text('Halaman berikutnya'));
    await tester.pumpAndSettle();
    expect(fakeSound.played, ['sounds/page.wav']);

    await Settings.setSoundEffects(false);
    addTearDown(() => Settings.setSoundEffects(true));
    await tapAndPump(tester, find.text('Halaman berikutnya'));
    await tester.pumpAndSettle();
    expect(fakeSound.played, ['sounds/page.wav']);
  });

  testWidgets('Profil guru: menu Panduan dan saklar efek bunyi', (
    tester,
  ) async {
    tallScreen(tester);
    _signIn(UserRole.teacher);
    await tester.pumpWidget(testApp(const ProfileTab()));
    await tester.pumpAndSettle();

    // Guru juga bisa mematikan bunyi membalik halaman panduan.
    expect(find.text('Efek bunyi'), findsOneWidget);
    await tapAndPump(tester, find.text('Panduan'));
    await tester.pumpAndSettle();
    expect(find.text('Panduan Guru'), findsOneWidget);
    expect(find.text('Bab 8: Progres siswa'), findsOneWidget);
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

    final toggle = find.widgetWithText(SwitchListTile, 'Efek bunyi');
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
      expect(_heading('Daftar isi'), findsOneWidget);

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
      expect(_heading('Daftar isi'), findsNothing);
      expect(Settings.guideOffered('sari@contoh.id'), isTrue);
    });
  });
}
