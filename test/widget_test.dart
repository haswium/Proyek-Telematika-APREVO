import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/main.dart';

void main() {
  testWidgets('Splash lalu layar sambutan', (tester) async {
    // Mode demo: Supabase tidak diinisialisasi, jadi tes tidak butuh internet.
    expect(store.online, isFalse);

    await tester.pumpWidget(const AprevoApp());
    expect(find.text('APREVO'), findsOneWidget);

    // Splash pindah sendiri ke layar sambutan.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Daftar'), findsOneWidget);
  });
}
