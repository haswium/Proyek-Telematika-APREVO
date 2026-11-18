// Ikon versi web dan launcher Android: logo APREVO, bukan logo Flutter.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/theme/app_theme.dart';

/// Lebar dan tinggi dari header PNG (IHDR).
(int, int) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.sublist(1, 4), utf8.encode('PNG'), reason: path);
  int read(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  return (read(16), read(20));
}

/// Path file dari href, tanpa query versi ("favicon.png?v=2").
String _file(String href) => 'web/${href.split('?').first}';

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  test('manifest memakai nama APREVO dan ungu tua aplikasi', () {
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['name'], 'APREVO');
    expect(manifest['short_name'], 'APREVO');
    final purple = _hex(AppColors.bgBottom.toARGB32());
    expect(manifest['background_color'], purple);
    expect(manifest['theme_color'], purple);
    expect(manifest['description'], contains('siswa tunanetra'));
    for (final icon in manifest['icons'] as List) {
      final map = icon as Map<String, dynamic>;
      final src = map['src'] as String;
      expect(src, contains('?v='), reason: 'query versi melewati cache');
      final (width, height) = _pngSize(_file(src));
      expect('${width}x$height', map['sizes'], reason: map['src'] as String);
    }
  });

  test('tautan ikon di index.html memakai query versi dan filenya ada', () {
    final html = File('web/index.html').readAsStringSync();
    final links = RegExp(
      r'<link rel="(icon|apple-touch-icon|manifest)"[^>]*href="([^"]+)"',
    ).allMatches(html).toList();
    expect(links.map((m) => m.group(1)).toSet(), {
      'icon',
      'apple-touch-icon',
      'manifest',
    });
    for (final link in links) {
      final href = link.group(2)!;
      expect(href, matches(RegExp(r'\?v=\d+$')), reason: href);
      // Relatif terhadap <base href>, jadi tanpa garis miring di depan.
      expect(href, isNot(startsWith('/')), reason: href);
      expect(File(_file(href)).existsSync(), isTrue, reason: href);
    }
    expect(html, contains('href="favicon.png?v='));
    expect(html, contains(r'<base href="$FLUTTER_BASE_HREF">'));
  });

  testWidgets('favicon berisi logo APREVO, bukan logo Flutter', (tester) async {
    // Logo APREVO punya batang kuning #FFC400; logo Flutter hanya biru.
    final yellow = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File('web/favicon.png').readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData();
      var count = 0;
      for (var i = 0; i + 3 < data!.lengthInBytes; i += 4) {
        final r = data.getUint8(i), g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2), a = data.getUint8(i + 3);
        if (a > 200 && r > 230 && g > 170 && g < 220 && b < 60) count++;
      }
      return count;
    });
    expect(yellow, greaterThan(10));
  });

  test('favicon ada dan judul tab APREVO', () {
    final (width, height) = _pngSize('web/favicon.png');
    expect(width, height);
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<title>APREVO</title>'));
    expect(html, contains('lang="id"'));
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains("title: 'APREVO'"),
    );
  });

  test('aplikasi Android bernama APREVO dengan adaptive icon', () {
    const res = 'android/app/src/main/res';
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:label="APREVO"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    final adaptive = File('$res/mipmap-anydpi-v26/ic_launcher.xml')
        .readAsStringSync();
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    // Latar ungu tua AppColors.bgBottom.
    expect(
      File('$res/values/colors.xml').readAsStringSync(),
      contains(_hex(AppColors.bgBottom.toARGB32())),
    );
    for (final (density, size) in [
      ('mdpi', 48),
      ('hdpi', 72),
      ('xhdpi', 96),
      ('xxhdpi', 144),
      ('xxxhdpi', 192),
    ]) {
      expect(_pngSize('$res/mipmap-$density/ic_launcher.png'), (
        size,
        size,
      ), reason: density);
      expect(
        File('$res/drawable-$density/ic_launcher_foreground.png').existsSync(),
        isTrue,
        reason: density,
      );
    }
  });
}
