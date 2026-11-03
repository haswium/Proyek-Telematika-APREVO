import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, User;

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/choose_role_screen.dart';
import 'package:aprevo/screens/login_screen.dart';
import 'package:aprevo/screens/student/onboarding_screen.dart';
import 'package:aprevo/services/google_auth.dart';
import 'package:aprevo/widgets/common.dart';

import 'fake_server.dart';

User _user([Map<String, dynamic>? metadata]) => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: metadata,
  aud: 'authenticated',
  email: 'budi@gmail.com',
  createdAt: '2026-11-04T00:00:00Z',
);

class _FakeGoogleAuth extends GoogleAuth {
  _FakeGoogleAuth({this.opens = true});

  final bool opens;
  final results = StreamController<User>.broadcast();
  final saved = <Map<String, String>>[];
  int opened = 0;
  Object? saveError;

  @override
  Future<bool> open() async {
    opened++;
    return opens;
  }

  @override
  Stream<User> get signedIn => results.stream;

  @override
  Future<User> saveProfile({required String name, required String role}) async {
    if (saveError != null) throw saveError!;
    saved.add({'name': name, 'role': role});
    return _user({'name': name, 'role': role});
  }
}

_FakeGoogleAuth _install({bool online = true, bool opens = true}) {
  final previous = store.googleAuth;
  final fake = _FakeGoogleAuth(opens: opens);
  store.googleAuth = fake;
  store.online = online;
  addTearDown(() {
    store.googleAuth = previous;
    store.online = false;
    store.currentUser = null;
  });
  return fake;
}

List<String> _announced(WidgetTester tester) => [
  for (final event in tester.takeAnnouncements()) event.message,
];

void _lifecycle(WidgetTester tester, AppLifecycleState state) =>
    tester.binding.handleAppLifecycleStateChanged(state);

Future<void> _tapGoogle(WidgetTester tester) async {
  await tapAndPump(tester, find.text('Masuk dengan Google'));
  await tester.pump();
}

