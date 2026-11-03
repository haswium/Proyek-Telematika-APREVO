import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/services/api_client.dart';
import 'package:aprevo/theme/app_theme.dart';

const String fakeBaseUrl = 'http://tes:8000';

/// Respons JSON (UTF-8).
http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Body JSON sebuah permintaan.
Map<String, dynamic> jsonBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

/// Server tiruan: kunci "METODE /path", nilai fungsi yang membuat respons.
/// Permintaan yang masuk dicatat di [requests].
class FakeServer {
  FakeServer(this.routes, {this.delay});

  final Map<String, Object Function(http.Request request)> routes;

  /// Jeda sebelum menjawab, untuk menguji pesan "sedang memuat".
  final Duration? delay;
  final List<http.Request> requests = [];

  /// Body JSON permintaan terakhir ke [key].
  Map<String, dynamic> bodyOf(String key) {
    final r = requests.lastWhere((r) => '${r.method} ${r.url.path}' == key);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (delay != null) await Future<void>.delayed(delay!);
    final key = '${request.method} ${request.url.path}';
    final route = routes[key];
    if (route == null) {
      return jsonResponse({'detail': 'Tidak ada rute $key di tes'}, 404);
    }
    final result = route(request);
    if (result is http.Response) return result;
    return jsonResponse(result);
  }

  /// Memasang server ini ke [store] selama satu tes.
  void install() {
    final previous = store.api;
    store.api = ApiClient(
      client: MockClient(_handle),
      baseUrl: () => fakeBaseUrl,
      token: () async => 'token-tes',
    );
    addTearDown(() => store.api = previous);
  }
}

/// Server yang tidak bisa dihubungi.
void installUnreachableServer() {
  final previous = store.api;
  store.api = ApiClient(
    client: MockClient((_) async => throw http.ClientException('mati')),
    baseUrl: () => fakeBaseUrl,
  );
  addTearDown(() => store.api = previous);
}

/// Sama seperti AprevoApp, dengan animasi dimatikan (aturan APREVO:
/// animasi berhenti kalau disableAnimations aktif) supaya pumpAndSettle
/// tidak menunggu animasi berulang.
Widget testApp(Widget home) => MaterialApp(
  theme: buildAprevoTheme(),
  locale: const Locale('id', 'ID'),
  supportedLocales: const [Locale('id', 'ID')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: home,
);

/// Pesan di liveRegion: TalkBack membacakannya begitu muncul.
void expectLive(WidgetTester tester, String message) {
  expect(
    tester.getSemantics(find.bySemanticsLabel(message)),
    matchesSemantics(label: message, isLiveRegion: true),
  );
}

Future<void> tapAndPump(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Layar tes dibuat tinggi supaya ListView membangun semua tombol.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
