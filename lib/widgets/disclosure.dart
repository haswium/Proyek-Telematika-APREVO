import 'package:flutter/material.dart';

import '../services/announce.dart';
import '../theme/app_theme.dart';

/// Bagian yang bisa dibuka dan ditutup. Semua elemen buka-tutup di APREVO
/// memakai widget ini, supaya TalkBack dan NVDA selalu:
///
/// * membaca satu label utuh dengan statusnya, misalnya "Halaman 2: Iklim,
///   tertutup. 3 paragraf", lalu "tombol",
/// * mendapat status `expanded` di semantics,
/// * mendengar "Halaman 2: Iklim dibuka" atau "... ditutup" saat ditekan,
/// * menemukan isi yang baru muncul tepat setelah tombolnya (satu geser ke
///   kanan), bukan di tempat lain di layar.
///
/// Isi yang tertutup tidak dibangun sama sekali, jadi tidak terbaca.
class Disclosure extends StatefulWidget {
  const Disclosure({
    super.key,
    required this.title,
    required this.child,
    this.summary,
    this.initiallyOpen = false,
    this.onChanged,
  });

  final String title;

  /// Keterangan singkat yang ikut dibaca, misalnya "3 paragraf".
  final String? summary;
  final Widget child;
  final bool initiallyOpen;
  final ValueChanged<bool>? onChanged;

  @override
  State<Disclosure> createState() => _DisclosureState();
}

/// "terbuka" atau "tertutup", dipakai label dan tes.
String disclosureState(bool open) => open ? 'terbuka' : 'tertutup';

class _DisclosureState extends State<Disclosure> {
  late bool _open = widget.initiallyOpen;

  void _toggle() {
    setState(() => _open = !_open);
    announce('${widget.title} ${_open ? 'dibuka' : 'ditutup'}');
    widget.onChanged?.call(_open);
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final label = [
      '${widget.title}, ${disclosureState(_open)}',
      ?summary,
    ].join('. ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          expanded: _open,
          label: label,
          hint: _open
              ? 'Ketuk dua kali untuk menutup'
              : 'Ketuk dua kali untuk membuka',
          onTap: _toggle,
          excludeSemantics: true,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kTouchTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: AppType.titleMedium),
                          if (summary != null)
                            Text(summary, style: AppType.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          // explicitChildNodes: tiap paragraf di dalamnya satu fokus sendiri,
          // tidak digabung menjadi satu blok panjang.
          Semantics(
            container: true,
            explicitChildNodes: true,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, top: 4, bottom: 8),
              child: widget.child,
            ),
          ),
      ],
    );
  }
}
