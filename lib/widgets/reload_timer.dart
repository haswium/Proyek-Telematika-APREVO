import 'dart:async';

import 'package:flutter/widgets.dart';

/// Memanggil [reload] setelah [after] lewat, misalnya saat sesi presensi
/// dibuka atau ditutup menurut jam server. Jam HP tidak dibaca: [after]
/// berasal dari backend. Timer diatur ulang setiap [after] berubah.
class ReloadTimer extends StatefulWidget {
  const ReloadTimer({
    super.key,
    required this.after,
    required this.reload,
    required this.child,
  });

  final Duration? after;
  final VoidCallback reload;
  final Widget child;

  @override
  State<ReloadTimer> createState() => _ReloadTimerState();
}

class _ReloadTimerState extends State<ReloadTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ReloadTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.after != widget.after) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final after = widget.after;
    if (after == null) return;
    // Satu detik lebih supaya server sudah melewati batasnya.
    _timer = Timer(after + const Duration(seconds: 1), () {
      if (mounted) widget.reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
