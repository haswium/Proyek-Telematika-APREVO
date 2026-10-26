import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'settings.dart';

/// Error dari backend atau sambungan. [message] sudah berbahasa Indonesia dan
/// siap dibacakan ke pengguna.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// `null` kalau server tidak terjangkau.
  final int? statusCode;

  @override
  String toString() => message;
}

/// Sambungan ke backend FastAPI APREVO (lihat `docs/kontrak-api.md`).
///
/// Setiap permintaan membawa token Supabase di header `Authorization`.
/// Kalau server membalas 401, token diperbarui sekali lalu permintaan
/// diulang.
class ApiClient {
  ApiClient({
    http.Client? client,
    String Function()? baseUrl,
    Future<String?> Function()? token,
    Future<bool> Function()? refreshToken,
  }) : _http = client ?? http.Client(),
       _baseUrl = baseUrl ?? (() => Settings.baseUrl),
       _token = token ?? (() async => null),
       _refresh = refreshToken ?? (() async => false);

  final http.Client _http;
  final String Function() _baseUrl;
  final Future<String?> Function() _token;
  final Future<bool> Function() _refresh;

  static const Duration timeout = Duration(seconds: 20);

  /// PDF besar butuh waktu untuk diunggah dan dipecah per sub-bab.
  static const Duration uploadTimeout = Duration(minutes: 3);

  String get baseUrl => _baseUrl();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send('POST', path, body);

  Future<Map<String, dynamic>> put(String path, Object body) =>
      _send('PUT', path, body);

  Future<Map<String, dynamic>> patch(String path, Object body) =>
      _send('PATCH', path, body);

  /// Unggah satu file lewat multipart, bersama kolom teks [fields].
  ///
  /// [contentType] wajib diisi: tanpa itu `http` mengirim
  /// `application/octet-stream`.
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required Uint8List bytes,
    required MediaType contentType,
  }) {
    return _run(() async {
      final request = http.MultipartRequest('POST', _uri(path))
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            fileField,
            bytes,
            filename: fileName,
            contentType: contentType,
          ),
        );
      request.headers.addAll(await _headers(json: false));
      return http.Response.fromStream(await _http.send(request));
    }, timeout: uploadTimeout);
  }

  /// Memeriksa apakah backend di [url] bisa dihubungi (`GET /`).
  /// Mengembalikan pesan error, atau `null` kalau tersambung.
  Future<String?> ping(String url) async {
    try {
      final response = await _http
          .get(Uri.parse('$url/'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return null;
      return 'Server di $url menjawab dengan kode ${response.statusCode}. '
          'Pastikan alamatnya mengarah ke backend APREVO.';
    } catch (_) {
      return unreachableMessage(url);
    }
  }

  static String unreachableMessage(String url) =>
      'Tidak bisa terhubung ke server di $url. Pastikan backend menyala, '
      'lalu HP dan laptop memakai Wi-Fi yang sama.';

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _token();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Object? body,
  ]) {
    return _run(() async {
      final request = http.Request(method, _uri(path))
        ..headers.addAll(await _headers());
      if (body != null) request.body = jsonEncode(body);
      return http.Response.fromStream(await _http.send(request));
    });
  }

  Future<Map<String, dynamic>> _run(
    Future<http.Response> Function() send, {
    Duration timeout = timeout,
  }) async {
    var response = await _guard(send, timeout);
    if (response.statusCode == 401 && await _refresh()) {
      response = await _guard(send, timeout);
    }
    return _decode(response);
  }

  Future<http.Response> _guard(
    Future<http.Response> Function() send,
    Duration timeout,
  ) async {
    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        'Server di $baseUrl terlalu lama menjawab. Periksa sambungan, lalu '
        'coba lagi.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      // http.ClientException, termasuk SocketException di Android, dan
      // XMLHttpRequest gagal di web (biasanya CORS atau server mati).
      throw ApiException(unreachableMessage(baseUrl));
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final code = response.statusCode;
    Object? data;
    try {
      data = response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (code >= 200 && code < 300) {
      if (data is Map<String, dynamic>) return data;
      return const {};
    }
    throw ApiException(errorMessage(code, data), statusCode: code);
  }

  /// Pesan error dari respons gagal. `detail` dari FastAPI sudah berbahasa
  /// Indonesia, jadi dipakai apa adanya. Error validasi (422) berupa daftar.
  @visibleForTesting
  static String errorMessage(int code, Object? data) {
    final detail = data is Map ? data['detail'] : null;
    if (detail is String && detail.trim().isNotEmpty) {
      return _sentence(detail.trim());
    }
    if (detail is List && detail.isNotEmpty) {
      final parts = <String>[
        for (final item in detail)
          if (item is Map && item['msg'] is String)
            _sentence(
              (item['msg'] as String).replaceFirst('Value error, ', ''),
            ),
      ];
      if (parts.isNotEmpty) return parts.toSet().join(' ');
    }
    if (code == 401) {
      return 'Sesi masuk sudah habis. Keluar dari akun, lalu masuk lagi.';
    }
    if (code == 403) return 'Kamu tidak punya izin untuk membuka ini.';
    if (code == 404) return 'Data tidak ditemukan.';
    if (code == 413) return 'File terlalu besar.';
    if (code >= 500) {
      return 'Server sedang bermasalah (kode $code). Coba lagi sebentar '
          'lagi.';
    }
    return 'Permintaan gagal (kode $code). Coba lagi.';
  }

  /// Pesan diakhiri titik supaya dibacakan sebagai kalimat utuh.
  static String _sentence(String text) =>
      RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}
