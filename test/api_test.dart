import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aprevo/config/api_config.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/services/api_client.dart';
import 'package:aprevo/services/time_format.dart';

import 'fake_server.dart';

void main() {
  group('alamat server', () {
    test('IP tanpa skema mendapat http dan port 8000', () {
      expect(ApiConfig.normalize(' 192.168.1.7 '), 'http://192.168.1.7:8000');
      expect(
        ApiConfig.normalize('192.168.1.7:9000'),
        'http://192.168.1.7:9000',
      );
    });

    test('alamat lengkap dipakai apa adanya, garis miring dibuang', () {
      expect(
        ApiConfig.normalize('http://10.0.2.2:8000/'),
        'http://10.0.2.2:8000',
      );
      expect(
        ApiConfig.normalize('https://api.contoh.id'),
        'https://api.contoh.id',
      );
    });

    test('alamat kosong atau bukan http ditolak', () {
      expect(ApiConfig.normalize(''), isNull);
      expect(ApiConfig.normalize('ftp://laptop'), isNull);
    });
  });

  test('waktu dikirim lengkap dengan zona waktu', () {
    final local = DateTime(2026, 11, 3, 21, 0);
    final iso = isoWithOffset(local);
    expect(iso, matches(RegExp(r'^2026-11-03T21:00:00[+-]\d\d:\d\d$')));
    expect(DateTime.parse(iso).isAtSameMomentAs(local), isTrue);
  });

  test('tanggal dibaca dalam bahasa Indonesia', () {
    // 3 November 2026 adalah hari Selasa.
    expect(
      formatDateTime(DateTime(2026, 11, 3, 21, 5)),
      'Selasa, 3 November 2026 pukul 21.05',
    );
  });

  group('pesan error', () {
    test('detail dari backend dipakai, diakhiri titik', () {
      expect(
        ApiClient.errorMessage(403, {'detail': 'Kuis belum tersedia'}),
        'Kuis belum tersedia.',
      );
    });

    test('error validasi 422 dirapikan', () {
      expect(
        ApiClient.errorMessage(422, {
          'detail': [
            {'msg': 'Value error, Opsi tidak boleh duplikat.'},
          ],
        }),
        'Opsi tidak boleh duplikat.',
      );
    });

    test('error server tanpa detail', () {
      expect(ApiClient.errorMessage(500, null), contains('kode 500'));
    });

    test('server mati: pesan menyebut alamatnya', () async {
      final api = ApiClient(
        client: MockClient((_) async => throw http.ClientException('mati')),
        baseUrl: () => fakeBaseUrl,
      );
      await expectLater(
        api.get('/student/subjects'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            startsWith('Tidak bisa terhubung ke server di $fakeBaseUrl.'),
          ),
        ),
      );
    });
  });

  test('token dikirim, dan 401 memperbarui token lalu mengulang', () async {
    var token = 'lama';
    final seen = <String?>[];
    final api = ApiClient(
      client: MockClient((request) async {
        seen.add(request.headers['Authorization']);
        if (request.headers['Authorization'] == 'Bearer lama') {
          return jsonResponse({'detail': 'Token tidak valid'}, 401);
        }
        return jsonResponse({'subjects': []});
      }),
      baseUrl: () => fakeBaseUrl,
      token: () async => token,
      refreshToken: () async {
        token = 'baru';
        return true;
      },
    );
    expect(await api.get('/student/subjects'), {'subjects': []});
    expect(seen, ['Bearer lama', 'Bearer baru']);
  });

  group('bentuk soal untuk backend', () {
    test('pilihan ganda: tepat satu benar', () {
      final q = Question(
        prompt: 'Ibu kota?',
        options: ['A', 'B', 'C', 'D'],
        correctIndex: 2,
        explanation: 'Karena C.',
      );
      expect(q.toApi(GameType.quiz), {
        'type': 'multiple_choice',
        'question': 'Ibu kota?',
        'explanation': 'Karena C.',
        'options': [
          {'text': 'A', 'is_correct': false},
          {'text': 'B', 'is_correct': false},
          {'text': 'C', 'is_correct': true},
          {'text': 'D', 'is_correct': false},
        ],
      });
    });

    test('isian: beberapa jawaban dipisah titik koma', () {
      final q = Question(prompt: 'Planet ke?', answerText: 'ketiga; 3');
      expect(q.toApi(GameType.shortAnswer)['answers'], [
        {'answer': 'ketiga'},
        {'answer': '3'},
      ]);
    });

    test('benar/salah dan urutan', () {
      final tf = Question(prompt: 'P', correctIndex: 1);
      expect(tf.toApi(GameType.trueFalse)['correct_answer'], false);
      final order = Question(prompt: 'U', options: ['x', 'y']);
      expect(order.toApi(GameType.ordering)['items'], [
        {'text': 'x', 'correct_order': 1},
        {'text': 'y', 'correct_order': 2},
      ]);
    });
  });

  test('jawaban siswa: tepat satu format', () {
    expect(const StudentAnswer.option('o1').toJson('q1'), {
      'question_id': 'q1',
      'selected_option_ids': ['o1'],
    });
    expect(const StudentAnswer.boolean(false).toJson('q1'), {
      'question_id': 'q1',
      'boolean_value': false,
    });
    expect(const StudentAnswer.order(['b', 'a']).toJson('q1'), {
      'question_id': 'q1',
      'ordered_item_ids': ['b', 'a'],
    });
  });
}
