// Materi dari format lain: edit teks halaman, pemutar audio, dan status
// konversi di halaman kelas.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/material_file.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/section_reader_screen.dart';
import 'package:aprevo/screens/teacher/section_text_screen.dart';
import 'package:aprevo/screens/teacher/subject_detail_screen.dart';
import 'package:aprevo/widgets/audio_player_card.dart';

import 'fake_server.dart';

const _table = '[[tabel:{"title": "T", "columns": ["A"], "rows": [["1"]]}]]';

class _FakePlayer implements LessonAudioPlayer {
  final positionsController = StreamController<Duration>.broadcast();
  final completedController = StreamController<void>.broadcast();
  final calls = <String>[];

  @override
  Stream<Duration> get positions => positionsController.stream;

  @override
  Stream<void> get completed => completedController.stream;

  @override
  Future<void> play(String url, Duration from) async =>
      calls.add('play $url ${from.inSeconds}');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek ${position.inSeconds}');

  @override
  Future<void> dispose() async {
    await positionsController.close();
    await completedController.close();
  }
}

_FakePlayer _installPlayer() {
  final player = _FakePlayer();
  final previous = createLessonAudioPlayer;
  createLessonAudioPlayer = () => player;
  addTearDown(() => createLessonAudioPlayer = previous);
  return player;
}

