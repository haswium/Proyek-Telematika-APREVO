import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../config/api_config.dart';

/// Kegagalan saat memanggil backend. [message] sudah dalam bahasa Indonesia
/// dan siap dibacakan ke siswa.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Pemanggil backend FastAPI. Setiap permintaan membawa token login
/// Supabase sebagai `Authorization: Bearer <token>`, yang dicek backend
/// lewat `get_current_user`.
class ApiClient {
  ApiClient._();

  static Future<dynamic> get(String path) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      throw ApiException('Kamu belum masuk. Silakan masuk lagi.');
    }

    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw ApiException('Server terlalu lama menjawab. Coba lagi.');
    } catch (_) {
      // Di Chrome, CORS yang belum diizinkan juga berakhir di sini.
      throw ApiException(
        'Tidak bisa terhubung ke server. Periksa sambungan internet.',
      );
    }

    final code = response.statusCode;
    if (code >= 200 && code < 300) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (code == 401 || code == 403) {
      throw ApiException(
        'Sesi masuk sudah habis. Silakan keluar lalu masuk lagi.',
        statusCode: code,
      );
    }
    if (code == 404) {
      throw ApiException('Data tidak ditemukan di server.', statusCode: code);
    }
    throw ApiException(
      'Server sedang bermasalah. Coba lagi nanti.',
      statusCode: code,
    );
  }
}
