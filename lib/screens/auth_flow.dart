import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'student/student_shell.dart';
import 'student/onboarding_screen.dart';
import 'teacher/teacher_shell.dart';
import 'welcome_screen.dart';

/// Setelah masuk atau daftar: buka beranda sesuai peran akun, dan hapus
/// layar-layar sebelumnya supaya tombol kembali tidak balik ke form masuk.
void goHome(BuildContext context, Account account) {
  final Widget home;
  if (account.role == UserRole.teacher) {
    home = const TeacherShell();
  } else if (store.needsOnboarding(account)) {
    home = OnboardingScreen(studentName: account.name);
  } else {
    home = StudentShell(studentName: account.name);
  }
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => home),
    (route) => false,
  );
}

/// Keluar dari akun dan kembali ke layar sambutan.
void logout(BuildContext context) {
  store.signOut();
  Speech.stop();
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    (route) => false,
  );
}

/// Kepala form masuk/daftar: dua baris judul seperti di Figma.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: AppColors.white,
    );
    return Semantics(
      header: true,
      label: '$title ke APREVO',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: style),
          Text('ke APREVO', style: style.copyWith(color: AppColors.accent)),
        ],
      ),
    );
  }
}

/// Kolom isian dengan label huruf besar di atasnya, seperti di Figma.
/// Label dibacakan TalkBack sebagai nama kolomnya.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.suffixIcon,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(14));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            autocorrect: false,
            enableSuggestions: !obscureText,
            style: AppType.bodyLarge,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.muted),
              suffixIcon: suffixIcon,
              filled: true,
              fillColor: AppColors.white,
              border: const OutlineInputBorder(borderRadius: radius),
              enabledBorder: const OutlineInputBorder(
                borderRadius: radius,
                borderSide: kStickerSide,
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: AppColors.accent, width: 3.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tombol tampilkan/sembunyikan password.
class PasswordToggle extends StatelessWidget {
  const PasswordToggle({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: visible ? 'Sembunyikan password' : 'Tampilkan password',
      constraints: const BoxConstraints(
        minWidth: kTouchTarget,
        minHeight: kTouchTarget,
      ),
      color: AppColors.primary,
      icon: Icon(visible ? Icons.visibility_off : Icons.visibility_outlined),
      onPressed: onPressed,
    );
  }
}

/// Kartu pesan error. liveRegion: TalkBack langsung membacakannya.
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: AppCard(
        color: AppColors.dangerBg,
        borderColor: AppColors.danger,
        child: Text(
          message,
          style: AppType.bodyMedium.copyWith(color: AppColors.danger),
        ),
      ),
    );
  }
}

/// App bar putih polos dengan tombol kembali, untuk layar masuk/daftar.
AppBar plainAppBar() {
  return AppBar(
    backgroundColor: AppColors.bgTop,
    foregroundColor: AppColors.white,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
  );
}
