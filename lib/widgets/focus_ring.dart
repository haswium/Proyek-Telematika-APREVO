import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

/// Cincin kuning di sekeliling elemen yang sedang difokus, hanya saat
/// aplikasi dipakai dengan keyboard (Tab di browser laptop). Fokus bawaan
/// Material hampir tidak terlihat di latar ungu dan kartu putih.
///
/// Saat dipakai dengan sentuhan (HP), cincin tidak muncul. Cincin hanya
/// gambar: disembunyikan dari screen reader dan tidak menangkap ketukan.
/// Dipasang sekali di `MaterialApp.builder`.
class KeyboardFocusRing extends StatefulWidget {
  const KeyboardFocusRing({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardFocusRing> createState() => _KeyboardFocusRingState();
}

class _KeyboardFocusRingState extends State<KeyboardFocusRing> {
  final _area = GlobalKey();
  Rect? _ring;
  bool _checkScheduled = false;

  FocusManager get _focus => FocusManager.instance;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_scheduleCheck);
    _focus.addHighlightModeListener(_onHighlightMode);
    // Elemen yang difokus bisa bergeser tanpa fokus berpindah (digulir,
    // layar berganti). Posisinya diperiksa setelah setiap frame.
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    _focus.removeListener(_scheduleCheck);
    _focus.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode _) => _scheduleCheck();

  // Tidak meminta frame baru: hanya memeriksa di akhir frame yang memang
  // sedang digambar, supaya tidak terjadi gambar ulang tanpa henti.
  void _onFrame(Duration _) {
    if (mounted && (_ring != null || _keyboard)) {
      _scheduleCheck(requestFrame: false);
    }
  }

  bool get _keyboard => _focus.highlightMode == FocusHighlightMode.traditional;

  void _scheduleCheck({bool requestFrame = true}) {
    if (_checkScheduled || !mounted) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final ring = _currentRing();
      if (ring != _ring) setState(() => _ring = ring);
    });
    if (requestFrame) SchedulerBinding.instance.ensureVisualUpdate();
  }

  Rect? _currentRing() {
    if (!_keyboard) return null;
    final node = _focus.primaryFocus;
    final box = _area.currentContext?.findRenderObject() as RenderBox?;
    if (node == null || node is FocusScopeNode || box == null) return null;
    if (node.context == null || !box.hasSize) return null;
    final rect = node.rect.shift(-box.localToGlobal(Offset.zero));
    // Node selebar layar (misalnya seluruh halaman) tidak diberi cincin.
    if (rect.isEmpty ||
        rect.width >= box.size.width - 1 &&
            rect.height >= box.size.height - 1) {
      return null;
    }
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final ring = _ring;
    return Stack(
      key: _area,
      children: [
        widget.child,
        if (ring != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(
                  key: const ValueKey('cincin-fokus'),
                  painter: _RingPainter(ring),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    // Kuning tebal di luar, garis ungu tua di dalam, supaya tetap terlihat di
    // latar ungu, kartu putih, maupun tombol kuning.
    final outer = RRect.fromRectAndRadius(
      rect.inflate(4),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = AppColors.accent,
    );
    canvas.drawRRect(
      outer.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.rect != rect;
}
