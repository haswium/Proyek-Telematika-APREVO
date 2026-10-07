import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/main.dart';
import 'package:aprevo/theme/app_theme.dart';

void main() {
  testWidgets('Splash lalu layar sambutan', (tester) async {
    // Tes tidak boleh mengunduh huruf dari internet.
    AppType.webFonts = false;

    await tester.pumpWidget(const AprevoApp());
    expect(find.text('APREVO'), findsOneWidget);

    // Splash pindah sendiri ke layar sambutan.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Daftar'), findsOneWidget);
  });
}