Future<void> _leaveAndReturn(WidgetTester tester) async {
  _lifecycle(tester, AppLifecycleState.inactive);
  _lifecycle(tester, AppLifecycleState.hidden);
  _lifecycle(tester, AppLifecycleState.paused);
  await tester.pump();
  _lifecycle(tester, AppLifecycleState.hidden);
  _lifecycle(tester, AppLifecycleState.inactive);
  _lifecycle(tester, AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  group('layar masuk', () {
    testWidgets('mode demo hanya menampilkan pesan belum tersambung', (
      tester,
    ) async {
      final fake = _install(online: false);
      await tester.pumpWidget(testApp(const LoginScreen()));

      await _tapGoogle(tester);

      expect(find.textContaining('akan aktif setelah'), findsOneWidget);
      expect(fake.opened, 0);
    });

    testWidgets('tersambung: membuka browser tanpa pesan demo', (tester) async {
      final fake = _install();
      await tester.pumpWidget(testApp(const LoginScreen()));

      await _tapGoogle(tester);

      expect(fake.opened, 1);
      expect(find.textContaining('akan aktif setelah'), findsNothing);
      expect(_announced(tester), ['Membuka halaman login Google']);
    });

    testWidgets('tombol Lupa password tidak tampil', (tester) async {
      _install();
      await tester.pumpWidget(testApp(const LoginScreen()));

      expect(find.textContaining('Lupa password'), findsNothing);
    });

    testWidgets('browser tidak bisa dibuka: error dibacakan', (tester) async {
      _install(opens: false);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(testApp(const LoginScreen()));

      await _tapGoogle(tester);

      expectLive(tester, 'Halaman login Google tidak bisa dibuka. Coba lagi.');
      handle.dispose();
    });

    testWidgets('kembali tanpa login: diumumkan dibatalkan', (tester) async {
      _install();
      await tester.pumpWidget(testApp(const LoginScreen()));
      await _tapGoogle(tester);
      _announced(tester);

      await _leaveAndReturn(tester);
      expect(_announced(tester), isEmpty);
      await tester.pump(kGoogleReturnGrace);

      expect(_announced(tester), ['Login Google dibatalkan']);
    });

    testWidgets('hasil yang datang saat jeda tidak dianggap batal', (
      tester,
    ) async {
      final fake = _install();
      await tester.pumpWidget(testApp(const LoginScreen()));
      await _tapGoogle(tester);
      _announced(tester);

      await _leaveAndReturn(tester);
      fake.results.add(_user());
      await tester.pumpAndSettle();
      await tester.pump(kGoogleReturnGrace);

      expect(_announced(tester), ['Berhasil masuk']);
      expect(find.byType(ChooseRoleScreen), findsOneWidget);
    });

    testWidgets('hasil yang terlambat tetap diterima setelah batal', (
      tester,
    ) async {
      final fake = _install();
      await tester.pumpWidget(testApp(const LoginScreen()));
      await _tapGoogle(tester);
      await _leaveAndReturn(tester);
      await tester.pump(kGoogleReturnGrace);
      _announced(tester);

      fake.results.add(_user());
      await tester.pumpAndSettle();

      expect(_announced(tester), ['Berhasil masuk']);
      expect(find.byType(ChooseRoleScreen), findsOneWidget);
    });

    testWidgets('akun yang sudah punya peran langsung ke berandanya', (
      tester,
    ) async {
      final fake = _install();
      await tester.pumpWidget(testApp(const LoginScreen()));
      await _tapGoogle(tester);

      fake.results.add(_user({'name': 'Budi', 'role': 'student'}));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseRoleScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('masuk yang tidak dimulai dari tombol Google diabaikan', (
      tester,
    ) async {
      final fake = _install();
      await tester.pumpWidget(testApp(const LoginScreen()));

      fake.results.add(_user());
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(_announced(tester), isEmpty);
    });

    testWidgets('Google menolak: dibatalkan tanpa menunggu jeda', (
      tester,
    ) async {
      final fake = _install();
      await tester.pumpWidget(testApp(const LoginScreen()));
      await _tapGoogle(tester);
      _announced(tester);

      fake.results.addError(const AuthException('access_denied'));
      await tester.pump();

      expect(_announced(tester), ['Login Google dibatalkan']);
    });

    testWidgets('kegagalan lain dibacakan sebagai error', (tester) async {
      final fake = _install();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(testApp(const LoginScreen()));
      await _tapGoogle(tester);

      fake.results.addError(const AuthException('server rusak'));
      await tester.pump();

      expectLive(tester, 'Login Google gagal. Coba lagi.');
      handle.dispose();
    });
  });

  group('layar pilih peran', () {
    FakeServer serverAnswering(String role) => FakeServer({
      'POST /me/role': (_) => {'name': 'Budi Santoso', 'role': role},
    })..install();

    testWidgets('judul dan tombol punya label jelas', (tester) async {
      _install(online: false);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(testApp(const ChooseRoleScreen()));

      expect(
        tester.getSemantics(find.text('Pilih peran')),
        matchesSemantics(label: 'Pilih peran', isHeader: true),
      );
      for (final role in ['Guru', 'Siswa']) {
        expect(
          find.bySemanticsLabel(
            RegExp('^$role\\. .*Peran tidak bisa diganti setelah dipilih\\.\$'),
          ),
          findsOneWidget,
        );
      }
      handle.dispose();
    });

    testWidgets('memilih Siswa menyimpan peran dan nama dari backend', (
      tester,
    ) async {
      final fake = _install(online: false);
      final server = serverAnswering('student');
      await tester.pumpWidget(testApp(const ChooseRoleScreen()));

      await tapAndPump(tester, find.text('Siswa'));
      await tester.pumpAndSettle();

      expect(server.bodyOf('POST /me/role'), {'role': 'student'});
      expect(fake.saved, [
        {'name': 'Budi Santoso', 'role': 'student'},
      ]);
      expect(store.currentUser!.role, UserRole.student);
      expect(store.currentUser!.roleChosen, isTrue);
      expect(find.byType(ChooseRoleScreen), findsNothing);
    });

    testWidgets('peran lama yang berlaku, dan itu diumumkan', (tester) async {
      final fake = _install(online: false);
      serverAnswering('student');
      await tester.pumpWidget(testApp(const ChooseRoleScreen()));

      await tapAndPump(tester, find.text('Guru'));
      await tester.pumpAndSettle();

      expect(fake.saved.single['role'], 'student');
      expect(store.currentUser!.role, UserRole.student);
      expect(
        _announced(tester),
        contains('Akun ini sudah terdaftar sebagai Siswa'),
      );
    });

    testWidgets('server gagal: error dibacakan dan bisa dicoba lagi', (
      tester,
    ) async {
      _install(online: false);
      installUnreachableServer();
      await tester.pumpWidget(testApp(const ChooseRoleScreen()));

      await tapAndPump(tester, find.text('Siswa'));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseRoleScreen), findsOneWidget);
      expect(store.currentUser, isNull);
      expect(find.byType(ErrorCard), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNotNull,
      );
    });

    testWidgets('metadata gagal disimpan: tetap di layar ini', (tester) async {
      final fake = _install(online: false);
      fake.saveError = const AuthException('rate limit');
      serverAnswering('student');
      await tester.pumpWidget(testApp(const ChooseRoleScreen()));

      await tapAndPump(tester, find.text('Siswa'));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseRoleScreen), findsOneWidget);
      expect(store.currentUser, isNull);
    });

    testWidgets('Batal dan keluar kembali ke layar sambutan', (tester) async {
      _install(online: false);
      await tester.pumpWidget(testApp(const ChooseRoleScreen()));

      await tapAndPump(tester, find.text('Batal dan keluar'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ChooseRoleScreen), findsNothing);
    });
  });

  test('alamat kembali sama dengan intent-filter', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final redirect = Uri.parse(kAuthRedirectUrl);

    expect(
      manifest,
      contains(
        '<data android:scheme="${redirect.scheme}" '
        'android:host="${redirect.host}"/>',
      ),
    );
    expect(manifest, contains('android:name="flutter_deeplinking_enabled"'));
  });
}
