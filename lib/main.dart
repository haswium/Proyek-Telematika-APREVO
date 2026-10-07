import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
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
      home: const SplashScreen(),
    );
  }
}
