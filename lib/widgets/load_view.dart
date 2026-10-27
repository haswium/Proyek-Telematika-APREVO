import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../services/announce.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Memuat data dari backend dengan pesan yang dibacakan screen reader.
///
/// * Saat memuat: [loadingMessage] tampil dan diumumkan ke TalkBack.
/// * Kalau gagal: pesan error di [ErrorCard] (liveRegion) dan tombol
///   "Coba lagi". Kalau TalkBack mati, pesannya dibacakan dengan suara.
/// * Kalau [listenToStore] `true`, data dimuat ulang diam-diam setiap
///   [store] berubah (misalnya setelah siswa mengumpulkan kuis), sambil
///   tetap menampilkan data lama.
class LoadView<T> extends StatefulWidget {
  const LoadView({
    super.key,
    required this.load,
    required this.loadingMessage,
    required this.builder,
    this.initialData,
    this.listenToStore = true,
    this.scrollable = true,
    this.padding = const EdgeInsets.all(20),
  });

  final Future<T> Function() load;
  final String loadingMessage;
  final Widget Function(BuildContext context, T data, VoidCallback reload)
  builder;

  /// Data yang sudah ada (misalnya dari layar sebelumnya), supaya layar
  /// langsung tampil. Data terbaru tetap dimuat di belakang.
  final T? initialData;
  final bool listenToStore;

  /// `false` kalau LoadView berada di dalam daftar yang sudah bisa
  /// digulir: pesan memuat dan error lalu tampil sebagai Column biasa.
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> {
  T? _data;
  bool _hasData = false;
  bool _loading = false;

  /// Store berubah saat sedang memuat: muat sekali lagi setelahnya.
  bool _again = false;
  String? _error;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _data = widget.initialData;
      _hasData = true;
    }
    if (widget.listenToStore) store.addListener(_onStoreChanged);
    _load(announceLoading: !_hasData);
  }

  @override
  void dispose() {
    if (widget.listenToStore) store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() => _load(announceLoading: false);

  Future<void> _load({bool announceLoading = true}) async {
    if (_loading) {
      _again = true;
      return;
    }
    final serial = ++_serial;
    setState(() {
      _loading = true;
      if (!_hasData) _error = null;
    });
    if (announceLoading && !_hasData) {
      // Diumumkan setelah frame ini supaya tidak tertimpa pembacaan judul
      // halaman oleh TalkBack.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loading && serial == _serial) {
          announce(widget.loadingMessage);
        }
      });
    }
    try {
      final data = await widget.load();
      if (!mounted || serial != _serial) return;
      setState(() {
        _data = data;
        _hasData = true;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || serial != _serial) return;
      final message = e.toString();
      setState(() {
        _error = message;
        _loading = false;
      });
    }
    if (_again && mounted) {
      _again = false;
      _load(announceLoading: false);
    }
  }

  void _retry() {
    setState(() {
      // Data lama dibuang supaya pesan memuat tampil lagi dan dibacakan.
      _hasData = false;
      _data = null;
    });
    _load();
  }

  Widget _wrap(List<Widget> children) {
    if (widget.scrollable) {
      return ListView(padding: widget.padding, children: children);
    }
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _wrap([
        ErrorCard(key: ErrorCard.keyFor(_serial), message: _error!),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Coba lagi',
          icon: Icons.refresh,
          onPressed: _loading ? null : _retry,
        ),
      ]);
    }
    if (!_hasData) {
      return _wrap([LoadingMessage(message: widget.loadingMessage)]);
    }
    return widget.builder(
      context,
      _data as T,
      () => _load(announceLoading: false),
    );
  }
}

/// Pesan "sedang memuat" dengan indikator yang berhenti berputar kalau
/// animasi dimatikan. Ikon dan indikator disembunyikan dari screen reader.
///
/// Bukan liveRegion: [LoadView] sudah mengumumkannya, jadi tidak dibaca
/// dua kali.
class LoadingMessage extends StatelessWidget {
  const LoadingMessage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Semantics(
      container: true,
      label: message,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: still
                  ? const Icon(Icons.hourglass_top, color: AppColors.white)
                  : const CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
