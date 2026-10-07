import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palet APREVO hanya empat warna: ungu tua, ungu muda, putih, dan kuning.
/// Tidak ada merah atau hijau. Benar dan salah dibedakan lewat ikon dan
/// kata-kata, bukan warna, jadi tetap jelas untuk siswa buta warna.
class AppColors {
  AppColors._();

  // Ungu tua.
  static const Color ink = Color(0xFF1E0F5C); // teks dan garis tepi
  static const Color bgBottom = Color(0xFF2A1580); // latar, bagian bawah
  static const Color bgTop = Color(0xFF4B28C7); // latar, bagian atas
  static const Color berry = Color(0xFF3A1FA8);
  static const Color primary = Color(0xFF5B34E0); // ungu utama

  // Ungu muda.
  static const Color violet = Color(0xFF8468F5);
  static const Color lilac = Color(0xFFCDBDFF);
  static const Color soft = Color(0xFFF1ECFF);
  static const Color border = Color(0xFFCDBDFF);
  static const Color muted = Color(0xFF5A4E8C);

  // Putih dan kuning.
  static const Color white = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFFFC400);
  static const Color sun = Color(0xFFFFC400);
  static const Color highlight = Color(0xFFFFEB9E);

  // Nama lama, sekarang diarahkan ke palet empat warna di atas.
  static const Color accentEdge = ink;
  static const Color aqua = lilac;
  static const Color mint = soft;
  static const Color pinkSoft = soft;
  static const Color success = ink;
  static const Color successBg = highlight;
  static const Color danger = ink;
  static const Color dangerBg = white;
}

/// Ukuran minimum area sentuh. Lebih besar dari standar 48 supaya mudah
/// ditemukan dengan explore-by-touch TalkBack.
const double kTouchTarget = 56;

/// Gaya teks APREVO. Sengaja TANPA warna: warnanya mengikuti tempat teks
/// itu berada, putih di latar ungu dan ungu tua di dalam kartu putih.
///
/// Hurufnya Poppins dengan dua ketebalan saja: Bold untuk judul dan
/// SemiBold untuk teks isi.
class AppType {
  AppType._();

  static const FontWeight bold = FontWeight.w700;
  static const FontWeight semiBold = FontWeight.w600;

  /// `false` hanya saat widget test, supaya tes tidak mengunduh huruf.
  static bool webFonts = true;

  static TextStyle _display(double size, double height) {
    final style = TextStyle(fontSize: size, fontWeight: bold, height: height);
    return webFonts ? GoogleFonts.poppins(textStyle: style) : style;
  }

  static TextStyle get headlineMedium => _display(28, 1.2);

  static TextStyle get titleLarge => _display(22, 1.25);

  static const TextStyle titleMedium = TextStyle(
    fontSize: 17,
    fontWeight: bold,
    height: 1.3,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 17,
    fontWeight: semiBold,
    height: 1.45,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: semiBold,
    height: 1.45,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: semiBold,
    height: 1.4,
  );
}

/// Garis tepi dan bayangan "stiker": garis ungu tua dan bayangan padat tanpa
/// blur, supaya tombol dan kartu terasa seperti benda yang bisa ditekan.
const BorderSide kStickerSide = BorderSide(color: AppColors.ink, width: 2);

const List<BoxShadow> kStickerShadow = [
  BoxShadow(color: AppColors.ink, offset: Offset(0, 5)),
];

/// Poppins untuk seluruh aplikasi: SemiBold untuk teks, Bold untuk judul.
/// Tiap gaya dibuat lewat `GoogleFonts.poppins(textStyle: ...)` supaya
/// berkas huruf dengan ketebalan yang tepat yang dipakai.
TextTheme _textTheme(TextTheme base) {
  final t = base.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  TextStyle? poppins(TextStyle? s, FontWeight weight) {
    if (s == null) return null;
    final weighted = s.copyWith(fontWeight: weight);
    return AppType.webFonts
        ? GoogleFonts.poppins(textStyle: weighted)
        : weighted;
  }

  TextStyle? semi(TextStyle? s) => poppins(s, AppType.semiBold);
  TextStyle? bold(TextStyle? s) => poppins(s, AppType.bold);

  return t.copyWith(
    displayLarge: bold(t.displayLarge),
    displayMedium: bold(t.displayMedium),
    displaySmall: bold(t.displaySmall),
    headlineLarge: bold(t.headlineLarge),
    headlineMedium: bold(t.headlineMedium),
    headlineSmall: bold(t.headlineSmall),
    titleLarge: bold(t.titleLarge),
    titleMedium: semi(t.titleMedium),
    titleSmall: semi(t.titleSmall),
    bodyLarge: semi(t.bodyLarge),
    bodyMedium: semi(t.bodyMedium),
    bodySmall: semi(t.bodySmall),
    labelLarge: semi(t.labelLarge),
    labelMedium: semi(t.labelMedium),
    labelSmall: semi(t.labelSmall),
  );
}

ThemeData _buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: AppColors.white,
    secondary: AppColors.accent,
    onSecondary: AppColors.ink,
    surface: AppColors.white,
    onSurface: AppColors.ink,
    error: AppColors.ink,
    onError: AppColors.white,
  );

  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(18)),
  );
  const buttonText = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgBottom,
  );

  return base.copyWith(
    textTheme: _textTheme(base.textTheme),
    // Tombol ungu muda: terbaca di latar ungu maupun di kartu putih.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, kTouchTarget),
        shape: buttonShape,
        textStyle: buttonText,
        backgroundColor: AppColors.lilac,
        foregroundColor: AppColors.ink,
        side: kStickerSide,
      ),
    ),
    // Tombol putih bergaris: juga terbaca di kedua latar.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, kTouchTarget),
        shape: buttonShape,
        textStyle: buttonText,
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.ink,
        side: kStickerSide,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.white,
      selectedColor: AppColors.accent,
      disabledColor: AppColors.soft,
      checkmarkColor: AppColors.ink,
      side: kStickerSide,
      labelStyle: const TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        color: AppColors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Tema dibuat sekali saja, lalu dipakai ulang.
final ThemeData _theme = _buildTheme();

ThemeData buildAprevoTheme() => _theme;

/// Tema untuk isi yang langsung berada di latar ungu: tombol teks dan
/// indikator proses menjadi putih.
final ThemeData aprevoOnPurpleTheme = _theme.copyWith(
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.white,
      minimumSize: const Size(0, 48),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: AppColors.white,
  ),
);