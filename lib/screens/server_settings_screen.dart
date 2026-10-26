import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../data/app_store.dart';
import '../services/settings.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';

/// Mengatur alamat backend. Dari HP, isi IP laptop yang menjalankan
/// backend, misalnya 192.168.1.7. Port 8000 ditambahkan sendiri.
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
    Speech.feedback(context, message);
  }

  /// Alamat yang sudah dirapikan, atau `null` (dengan pesan error).
  String? _cleanUrl() {
    final url = ApiConfig.normalize(_url.text);
    if (url == null) {
      _setStatus(
        _Kind.error,
        'Alamat server belum benar. Contoh: 192.168.1.7 atau '
        'http://192.168.1.7:8000',
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
      appBar: aprevoAppBar('Alamat server'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Alamat backend APREVO. Kalau memakai HP, isi alamat IP '
              'laptop yang menjalankan backend, misalnya 192.168.1.7. HP '
              'dan laptop harus memakai Wi-Fi yang sama.',
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
                hint: 'Contoh: 192.168.1.7',
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

/// Baris "Alamat server" untuk layar Masuk dan tab Profil.
class ServerAddressRow extends StatelessWidget {
  const ServerAddressRow({super.key});

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) => ListRow(
        icon: Icons.dns_outlined,
        title: 'Alamat server',
        subtitle: Settings.baseUrl,
        semanticLabel: 'Alamat server: ${Settings.baseUrl}. Ketuk untuk ubah',
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ServerSettingsScreen()),
          );
          // Tampilkan alamat terbaru setelah kembali.
          setState(() {});
        },
      ),
    );
  }
}
