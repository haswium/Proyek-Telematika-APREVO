// Versi web dipakai guru di laptop: semua tombol harus bisa dicapai dengan
// Tab, dipilih dengan Enter, dan fokusnya terlihat.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/screens/register_screen.dart';
import 'package:aprevo/theme/app_theme.dart';
import 'package:aprevo/widgets/focus_ring.dart';

import 'fake_server.dart';

final _ring = find.byKey(const ValueKey('cincin-fokus'));

Widget _ringApp(Widget home) => MaterialApp(
  theme: buildAprevoTheme(),
  builder: (context, child) => KeyboardFocusRing(child: child!),
  home: home,
);

/// Menekan Tab sampai fokus berada di dalam [target].
Future<bool> _tabTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 20; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        find
            .descendant(of: target, matching: find.byWidget(focused.widget))
            .evaluate()
            .isNotEmpty) {
      return true;
    }
  }
  return false;
}

void main() {
  testWidgets('cincin fokus hanya muncul saat memakai keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ringApp(
        Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Simpan'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Disentuh: tidak ada cincin.
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump();
    expect(_ring, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(_ring, findsOneWidget);

    // Cincin mengelilingi tombol yang difokus dan tidak dibaca screen reader.
    final button = tester.getRect(find.byType(ElevatedButton));
    final Rect ring =
        (tester.widget<CustomPaint>(_ring).painter! as dynamic).rect;
    expect(ring.isEmpty, isFalse);
    expect(button.inflate(1).contains(ring.topLeft), isTrue);
    expect(button.inflate(1).contains(ring.bottomRight), isTrue);
    expect(
      find.ancestor(of: _ring, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    expect(
      find.ancestor(of: _ring, matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
  });

  testWidgets(
    'pilihan peran di layar daftar bisa dipilih dengan Tab dan Enter',
    (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(testApp(const RegisterScreen()));
      await tester.pumpAndSettle();

      final teacher = find.bySemanticsLabel('Daftar sebagai Guru');
      expect(await _tabTo(tester, teacher), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(teacher),
        isSemantics(label: 'Daftar sebagai Guru', isSelected: true),
      );
    },
  );
}