void main() {
  group('teks halaman yang bisa diedit', () {
    const content = 'Pembuka.\n[[gambar:foto-1]]\nTengah.\n$_table\nPenutup.';

    test('penanda diganti baris pendek lalu dikembalikan', () {
      final editable = EditablePageText.fromContent(content);
      expect(
        editable.text,
        'Pembuka.\n[Gambar 1]\nTengah.\n[Tabel 1]\nPenutup.',
      );
      expect(
        editable.restore(
          'Pembuka baru.\n[Gambar 1]\nTengah.\n[Tabel 1]\n- Butir',
        ),
        'Pembuka baru.\n[[gambar:foto-1]]\nTengah.\n$_table\n- Butir',
      );
    });

    test('penanda hilang, berulang, atau tertukar ditolak', () {
      final editable = EditablePageText.fromContent(content);
      expect(editable.restore('Tanpa penanda.'), isNull);
      expect(editable.restore('[Tabel 1]\n[Gambar 1]'), isNull);
      expect(editable.restore('[Gambar 1]\n[Gambar 1]\n[Tabel 1]'), isNull);
    });

    test('halaman tanpa gambar dan tabel bebas diedit', () {
      final editable = EditablePageText.fromContent('Satu.\nDua.');
      expect(editable.hasMarkers, isFalse);
      expect(editable.restore('Tiga.'), 'Tiga.');
    });
  });

  group('editor teks halaman', () {
    final section = MaterialSection(
      id: 's1',
      position: 1,
      title: 'Transkrip',
      content: 'Kalimat salah dengar.\n[[gambar:foto-1]]',
    );

    Future<FakeServer> open(WidgetTester tester) async {
      tallScreen(tester);
      final server = FakeServer({
        'PATCH /teacher/materials/m1/sections/s1': (_) => {
          'section': {'id': 's1', 'title': 'Transkrip', 'content': 'x'},
        },
      })..install();
      await tester.pumpWidget(testApp(const Text('Daftar')));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute(
              builder: (_) => SectionTextEditorScreen(
                materialId: 'm1',
                section: section,
                number: 1,
              ),
            ),
          );
      await tester.pumpAndSettle();
      return server;
    }

    testWidgets('simpan: penanda asli dikirim kembali', (tester) async {
      final server = await open(tester);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(kSectionMarkerHelp), findsOneWidget);
      expect(find.text('Kalimat salah dengar.\n[Gambar 1]'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Teks halaman'),
        'Kalimat yang benar.\n[Gambar 1]',
      );
      await tapAndPump(tester, find.text('Simpan halaman'));
      await tester.pumpAndSettle();

      expect(server.bodyOf('PATCH /teacher/materials/m1/sections/s1'), {
        'title': 'Transkrip',
        'content': 'Kalimat yang benar.\n[[gambar:foto-1]]',
      });
      expect(find.text('Daftar'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('baris gambar dihapus: error, tidak dikirim', (tester) async {
      final server = await open(tester);
      final handle = tester.ensureSemantics();
      await tester.enterText(
        find.widgetWithText(TextField, 'Teks halaman'),
        'Gambarnya terhapus.',
      );
      await tapAndPump(tester, find.text('Simpan halaman'));
      expectLive(
        tester,
        'Baris [Gambar] atau [Tabel] terhapus atau urutannya berubah. '
        'Kembalikan barisnya, lalu simpan lagi.',
      );
      expect(server.requests, isEmpty);
      handle.dispose();
    });
  });

  group('pemutar audio', () {
    Future<FakeServer> open(WidgetTester tester) async {
      final server = FakeServer({
        'GET /materials/m1/audio': (_) => {
          'url': 'https://tanda.test/a.mp3',
          'expires_in': 3600,
          'duration_seconds': 300,
        },
      })..install();
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: AudioPlayerCard(materialId: 'm1', durationSeconds: 300),
          ),
        ),
      );
      return server;
    }

    testWidgets('tombol berlabel jelas, tidak diputar otomatis', (
      tester,
    ) async {
      final player = _installPlayer();
      final handle = tester.ensureSemantics();
      await open(tester);

      for (final label in ['Putar audio', 'Mundur 10 detik', 'Maju 10 detik']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(label: label, isButton: true, hasTapAction: true),
          reason: label,
        );
      }
      expect(
        find.bySemanticsLabel('Posisi audio: 0 detik dari 5 menit'),
        findsOneWidget,
      );
      expect(player.calls, isEmpty);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('putar, jeda, mundur, maju diumumkan', (tester) async {
      final player = _installPlayer();
      final handle = tester.ensureSemantics();
      await open(tester);

      await tapAndPump(tester, find.text('Putar audio'));
      await tester.pumpAndSettle();
      expect(player.calls, ['play https://tanda.test/a.mp3 0']);
      expect(find.text('Jeda audio'), findsOneWidget);

      player.positionsController.add(const Duration(seconds: 80));
      await tester.pump();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Posisi audio: 1 menit 20 detik dari 5 menit'),
        findsOneWidget,
      );
      tester.takeAnnouncements();

      await tapAndPump(tester, find.text('Mundur 10 detik'));
      await tester.pumpAndSettle();
      expect(player.calls.last, 'seek 70');
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Posisi 1 menit 10 detik dari 5 menit.'),
      );

      await tapAndPump(tester, find.text('Maju 10 detik'));
      await tester.pumpAndSettle();
      expect(player.calls.last, 'seek 80');

      await tapAndPump(tester, find.text('Jeda audio'));
      await tester.pumpAndSettle();
      expect(player.calls.last, 'pause');
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Audio dijeda di 1 menit 20 detik dari 5 menit.'),
      );
      expect(find.text('Putar audio'), findsOneWidget);

      player.completedController.add(null);
      await tester.pump();
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Audio selesai.'),
      );
      handle.dispose();
    });

    testWidgets('mundur tidak melewati awal', (tester) async {
      final player = _installPlayer();
      await open(tester);
      await tapAndPump(tester, find.text('Mundur 10 detik'));
      await tester.pumpAndSettle();
      // Belum diputar: posisi saja yang berubah, tanpa memanggil pemutar.
      expect(player.calls, isEmpty);
      expect(find.text('0 detik dari 5 menit'), findsOneWidget);
    });

    testWidgets('audio gagal dimuat: error dibacakan', (tester) async {
      _installPlayer();
      FakeServer({
        'GET /materials/m1/audio': (_) =>
            jsonResponse({'detail': 'Materi ini tidak punya audio'}, 404),
      }).install();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(const Scaffold(body: AudioPlayerCard(materialId: 'm1'))),
      );
      await tapAndPump(tester, find.text('Putar audio'));
      await tester.pumpAndSettle();
      expectLive(
        tester,
        'Audio belum bisa diputar. Materi ini tidak punya audio.',
      );
      handle.dispose();
    });
  });

  testWidgets('layar baca materi audio menampilkan pemutar', (tester) async {
    _installPlayer();
    tallScreen(tester);
    FakeServer({
      'GET /materials/m1/sections': (_) => {
        'material': {
          'id': 'm1',
          'title': 'Rekaman',
          'source_type': 'audio',
          'has_audio': true,
          'audio_duration_seconds': 65,
        },
        'sections': [
          {
            'id': 's1',
            'position': 1,
            'title': 'Transkrip',
            'content': 'Selamat pagi anak-anak.',
          },
        ],
        'images': [],
      },
    }).install();
    await tester.pumpWidget(
      testApp(
        const MaterialSectionsScreen(
          materialId: 'm1',
          materialTitle: 'Rekaman',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapAndPump(tester, find.text('Halaman 1: Transkrip'));
    await tester.pumpAndSettle();

    expect(find.byType(AudioPlayerCard), findsOneWidget);
    expect(find.text('0 detik dari 1 menit 5 detik'), findsOneWidget);
    expect(find.text('Selamat pagi anak-anak.'), findsOneWidget);
  });

  testWidgets('materi bukan audio: tanpa pemutar', (tester) async {
    tallScreen(tester);
    FakeServer({
      'GET /materials/m1/sections': (_) => {
        'material': {'id': 'm1', 'title': 'Peta'},
        'sections': [
          {'id': 's1', 'position': 1, 'title': 'Peta', 'content': 'Isi.'},
        ],
        'images': [],
      },
    }).install();
    await tester.pumpWidget(
      testApp(
        const MaterialSectionsScreen(materialId: 'm1', materialTitle: 'Peta'),
      ),
    );
    await tester.pumpAndSettle();
    await tapAndPump(tester, find.text('Halaman 1: Peta'));
    await tester.pumpAndSettle();
    expect(find.byType(AudioPlayerCard), findsNothing);
  });

  testWidgets('halaman kelas: materi diproses dan gagal diproses', (
    tester,
  ) async {
    tallScreen(tester);
    final server = FakeServer({
      'GET /teacher/subjects/s1/materials': (_) => {
        'materials': [
          {
            'id': 'm1',
            'title': 'Rekaman pagi',
            'is_published': false,
            'quizzes': [],
            'conversion': {
              'status': 'processing',
              'step':
                  'Membuat transkrip audio dengan AI. Bisa sampai '
                  'beberapa menit.',
            },
          },
          {
            'id': 'm2',
            'title': 'Slide lama',
            'is_published': false,
            'quizzes': [],
            'conversion': {
              'status': 'failed',
              'error': 'Presentasi PowerPoint tidak bisa dibaca.',
            },
          },
        ],
      },
      'DELETE /teacher/materials/m2': (_) => {'message': 'Materi dihapus'},
    })..install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        SubjectDetailScreen(
          subject: Subject(id: 's1', name: 'IPA'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unggah materi'), findsOneWidget);
    expect(find.text('Sedang diproses'), findsOneWidget);
    expect(
      find.text(
        'Membuat transkrip audio dengan AI. Bisa sampai beberapa menit.',
      ),
      findsOneWidget,
    );
    expect(find.text('Gagal diproses'), findsOneWidget);
    expect(
      find.text('Gagal diproses. Presentasi PowerPoint tidak bisa dibaca.'),
      findsOneWidget,
    );
    // Materi yang belum siap tidak bisa dikelola.
    expect(find.bySemanticsLabel('Kelola materi Rekaman pagi'), findsNothing);

    await tapAndPump(
      tester,
      find.bySemanticsLabel('Hapus materi Slide lama yang gagal diproses'),
    );
    await tester.pump();
    expect(
      server.requests.map((r) => '${r.method} ${r.url.path}'),
      contains('DELETE /teacher/materials/m2'),
    );
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Materi Slide lama yang gagal diproses dihapus.'),
    );
    handle.dispose();
    // Hentikan pemuatan ulang berkala sebelum tes selesai.
    await tester.pumpWidget(const SizedBox());
  });
}
