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

  /// Server gratis di Render tidur kalau lama tidak dipakai dan butuh sekitar
  /// satu menit untuk bangun. Selama itu permintaannya ditahan, jadi batasnya
  /// harus lebih panjang.
  static const Duration timeout = Duration(seconds: 90);

  /// Belum ada jawaban selama ini: pengguna diberi tahu server sedang bangun.
  static const Duration slowAfter = Duration(seconds: 5);

  /// Server yang menjawab selama ini tidak mungkin tidur, jadi permintaan yang
  /// lambat berarti prosesnya memang lama, misalnya AI. Render menidurkan layanan
  /// setelah 15 menit.
  static const Duration awakeFor = Duration(minutes: 10);

  /// Jeda sebelum mengulang permintaan yang dijawab Render, bukan backend.
  static const Duration wakeRetryDelay = Duration(seconds: 5);

  /// PDF besar butuh waktu untuk diunggah dan dipecah per sub-bab.
  static const Duration uploadTimeout = Duration(minutes: 3);

  /// `true` selama pengguna menunggu server bangun.
  final ValueNotifier<bool> connecting = ValueNotifier(false);

  /// Apakah permintaan terakhir mendapat jawaban.
  bool get reachable => _reachable;
  bool _reachable = true;
  DateTime? _answeredAt;
  int _waiting = 0;

  bool get _recentlyAnswered {
    final at = _answeredAt;
    return at != null && DateTime.now().difference(at) < awakeFor;
  }

  String get baseUrl => _baseUrl();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send('POST', path, body);

  Future<Map<String, dynamic>> put(String path, Object body) =>
      _send('PUT', path, body);

  Future<Map<String, dynamic>> patch(String path, Object body) =>
      _send('PATCH', path, body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

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

  /// Memeriksa apakah backend di [url] bisa dihubungi, untuk menu pengembang.
  /// Mengembalikan pesan error, atau `null` kalau tersambung.
  Future<String?> ping(String url) async {
    try {
      final response = await _guard(
        () => _http.get(Uri.parse('$url/health')),
        timeout,
        quiet: true,
      );
      if (response.statusCode == 200) return null;
      return 'Server di $url menjawab dengan kode ${response.statusCode}. '
          'Pastikan alamatnya mengarah ke backend APREVO.';
    } on ApiException {
      return 'Tidak bisa terhubung ke $url. Pastikan alamatnya benar dan '
          'backend menyala.';
    }
  }

  /// Membangunkan server saat aplikasi dibuka, supaya siap selagi siswa masuk.
  /// Tanpa pesan apa pun, karena siswa belum menunggu apa-apa.
  Future<void> wakeUp() async {
    try {
      await _guard(
        () => _http.get(_uri('/health')),
        timeout,
        retryDrop: true,
        quiet: true,
      );
    } on ApiException {
      // Permintaan berikutnya yang akan memberi tahu pengguna.
    }
  }

  static const String unreachableMessage =
      'Tidak bisa terhubung ke server. Periksa internet HP, lalu coba lagi.';

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _token();
    return {
      'Accept': 'application/json',
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
    }, retryDrop: method == 'GET');
  }

  Future<Map<String, dynamic>> _run(
    Future<http.Response> Function() send, {
    Duration timeout = timeout,
    bool retryDrop = false,
  }) async {
    var response = await _guard(send, timeout, retryDrop: retryDrop);
    if (response.statusCode == 401 && await _refresh()) {
      response = await _guard(send, timeout, retryDrop: retryDrop);
    }
    return _decode(response);
  }

  /// Mengirim permintaan dan menunggu server, termasuk selama server bangun.
  ///
  /// Permintaan yang lambat tidak pernah dikirim ulang, karena mungkin sudah
  /// diproses backend, misalnya jawaban kuis. Yang diulang hanya jawaban dari
  /// Render, dan sambungan putus kalau [retryDrop].
  Future<http.Response> _guard(
    Future<http.Response> Function() send,
    Duration timeout, {
    bool retryDrop = false,
    bool quiet = false,
  }) async {
    var stopped = false;
    var counted = false;
    void markWaiting() {
      if (counted || quiet) return;
      counted = true;
      _waiting++;
      connecting.value = true;
    }

    final slow = _recentlyAnswered ? null : Timer(slowAfter, markWaiting);
    try {
      final response = await _untilBackendAnswers(
        send,
        () => stopped,
        markWaiting,
        retryDrop,
      ).timeout(timeout);
      _answeredAt = DateTime.now();
      _reachable = true;
      return response;
    } on TimeoutException {
      stopped = true;
      _reachable = false;
      throw const ApiException(
        'Server terlalu lama menjawab. Periksa internet HP, lalu coba lagi.',
      );
    } on ApiException {
      _reachable = false;
      rethrow;
    } catch (_) {
      // http.ClientException, termasuk SocketException di Android, dan
      // XMLHttpRequest gagal di web (biasanya CORS atau server mati).
      _reachable = false;
      throw const ApiException(unreachableMessage);
    } finally {
      slow?.cancel();
      if (counted) {
        _waiting--;
        if (_waiting == 0) connecting.value = false;
      }
    }
  }

  Future<http.Response> _untilBackendAnswers(
    Future<http.Response> Function() send,
    bool Function() stopped,
    VoidCallback markWaiting,
    bool retryDrop,
  ) async {
    var dropped = false;
    while (true) {
      final http.Response response;
      try {
        response = await send();
      } on ApiException {
        rethrow;
      } catch (_) {
        // Sambungan lama bisa sudah mati setelah server tidur.
        if (!retryDrop || dropped || stopped()) rethrow;
        dropped = true;
        continue;
      }
      if (!_isFromRender(response)) return response;
      markWaiting();
      await Future<void>.delayed(wakeRetryDelay);
      if (stopped()) return response;
    }
  }

  /// Jawaban Render saat layanan bangun atau deploy, bukan dari backend, jadi
  /// permintaannya belum diproses. Error backend selalu JSON, termasuk 502 saat
  /// Gemini gagal. Halaman tunggu bisa berstatus 200, dan tidak boleh dianggap
  /// data kosong.
  static bool _isFromRender(http.Response response) {
    final type = response.headers['content-type'] ?? '';
    final code = response.statusCode;
    if (code == 502 || code == 503 || code == 504) {
      return !type.contains('application/json');
    }
    return code >= 200 && code < 300 && type.contains('text/html');
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
      return 'Server mengalami kesalahan (kode $code). Coba lagi sebentar '
          'lagi.';
    }
    return 'Permintaan gagal (kode $code). Coba lagi.';
  }

  /// Pesan diakhiri titik supaya dibacakan sebagai kalimat utuh.
  static String _sentence(String text) =>
      RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}
