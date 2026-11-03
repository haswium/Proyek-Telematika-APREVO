import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../data/app_store.dart';
import '../services/announce.dart';
import '../services/settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';

/// Menu pengembang: mengatur alamat backend. Siswa tidak memerlukannya, jadi
/// hanya terbuka lewat [AboutAprevoRow].
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

enum _Kind { info, busy, success, error }

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final _url = TextEditingController(text: Settings.baseUrl);
  String? _status;
  _Kind _kind = _Kind.info;
  int _serial = 0;

  bool get _busy => _kind == _Kind.busy;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _setStatus(_Kind kind, String message) {
    setState(() {
      _kind = kind;
      _status = message;
      _serial++;
    });
  }

  /// Alamat yang sudah dirapikan, atau `null` (dengan pesan error).
  String? _cleanUrl() {
    final url = ApiConfig.normalize(_url.text);
    if (url == null) {
      _setStatus(
        _Kind.error,
        'Alamat server belum benar. Contoh: https://aprevo.onrender.com atau '
        '192.168.1.7',
      );
    }
    return url;
  }

  Future<void> _check() async {
    final url = _cleanUrl();
    if (url == null) return;
    _setStatus(_Kind.busy, 'Memeriksa sambungan ke $url.');
    final error = await store.api.ping(url);
    if (!mounted) return;
    if (error == null) {
      _setStatus(_Kind.success, 'Tersambung ke server $url.');
    } else {
      _setStatus(_Kind.error, error);
    }
  }

  Future<void> _save() async {
    final url = _cleanUrl();
    if (url == null) return;
    await Settings.setBaseUrl(url == ApiConfig.defaultBaseUrl ? null : url);
    if (!mounted) return;
    _url.text = url;
    _setStatus(_Kind.success, 'Alamat server disimpan: $url.');
  }

  Future<void> _reset() async {
    await Settings.setBaseUrl(null);
    if (!mounted) return;
    _url.text = Settings.baseUrl;
    _setStatus(_Kind.success, 'Kembali ke alamat bawaan: ${Settings.baseUrl}.');
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Menu pengembang'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Alamat backend APREVO. APK release hanya bisa memakai alamat '
              'https. Alamat http, misalnya IP laptop, hanya jalan di build '
              'debug.',
              style: AppType.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              style: AppType.bodyLarge,
              decoration: fieldDecoration(
                'Alamat server',
                hint: 'Contoh: https://aprevo.onrender.com',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            if (_status != null) ...[_statusCard(), const SizedBox(height: 12)],
            PrimaryButton(
              label: 'Simpan alamat',
              icon: Icons.save_outlined,
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.wifi_find),
              label: Text(_busy ? 'Sedang memeriksa...' : 'Cek sambungan'),
              onPressed: _busy ? null : _check,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Pakai alamat bawaan'),
              onPressed: _busy ? null : _reset,
            ),
            const SizedBox(height: 16),
            Text(
              'Di laptop, jalankan backend dengan: uvicorn main:app --host '
              '0.0.0.0 --port 8000',
              style: AppType.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final key = ValueKey('server-status-$_serial');
    if (_kind == _Kind.error) return ErrorCard(key: key, message: _status!);
    return Semantics(
      key: key,
      container: true,
      liveRegion: true,
      label: _status,
      excludeSemantics: true,
      child: AppCard(
        color: _kind == _Kind.success ? AppColors.highlight : AppColors.white,
        child: Row(
          children: [
            Icon(switch (_kind) {
              _Kind.busy => Icons.hourglass_top,
              _Kind.success => Icons.check_circle,
              _ => Icons.info_outline,
            }, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(_status!, style: AppType.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// Ketukan pada [AboutAprevoRow] yang membuka menu pengembang.
const int kDeveloperMenuTaps = 7;

/// Baris "Tentang APREVO" di layar Masuk dan tab Profil. Mengetuknya
/// [kDeveloperMenuTaps] kali berturut-turut membuka menu pengembang.
class AboutAprevoRow extends StatefulWidget {
  const AboutAprevoRow({super.key});

  @override
  State<AboutAprevoRow> createState() => _AboutAprevoRowState();
}

class _AboutAprevoRowState extends State<AboutAprevoRow> {
  static const String _about = 'APREVO, aplikasi belajar untuk siswa tunanetra.';

  /// Lebih longgar dari biasanya, karena TalkBack memakai ketukan dua kali.
  static const Duration _maxGap = Duration(seconds: 5);

  int _taps = 0;
  DateTime? _lastTap;

  void _tapped() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last == null || now.difference(last) > _maxGap) _taps = 0;
    _lastTap = now;
    _taps++;
    final left = kDeveloperMenuTaps - _taps;
    if (left > 0) {
      announce(
        left > 3
            ? _about
            : 'Ketuk $left kali lagi untuk membuka menu pengembang',
      );
      return;
    }
    _taps = 0;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServerSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => ListRow(
    icon: Icons.info_outline,
    title: 'Tentang APREVO',
    onTap: _tapped,
  );
}
