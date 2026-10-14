import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/speech.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'playful.dart';

enum MascotMood { happy, cheer, oops, thinking }

/// Odi, maskot APREVO: gurita kecil ungu muda dengan headphone kuning.
///
/// Digambar langsung dengan kode (CustomPainter), jadi tidak perlu file
/// gambar. Karena siswa tunanetra tidak melihatnya, Odi selalu punya
/// deskripsi: TalkBack membacakannya, dan mengetuk Odi membacakan
/// deskripsinya dengan suara.
class Mascot extends StatelessWidget {
  const Mascot({
    super.key,
    this.size = 120,
    this.mood = MascotMood.happy,
    this.decorative = false,
  });

  final double size;
  final MascotMood mood;

  /// `true` kalau Odi hanya menemani teks lain di sebelahnya, supaya
  /// TalkBack tidak berhenti di Odi berulang-ulang.
  final bool decorative;

  static String describe(MascotMood mood) {
    const base =
        'Odi, maskot APREVO. Gurita kecil berwarna ungu muda dengan mata '
        'bulat besar, pipi kuning, dan headphone berwarna kuning.';
    switch (mood) {
      case MascotMood.happy:
        return '$base Odi sedang tersenyum.';
      case MascotMood.cheer:
        return '$base Odi bersorak gembira sampai matanya terpejam.';
      case MascotMood.oops:
        return '$base Odi membulatkan mulutnya, memberi semangat.';
      case MascotMood.thinking:
        return '$base Odi sedang berpikir sambil melirik ke atas.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = describe(mood);
    final picture = Loop(
      duration: const Duration(milliseconds: 2600),
      builder: (context, t) => Transform.translate(
        offset: Offset(0, math.sin(t * 2 * math.pi) * size * 0.035),
        child: CustomPaint(
          size: Size.square(size),
          painter: _OdiPainter(t: t, mood: mood),
        ),
      ),
    );

    if (decorative) return ExcludeSemantics(child: picture);

    void speak() => Speech.speak(description);
    return Semantics(
      label: description,
      image: true,
      button: true,
      onTap: speak,
      onTapHint: 'mendengar deskripsi Odi',
      excludeSemantics: true,
      child: GestureDetector(onTap: speak, child: picture),
    );
  }
}

/// Odi dengan balon ucapan. Teks di balon adalah isi yang dibaca TalkBack;
/// Odi di sebelahnya hanya hiasan.
class MascotBubble extends StatelessWidget {
  const MascotBubble({
    super.key,
    required this.text,
    this.mood = MascotMood.happy,
    this.color = AppColors.highlight,
  });

  final String text;
  final MascotMood mood;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: Row(
        children: [
          Mascot(size: 84, mood: mood, decorative: true),
          const SizedBox(width: 10),
          Expanded(
            child: AppCard(
              color: color,
              borderColor: AppColors.ink,
              child: Text(text, style: AppType.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}

class _OdiPainter extends CustomPainter {
  _OdiPainter({required this.t, required this.mood});

  final double t;
  final MascotMood mood;

  static const Color _body = Color(0xFFCDBDFF);
  static const Color _bodyDark = Color(0xFF8468F5);
  static const Color _cheek = Color(0xFFFFC400);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2;
    final head = Offset(cx, s * 0.42);
    final r = s * 0.30;
    final fill = Paint()..style = PaintingStyle.fill;

    // Tentakel, bergoyang bergantian.
    fill.color = _bodyDark;
    for (var i = 0; i < 4; i++) {
      final x = cx + (i - 1.5) * s * 0.145;
      final wiggle = math.sin(t * 2 * math.pi + i * 1.4) * s * 0.025;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x - s * 0.055 + wiggle * 0.4,
            s * 0.58,
            x + s * 0.055 + wiggle * 0.4,
            s * 0.86 + wiggle,
          ),
          Radius.circular(s * 0.06),
        ),
        fill,
      );
    }

    // Badan.
    fill.color = _body;
    canvas.drawCircle(head, r, fill);
    fill.color = const Color(0x55FFFFFF);
    canvas.drawCircle(Offset(cx - r * 0.42, head.dy - r * 0.48), r * 0.2, fill);

    // Headphone: bando lalu dua bantalan telinga.
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.06
      ..color = AppColors.accent;
    canvas.drawArc(
      Rect.fromCircle(center: head, radius: r + s * 0.035),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      band,
    );
    for (final side in const [-1.0, 1.0]) {
      final cup = Rect.fromCenter(
        center: Offset(cx + side * (r + s * 0.01), s * 0.45),
        width: s * 0.12,
        height: s * 0.2,
      );
      fill.color = AppColors.accent;
      canvas.drawRRect(
        RRect.fromRectAndRadius(cup, Radius.circular(s * 0.05)),
        fill,
      );
      fill.color = AppColors.highlight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cup.deflate(s * 0.03),
          Radius.circular(s * 0.03),
        ),
        fill,
      );
    }

    // Pipi.
    fill.color = _cheek;
    canvas.drawCircle(Offset(cx - s * 0.19, s * 0.49), s * 0.04, fill);
    canvas.drawCircle(Offset(cx + s * 0.19, s * 0.49), s * 0.04, fill);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.025
      ..color = AppColors.ink;

    // Mata.
    for (final side in const [-1.0, 1.0]) {
      final eye = Offset(cx + side * s * 0.11, s * 0.40);
      if (mood == MascotMood.cheer) {
        canvas.drawArc(
          Rect.fromCircle(center: eye, radius: s * 0.05),
          math.pi,
          math.pi,
          false,
          line,
        );
        continue;
      }
      fill.color = AppColors.white;
      canvas.drawCircle(eye, s * 0.07, fill);
      var pupil = eye;
      if (mood == MascotMood.thinking) {
        pupil = eye + Offset(s * 0.02, -s * 0.025);
      } else if (mood == MascotMood.oops) {
        pupil = eye + Offset(0, s * 0.015);
      }
      fill.color = AppColors.ink;
      canvas.drawCircle(pupil, s * 0.038, fill);
      fill.color = AppColors.white;
      canvas.drawCircle(pupil + Offset(-s * 0.012, -s * 0.012), s * 0.012, fill);
    }

    // Mulut.
    final mouth = Offset(cx, s * 0.50);
    switch (mood) {
      case MascotMood.happy:
        canvas.drawArc(
          Rect.fromCenter(center: mouth, width: s * 0.14, height: s * 0.10),
          math.pi * 0.15,
          math.pi * 0.7,
          false,
          line,
        );
      case MascotMood.cheer:
        fill.color = AppColors.ink;
        canvas.drawArc(
          Rect.fromCenter(center: mouth, width: s * 0.15, height: s * 0.14),
          0,
          math.pi,
          true,
          fill,
        );
      case MascotMood.oops:
        canvas.drawOval(
          Rect.fromCenter(
            center: mouth + Offset(0, s * 0.02),
            width: s * 0.06,
            height: s * 0.07,
          ),
          line,
        );
      case MascotMood.thinking:
        canvas.drawLine(
          mouth + Offset(-s * 0.04, s * 0.025),
          mouth + Offset(s * 0.04, s * 0.015),
          line,
        );
    }
  }

  @override
  bool shouldRepaint(_OdiPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.mood != mood;
}
