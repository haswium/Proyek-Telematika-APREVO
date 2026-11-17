import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/app_store.dart';
import 'screens/splash_screen.dart';
import 'services/settings.dart';
import 'theme/app_theme.dart';
import 'widgets/connecting_banner.dart';
import 'widgets/focus_ring.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Di web, Flutter baru membuat pohon aksesibilitas setelah tombol tersembunyi
  // "Enable accessibility" ditekan. Dinyalakan sejak awal supaya screen reader
  // (NVDA, TalkBack di Chrome) langsung membaca semua label.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  // Alamat server dan status layar sambutan yang tersimpan di perangkat.
  await Settings.load();
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    store.online = true;
  }
  runApp(const AprevoApp());
  store.api.wakeUp();
}

class AprevoApp extends StatelessWidget {
  const AprevoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APREVO',
      debugShowCheckedModeBanner: false,
      theme: buildAprevoTheme(),
      // Bahasa Indonesia untuk teks bawaan Flutter yang dibaca TalkBack,
      // misalnya tombol kembali ("Kembali", bukan "Back").
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          KeyboardFocusRing(child: ConnectingBanner(child: child!)),
      home: const SplashScreen(),
    );
  }
}
