// Ikon dan manifest versi web: logo APREVO, bukan logo Flutter.
import 'dart:convert';
import 'dart:io';

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
      final (width, height) = _pngSize('web/${map['src']}');
      expect('${width}x$height', map['sizes'], reason: map['src'] as String);
    }
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
}
