import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../services/announce.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

const String kConnectingMessage = 'Menghubungkan ke server, mohon tunggu';
const String kConnectedMessage = 'Server tersambung';

/// Spanduk di atas semua layar selama server sedang bangun. Server gratis tidur
/// kalau lama tidak dipakai, dan butuh sekitar satu menit untuk bangun.
///
/// Dipasang di `MaterialApp.builder`, jadi posisi [child] harus tetap saat
/// spanduk muncul, supaya isi layar yang terbuka tidak dibangun ulang.
class ConnectingBanner extends StatefulWidget {
  const ConnectingBanner({super.key, required this.child, this.api});

  final Widget child;

  /// Bawaan: `store.api`.
  final ApiClient? api;

  @override
  State<ConnectingBanner> createState() => _ConnectingBannerState();
}

class _ConnectingBannerState extends State<ConnectingBanner> {
  late final ApiClient _api = widget.api ?? store.api;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _shown = _api.connecting.value;
    _api.connecting.addListener(_changed);
  }

  @override
  void dispose() {
    _api.connecting.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final shown = _api.connecting.value;
    if (shown == _shown) return;
    // Kalau gagal, pesan errornya yang dibacakan layar yang menunggu.
    if (!shown && _api.reachable) announce(kConnectedMessage);
    setState(() => _shown = shown);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_shown)
          Semantics(
            container: true,
            liveRegion: true,
            child: Material(
              color: AppColors.highlight,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const ExcludeSemantics(
                        child: Icon(Icons.hourglass_top, color: AppColors.ink),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          kConnectingMessage,
                          style: AppType.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        Expanded(
          child: MediaQuery(
            data: _shown ? media.removePadding(removeTop: true) : media,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
