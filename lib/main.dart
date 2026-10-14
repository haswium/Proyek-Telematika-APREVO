import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/app_store.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    store.online = true;
  }
  runApp(const AprevoApp());
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
      home: const SplashScreen(),
    );
  }
}
