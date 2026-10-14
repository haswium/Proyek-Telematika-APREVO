import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Semua animasi di APREVO hanya hiasan. Kalau pengguna mematikan animasi di
/// pengaturan aksesibilitas HP ("Hapus animasi"), semuanya ikut berhenti.
bool reduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

/// Animasi berulang. [builder] menerima nilai `t` dari 0 sampai 1.
class Loop extends StatefulWidget {
  const Loop({
    super.key,
    required this.builder,
    this.duration = const Duration(seconds: 3),
  });

  final Duration duration;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<Loop> createState() => _LoopState();
}

class _LoopState extends State<Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _controller.value),
    );
  }
}

/// Muncul sambil naik sedikit. Dipakai untuk kartu dan baris daftar.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  static const int _moveMs = 420;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delay.inMilliseconds + _moveMs),
  );

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMilliseconds / (widget.delay.inMilliseconds + _moveMs),
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        // Tetap terbaca screen reader walau masih transparan.
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - _animation.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Mengecil sedikit saat ditekan, seperti tombol empuk.
class Bouncy extends StatefulWidget {
  const Bouncy({super.key, required this.child});

  final Widget child;

  @override
  State<Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<Bouncy> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !reduceMotion(context) ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Latar ungu bergradasi dengan gelembung lembut yang naik.
/// Gelembungnya hiasan, jadi disembunyikan dari screen reader.
class OceanBackground extends StatelessWidget {
  const OceanBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.ink,
                  AppColors.primary,
                  AppColors.violet,
                  AppColors.berry,
                ],
                stops: [0, 0.38, 0.75, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Loop(
                duration: const Duration(seconds: 14),
                builder: (context, t) => CustomPaint(
                  painter: _BubblePainter(t),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.t);

  final double t;

  static const List<Color> _colors = [
    Color(0x44FFFFFF), // putih
    Color(0x55FFC400), // kuning
    Color(0x447C5CF0), // ungu terang
    Color(0x33FFF1B8), // kuning lembut
  ];

  double _frac(double v) => v - v.floorToDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Dua bentuk karang lembut di sudut.
    paint.color = const Color(0x22FFFFFF);
    canvas.drawCircle(
      Offset(size.width * 0.95, size.height * 0.12),
      size.width * 0.32,
      paint,
    );
    paint.color = const Color(0x22FFC400);
    canvas.drawCircle(
      Offset(size.width * 0.02, size.height * 0.62),
      size.width * 0.26,
      paint,
    );

    for (var i = 0; i < 16; i++) {
      final phase = _frac(i * 0.618034);
      final speed = 1 + i % 3; // bilangan bulat supaya putarannya mulus
      final progress = _frac(t * speed + phase);
      final radius = 6.0 + (i * 37 % 22);
      final wobble = math.sin((progress + phase) * 2 * math.pi) * 10;
      final x = _frac(i * 0.381966 + 0.07) * size.width + wobble;
      final y = size.height + radius - progress * (size.height + radius * 2);

      paint.color = _colors[i % _colors.length];
      canvas.drawCircle(Offset(x, y), radius, paint);
      paint.color = const Color(0x66FFFFFF);
      canvas.drawCircle(
        Offset(x - radius * 0.3, y - radius * 0.3),
        radius * 0.22,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) => oldDelegate.t != t;
}

/// Skor bintang, 0 sampai 3. Bintang muncul satu per satu.
/// TalkBack membacanya sebagai satu kalimat, bukan tiga ikon.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 56});

  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars dari 3 bintang',
      image: true,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            FadeSlideIn(
              delay: Duration(milliseconds: 250 + i * 280),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Garis tepi gelap supaya bintang tetap terlihat jelas.
                  Icon(Icons.star_rounded, size: size, color: AppColors.ink),
                  Icon(
                    Icons.star_rounded,
                    size: size * 0.8,
                    color: i < stars ? AppColors.sun : AppColors.white,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Logo APREVO: lima batang gelombang suara yang naik-turun pelan.
/// Hanya hiasan; nama aplikasinya dibacakan dari teks di sebelahnya.
class SoundWaveLogo extends StatelessWidget {
  const SoundWaveLogo({super.key, this.height = 72, this.onDark = false});

  final double height;

  /// `true` untuk latar ungu (batang kuning dan putih),
  /// `false` untuk latar putih (batang kuning dan ungu).
  final bool onDark;

  static const List<double> _levels = [0.45, 0.8, 1, 0.8, 0.45];

  @override
  Widget build(BuildContext context) {
    final other = onDark ? AppColors.white : AppColors.primary;
    final barWidth = height * 0.12;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Loop(
          duration: const Duration(milliseconds: 1800),
          builder: (context, t) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _levels.length; i++)
                Container(
                  width: barWidth,
                  height: height *
                      _levels[i] *
                      (0.8 + 0.2 * math.sin(t * 2 * math.pi + i * 1.1)),
                  margin: EdgeInsets.symmetric(horizontal: barWidth * 0.3),
                  decoration: BoxDecoration(
                    color: i.isEven ? AppColors.accent : other,
                    borderRadius: BorderRadius.circular(barWidth),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lingkaran yang berdenyut pelan di belakang sebuah ikon.
class PulseRings extends StatelessWidget {
  const PulseRings({
    super.key,
    required this.size,
    required this.color,
    required this.child,
  });

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(
            child: Loop(
              duration: const Duration(milliseconds: 2400),
              builder: (context, t) {
                final grow = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final scale in const [1.0, 0.8])
                      Container(
                        width: size * scale * (0.92 + 0.08 * grow),
                        height: size * scale * (0.92 + 0.08 * grow),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Kerangka layar APREVO: latar ungu bergradasi dengan hiasan, dan isi
/// berwarna putih di atasnya. Dipakai sebagai pengganti `Scaffold`.
class PurpleScaffold extends StatelessWidget {
  const PurpleScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.backgroundColor,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;

  /// Diabaikan; latarnya selalu ungu. Ada supaya kode lama tetap cocok.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _BackdropPainter()),
            ),
          ),
          Theme(
            data: aprevoOnPurpleTheme,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: AppColors.white),
              // Di layar lebar (browser, tablet) isi tetap selebar HP dan
              // berada di tengah, tidak melar ke seluruh layar.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: body,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hiasan latar: gradasi ungu dengan dua lengkung besar ungu muda.
/// Diam, supaya tidak mengganggu isi.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, AppColors.bgBottom],
        ).createShader(rect),
    );

    final paint = Paint();
    final w = size.width;
    final h = size.height;

    // Dua lengkung besar di pojok.
    paint.color = const Color(0x1FCDBDFF);
    canvas.drawCircle(Offset(w * 1.05, h * 0.08), w * 0.42, paint);
    canvas.drawCircle(Offset(-w * 0.12, h * 0.78), w * 0.38, paint);
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}

/// Lembar putih dengan gaya stiker, untuk membungkus form di latar ungu.
class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.fromBorderSide(kStickerSide),
        boxShadow: kStickerShadow,
      ),
      child: Theme(
        data: buildAprevoTheme(),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: AppColors.ink),
          child: child,
        ),
      ),
    );
  }
}
