import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aprevo/config/api_config.dart';
import 'package:aprevo/screens/server_settings_screen.dart';
import 'package:aprevo/services/api_client.dart';
import 'package:aprevo/widgets/connecting_banner.dart';

import 'fake_server.dart';

http.Response _json(Object body, [int status = 200]) =>
    jsonResponse(body, status);

http.Response _html(int status) => http.Response(
  '<html>Service waking up</html>',
  status,
  headers: {'content-type': 'text/html; charset=utf-8'},
);

/// Klien dengan server tiruan yang menjawab setelah [delay].
ApiClient _client(
  http.Response Function(http.Request request) answer, {
  Duration delay = Duration.zero,
}) => ApiClient(
  client: MockClient((request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return answer(request);
  }),
  baseUrl: () => fakeBaseUrl,
);

Future<void> _pumpBanner(WidgetTester tester, ApiClient api) => tester
    .pumpWidget(testApp(ConnectingBanner(api: api, child: const Text('Isi'))));

List<String> _announced(WidgetTester tester) => [
  for (final a in tester.takeAnnouncements()) a.message,
];

void main() {
  group('saat server sedang bangun', () {
    testWidgets('pesan muncul setelah 5 detik, lalu server tersambung', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final api = _client(
        (_) => _json({'ok': true}),
        delay: const Duration(seconds: 40),
      );
      await _pumpBanner(tester, api);

      Map<String, dynamic>? result;
      api.get('/student/subjects').then((value) => result = value);
      await tester.pump(ApiClient.slowAfter - const Duration(milliseconds: 1));
      expect(find.text(kConnectingMessage), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text(kConnectingMessage), findsOneWidget);
      expectLive(tester, kConnectingMessage);
      // Lebih lama dari batas waktu lama (20 detik): belum error.
      await tester.pump(const Duration(seconds: 30));
      expect(result, isNull);

      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(result, {'ok': true});
      expect(find.text(kConnectingMessage), findsNothing);
      expect(_announced(tester), [kConnectedMessage]);
      handle.dispose();
    });

    testWidgets('server sudah menjawab: proses lama tidak disangka tidur', (
      tester,
    ) async {
      var delay = Duration.zero;
      final api = ApiClient(
        client: MockClient((_) async {
          await Future<void>.delayed(delay);
          return _json({'ok': true});
        }),
        baseUrl: () => fakeBaseUrl,
      );
      await _pumpBanner(tester, api);
      final first = api.get('/a');
      await tester.pump(const Duration(milliseconds: 1));
      await first;

      delay = const Duration(seconds: 30);
      final second = api.post('/teacher/materials/m1/generate-quiz');
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(kConnectingMessage), findsNothing);
      await tester.pump(const Duration(seconds: 21));
      await second;
    });

    testWidgets('server tidak pernah menjawab: pesan error, bukan tersambung', (
      tester,
    ) async {
      final api = _client(
        (_) => _json({'ok': true}),
        delay: const Duration(minutes: 5),
      );
      await _pumpBanner(tester, api);
      Object? error;
      api
          .get('/a')
          .then<void>(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      await tester.pump(ApiClient.timeout);
      await tester.pump();
      expect(
        error,
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Server terlalu lama menjawab. Periksa internet HP, lalu coba lagi.',
        ),
      );
      expect(find.text(kConnectingMessage), findsNothing);
      expect(_announced(tester), isNot(contains(kConnectedMessage)));
      await tester.pump(const Duration(minutes: 5));
    });

    testWidgets('halaman HTML dari Render diulang, dan pesan langsung muncul', (
      tester,
    ) async {
      for (final waking in [503, 502, 504, 200]) {
        var calls = 0;
        final api = _client((_) {
          calls++;
          return calls == 1 ? _html(waking) : _json({'ok': true});
        });
        await _pumpBanner(tester, api);
        Map<String, dynamic>? result;
        api.post('/quizzes/q/attempts').then((value) => result = value);
        await tester.pump();
        await tester.pump();
        // Status 200 berisi HTML tidak boleh dianggap data kosong.
        expect(result, isNull, reason: 'status $waking');
        expect(find.text(kConnectingMessage), findsOneWidget);

        await tester.pump(ApiClient.wakeRetryDelay);
        await tester.pump();
        expect(calls, 2, reason: 'status $waking');
        expect(result, {'ok': true}, reason: 'status $waking');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('layar tidak dibangun ulang saat spanduk muncul', (
      tester,
    ) async {
      final api = _client(
        (_) => _json({'ok': true}),
        delay: const Duration(seconds: 10),
      );
      final key = GlobalKey<_CounterState>();
      await tester.pumpWidget(
        testApp(
          ConnectingBanner(
            api: api,
            child: _Counter(key: key),
          ),
        ),
      );
      final state = key.currentState;

      final pending = api.get('/a');
      await tester.pump(ApiClient.slowAfter);
      await tester.pump();
      expect(find.text(kConnectingMessage), findsOneWidget);
      expect(key.currentState, same(state));

      await tester.pump(const Duration(seconds: 6));
      await pending;
      await tester.pump();
      expect(find.text(kConnectingMessage), findsNothing);
      expect(key.currentState, same(state));
    });
  });

  group('tidak dikirim dua kali', () {
    test('error JSON dari backend tidak diulang', () async {
      var calls = 0;
      final api = _client((_) {
        calls++;
        return _json({'detail': 'Gemini sedang sibuk'}, 502);
      });
      await expectLater(
        api.post('/teacher/materials/m1/generate-quiz'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 502)
              .having((e) => e.message, 'message', 'Gemini sedang sibuk.'),
        ),
      );
      expect(calls, 1);
    });

    test('sambungan putus: GET dicoba sekali lagi', () async {
      var calls = 0;
      final api = _client((_) {
        calls++;
        if (calls == 1) throw http.ClientException('putus');
        return _json({'ok': true});
      });
      expect(await api.get('/a'), {'ok': true});
      expect(calls, 2);
    });

    for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
      test('sambungan putus: $method tidak dikirim ulang', () async {
        var calls = 0;
        final api = _client((_) {
          calls++;
          throw http.ClientException('putus');
        });
        final Future<Object?> call = switch (method) {
          'POST' => api.post('/a'),
          'PUT' => api.put('/a', const {}),
          'PATCH' => api.patch('/a', const {}),
          _ => api.delete('/a'),
        };
        await expectLater(call, throwsA(isA<ApiException>()));
        expect(calls, 1);
      });
    }

    testWidgets('POST yang lambat tidak dikirim ulang', (tester) async {
      var calls = 0;
      final api = _client((_) {
        calls++;
        return _json({'ok': true});
      }, delay: const Duration(seconds: 60));
      final pending = api.post('/student/attempts/a/submit');
      await tester.pump(const Duration(seconds: 61));
      expect(await pending, {'ok': true});
      expect(calls, 1);
    });
  });

  test('pesan tanpa internet tidak menyebut laptop atau alamat', () async {
    final api = _client((_) => throw http.ClientException('mati'));
    await expectLater(
      api.get('/a'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Tidak bisa terhubung ke server. Periksa internet HP, lalu coba lagi.',
        ),
      ),
    );
  });

  test('wakeUp diam dan tidak melempar error', () async {
    final seen = <String>[];
    final api = _client((request) {
      seen.add(request.url.path);
      throw http.ClientException('mati');
    });
    await api.wakeUp();
    expect(seen.toSet(), {'/health'});
    expect(api.connecting.value, isFalse);
  });

  group('alamat server', () {
    test('tanpa kompilasi khusus memakai alamat produksi', () {
      expect(ApiConfig.defaultBaseUrl, ApiConfig.productionBaseUrl);
      expect(ApiConfig.productionBaseUrl, startsWith('https://'));
    });

    test('nama domain tanpa skema dianggap https tanpa port', () {
      expect(
        ApiConfig.normalize('aprevo.onrender.com'),
        'https://aprevo.onrender.com',
      );
      expect(ApiConfig.normalize('localhost'), 'http://localhost:8000');
      expect(ApiConfig.normalize('192.168.1.7'), 'http://192.168.1.7:8000');
    });
  });

  group('menu pengembang', () {
    Future<void> tapRow(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.text('Tentang APREVO'));
        await tester.pump();
      }
    }

    testWidgets('alamat server tidak tampil, menu terbuka setelah 7 ketukan', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(testApp(const Scaffold(body: AboutAprevoRow())));
      expect(find.textContaining('Alamat server'), findsNothing);
      expect(find.textContaining('http'), findsNothing);

      await tapRow(tester, 3);
      expect(_announced(tester).last, startsWith('APREVO, aplikasi belajar'));

      await tapRow(tester, 1);
      expect(_announced(tester), [
        'Ketuk 3 kali lagi untuk membuka menu pengembang',
      ]);
      await tapRow(tester, 2);
      expect(_announced(tester).last, contains('Ketuk 1 kali lagi'));
      expect(find.byType(ServerSettingsScreen), findsNothing);

      await tapRow(tester, 1);
      await tester.pumpAndSettle();
      expect(find.byType(ServerSettingsScreen), findsOneWidget);
      expect(find.text('Menu pengembang'), findsOneWidget);
      handle.dispose();
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const Text('Isi');
}
