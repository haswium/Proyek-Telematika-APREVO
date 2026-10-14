import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/screens/login_screen.dart';
import 'package:aprevo/screens/register_screen.dart';
import 'package:aprevo/theme/app_theme.dart';
import 'package:aprevo/widgets/common.dart';

/// Sama seperti AprevoApp: tema dan bahasa Indonesia.
Widget _app(Widget home) => MaterialApp(
  theme: buildAprevoTheme(),
  locale: const Locale('id', 'ID'),
  supportedLocales: const [Locale('id', 'ID')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: home,
);

/// Aturan APREVO: area sentuh minimal kTouchTarget (56), lebih besar dari
/// pedoman Android (48), jadi dicek sendiri.
void _expectTouchTarget(WidgetTester tester, Finder finder) {
  for (final element in finder.evaluate()) {
    final size = element.size!;
    expect(
      size.height >= kTouchTarget,
      isTrue,
      reason: '${element.widget.runtimeType} hanya ${size.height} tinggi',
    );
  }
}

void main() {
  testWidgets('chip, tombol teks, dan tombol ikon minimal 56', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ListView(
            children: [
              Wrap(
                children: [
                  AppChoiceChip(
                    label: 'Benar',
                    selected: true,
                    onSelected: (_) {},
                  ),
                  AppChoiceChip(
                    icon: Icons.quiz_outlined,
                    label: 'Quiz',
                    selected: false,
                    onSelected: (_) {},
                  ),
                ],
              ),
              TextButton(onPressed: () {}, child: const Text('Lupa password?')),
              IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
              const CodeBox(code: 'KXPRTA'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectTouchTarget(tester, find.byType(ChoiceChip));
    _expectTouchTarget(tester, find.byType(TextButton));
    _expectTouchTarget(tester, find.byType(IconButton));
    _expectTouchTarget(tester, find.byType(FilledButton));
  });

  testWidgets('kode akses dieja dan tombol salin berlabel jelas', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(const Scaffold(body: CodeBox(code: 'KXPRTA'))),
    );
    expect(find.bySemanticsLabel('Kode akses: K X P R T A'), findsOneWidget);
    expect(find.bySemanticsLabel('Salin kode akses'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('pesan error adalah liveRegion dengan labelnya sendiri', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(const Scaffold(body: ErrorCard(message: 'Password salah.'))),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Password salah.')),
      matchesSemantics(label: 'Password salah.', isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('pilihan peran menyebut konteksnya', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const RegisterScreen()));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Daftar sebagai Siswa')),
      matchesSemantics(
        label: 'Daftar sebagai Siswa',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  for (final (name, screen) in [
    ('Masuk', const LoginScreen()),
    ('Daftar', const RegisterScreen()),
  ]) {
    testWidgets(
      'layar $name: semua tombol berlabel, tombol kembali "Kembali"',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => screen),
                    ),
                    child: const Text('buka'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('buka'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(find.byTooltip('Kembali'), findsOneWidget);
        handle.dispose();
      },
    );
  }
}
