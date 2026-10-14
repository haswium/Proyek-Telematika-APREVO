import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'playful.dart';

AppBar aprevoAppBar(
  String title, {
  PreferredSizeWidget? bottom,
  List<Widget>? actions,
}) {
  return AppBar(
    actions: actions,
    title: Text(
      title,
      style: AppType.titleLarge.copyWith(color: AppColors.white),
    ),
    // Sewarna dengan bagian atas latar, jadi menyatu dengan halaman.
    backgroundColor: AppColors.bgTop,
    foregroundColor: AppColors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    bottom: bottom,
  );
}

IconData gameIcon(GameType type) {
  switch (type) {
    case GameType.quiz:
      return Icons.quiz_outlined;
    case GameType.trueFalse:
      return Icons.rule;
    case GameType.shortAnswer:
      return Icons.edit_note;
    case GameType.ordering:
      return Icons.swap_vert;
  }
}

/// Kode akses dieja per huruf untuk TalkBack, supaya "KXPRTA" tidak
/// dibaca sebagai satu kata: "K X P R T A".
String spellCode(String code) =>
    code.replaceAll('-', '').split('').join(' ');

/// Kolom kode akses: huruf kecil otomatis jadi kapital, karakter selain
/// huruf A-Z dibuang, dan panjangnya paling banyak [kAccessCodeLength].
class AccessCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = cleanAccessCode(newValue.text);
    if (text.length > kAccessCodeLength) {
      text = text.substring(0, kAccessCodeLength);
    }
    // Kursor tetap di posisi yang sama relatif terhadap huruf di depannya.
    final end = newValue.selection.end;
    var offset = end < 0 || end > newValue.text.length
        ? text.length
        : cleanAccessCode(newValue.text.substring(0, end)).length;
    if (offset > text.length) offset = text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

InputDecoration fieldDecoration(String label, {String? hint}) {
  const radius = BorderRadius.all(Radius.circular(16));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: AppColors.white,
    labelStyle: const TextStyle(color: AppColors.muted),
    // Label yang naik ke garis tepi diberi latar kuning supaya tetap
    // terbaca di latar ungu.
    floatingLabelStyle: const TextStyle(
      color: AppColors.ink,
      fontWeight: FontWeight.w700,
      backgroundColor: AppColors.highlight,
    ),
    border: const OutlineInputBorder(borderRadius: radius),
    enabledBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: kStickerSide,
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: AppColors.accent, width: 3.5),
    ),
  );
}

/// Tombol kuning: aksi utama di setiap layar. Bergaya stiker, dengan
/// bayangan padat di bawahnya yang hilang saat tombol tidak aktif.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final style = FilledButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.ink,
      disabledBackgroundColor: AppColors.soft,
      disabledForegroundColor: AppColors.muted,
      side: kStickerSide,
    );
    return Bouncy(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled ? kStickerShadow : null,
        ),
        child: icon == null
            ? FilledButton(
                onPressed: onPressed,
                style: style,
                child: Text(label),
              )
            : FilledButton.icon(
                onPressed: onPressed,
                style: style,
                icon: Icon(icon),
                label: Text(label),
              ),
      ),
    );
  }
}

/// Kartu bergaya stiker. Warna teks di dalamnya menyesuaikan sendiri:
/// ungu tua di kartu terang, putih di kartu gelap.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.color = AppColors.white,
    this.borderColor = AppColors.ink,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = color.computeLuminance() < 0.4;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.ink, width: 2),
        boxShadow: kStickerShadow,
      ),
      child: Theme(
        data: dark ? aprevoOnPurpleTheme : buildAprevoTheme(),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: dark ? AppColors.white : AppColors.ink),
          child: child,
        ),
      ),
    );
  }
}

/// Baris daftar yang dibaca TalkBack sebagai SATU tombol dengan satu label,
/// bukan potongan teks terpisah.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.semanticLabel,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel ??
        (subtitle == null ? title : '$title. $subtitle');

    // Warna kotak ikon bergantian supaya daftar terasa ceria. Tetap sama
    // untuk judul yang sama.
    const tiles = [AppColors.lilac, AppColors.highlight, AppColors.soft];
    final tile = tiles[title.codeUnits.fold<int>(0, (a, b) => a + b) %
        tiles.length];

    final content = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: tile,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.ink, width: 1.5),
          ),
          child: Icon(icon, color: AppColors.ink),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.titleMedium),
              if (subtitle != null) Text(subtitle!, style: AppType.bodySmall),
            ],
          ),
        ),
        if (onTap != null && trailing == null)
          const Icon(Icons.chevron_right, color: AppColors.primary),
      ],
    );

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: kStickerSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: label,
                button: onTap != null,
                onTap: onTap,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: trailing,
              ),
          ],
        ),
      ),
    );
    return onTap == null ? row : Bouncy(child: row);
  }
}

/// Kartu pesan error. liveRegion: TalkBack langsung membacakannya.
///
/// TalkBack hanya membacakan liveRegion kalau labelnya berubah. Supaya
/// pesan yang sama tetap dibacakan saat muncul lagi, beri `key` baru tiap
/// kali pesan ditampilkan (lihat [ErrorCard.keyFor]).
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message});

  final String message;

  /// Key unik untuk kemunculan ke-[serial] sebuah pesan.
  static Key keyFor(int serial) => ValueKey('error-$serial');

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
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

/// ChoiceChip setinggi [kTouchTarget]. Chip bawaan hanya 48; yang
/// menambah tingginya adalah `labelPadding` vertikal (sudah diukur di tes).
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      avatar: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppType.bodyMedium,
      ),
    );
  }
}

/// Judul bagian. `header: true` membuat siswa bisa lompat antarjudul
/// dengan navigasi "Judul" di TalkBack.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Semantics(
        header: true,
        child: Text(text, style: AppType.titleLarge),
      ),
    );
  }
}

/// Bagian kepala layar. Tanpa kotak: isinya langsung di latar ungu,
/// dengan teks putih atau kuning.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.white),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Label kecil berbentuk pil: jenis soal, status, kode.
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.icon,
    this.color = AppColors.lilac,
    this.textColor = AppColors.primary,
  });

  final String text;
  final IconData? icon;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: Icon(icon, size: 15, color: textColor)),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kotak angka ringkas, misalnya "32 Siswa". Dibaca sebagai satu frasa
/// dengan nama di depan: "Siswa: 32", "Nilai pre-test: Belum ada".
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kode akses dengan tombol Salin. Kodenya dieja per karakter untuk TalkBack
/// supaya tidak dibaca sebagai satu kata.
class CodeBox extends StatelessWidget {
  const CodeBox({super.key, required this.code, this.onDark = false});

  final String code;

  /// `true` kalau dipakai di dalam [HeroCard] (latar ungu).
  final bool onDark;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Kode akses disalin.')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: onDark ? const Color(0x33FFFFFF) : AppColors.soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.key,
              size: 20,
              color: onDark ? AppColors.accent : AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              label: 'Kode akses: ${spellCode(code)}',
              excludeSemantics: true,
              child: Text(
                code,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: onDark ? AppColors.white : AppColors.primary,
                ),
              ),
            ),
          ),
          Semantics(
            label: 'Salin kode akses',
            button: true,
            onTap: () => _copy(context),
            excludeSemantics: true,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.ink,
                minimumSize: const Size(0, kTouchTarget),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Salin'),
              onPressed: () => _copy(context),
            ),
          ),
        ],
      ),
    );
  }
}
