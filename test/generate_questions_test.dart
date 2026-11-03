import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/teacher/generate_questions_screen.dart';
import 'package:aprevo/screens/teacher/material_editor_screen.dart';
import 'package:aprevo/screens/teacher/question_form_screen.dart';

import 'fake_server.dart';

const _url = '/teacher/materials/m1/generate-questions';
const _post = 'POST $_url';
const _get = 'GET $_url';
const _delete = 'DELETE $_url';

final _subject = Subject(id: 's1', name: 'Kelas 2');

Map<String, dynamic> _ai(String prompt, {String? explanation = 'Karena.'}) => {
  'type': 'multiple_choice',
  'question': prompt,
  'explanation': explanation,
  'options': [
    {'text': 'Merah', 'is_correct': false},
    {'text': 'Coklat', 'is_correct': true},
    {'text': 'Biru', 'is_correct': false},
  ],
};

Map<String, dynamic> _job({
  bool running = false,
  int total = 2,
  List<Map<String, dynamic>> questions = const [],
  String? error,
  String? id = 'j1',
}) => {
  'job_id': id,
  'running': running,
  'total': total,
  'done': questions.length,
  'quiz_type': 'multiple_choice',
  'questions': questions,
  'error': error,
};

Map<String, dynamic> _quiz(String kind) => {
  'id': 'q-$kind',
  'title': kind,
  'kind': kind,
  'status': 'upcoming',
  'available_from': '2030-01-01T00:00:00+00:00',
  'deadline_at': '2030-01-02T00:00:00+00:00',
};

/// `statuses`: jawaban GET berurutan. Jawaban terakhir dipakai terus, dan
/// `null` berarti server error.
FakeServer _server({
  List<Map<String, dynamic>?>? statuses,
  bool scheduled = true,
  List<Map<String, dynamic>> saved = const [],
  Object Function()? onStart,
}) {
  final queue = [...?statuses];
  return FakeServer({
    'GET /teacher/subjects/s1/materials': (_) => {
      'materials': [
        {
          'id': 'm1',
          'title': 'ScratchJR',
          'is_published': false,
          'quizzes': scheduled ? [_quiz('pre'), _quiz('post')] : [],
        },
        {'id': 'm2', 'title': 'Menabung', 'is_published': false, 'quizzes': []},
      ],
    },
    'GET /quizzes/q-pre': (_) => {'questions': saved},
    'GET /quizzes/q-post': (_) => {'questions': []},
    'GET /teacher/materials/m1/images': (_) => {'images': []},
    _post: (_) => onStart?.call() ?? _job(running: true),
    _get: (r) {
      if (r.url.queryParameters['test_kind'] != 'pre' || queue.isEmpty) {
        return _job(id: null, total: 0);
      }
      final next = queue.length > 1 ? queue.removeAt(0) : queue.first;
      return next ?? jsonResponse({'detail': 'Gagal'}, 500);
    },
    _delete: (_) => {'message': 'Hasil dihapus'},
    'POST /quizzes/q-pre/questions': (_) => {'questions': []},
  });
}

List<String> _said(WidgetTester tester) => [
  for (final a in tester.takeAnnouncements()) a.message,
];

Future<void> _open(WidgetTester tester, {LessonMaterial? material}) async {
  await tester.pumpWidget(
    testApp(GenerateQuestionsScreen(subject: _subject, material: material)),
  );
  await tester.pumpAndSettle();
}

final _m1 = LessonMaterial(id: 'm1', title: 'ScratchJR', published: false);

Future<void> _openEditor(WidgetTester tester) async {
  await tester.pumpWidget(
    testApp(MaterialEditorScreen(subject: _subject, material: _m1)),
  );
  await tester.pumpAndSettle();
}

/// Belum ada proses atau hasil.
const _empty = <String, dynamic>{
  'job_id': null,
  'running': false,
  'total': 0,
  'questions': <Object>[],
};

Future<void> _poll(WidgetTester tester) async {
  await tester.pump(kQuestionPollInterval);
  await tester.pumpAndSettle();
}

void main() {
  group('Question.fromAi', () {
    test('keempat jenis soal', () {
      final quiz = Question.fromAi(_ai('Warna?'));
      expect(quiz.options, ['Merah', 'Coklat', 'Biru']);
      expect(quiz.correctIndex, 1);
      expect(quiz.aiGenerated, isTrue);
      expect(quiz.toApi(GameType.quiz)['options'], [
        {'text': 'Merah', 'is_correct': false},
        {'text': 'Coklat', 'is_correct': true},
        {'text': 'Biru', 'is_correct': false},
      ]);

      final truth = Question.fromAi({
        'type': 'true_false',
        'question': 'Benar?',
        'explanation': 'Ya.',
        'correct_answer': false,
      });
      expect(truth.correctIndex, 1);
      expect(truth.toApi(GameType.trueFalse)['correct_answer'], isFalse);

      final text = Question.fromAi({
        'type': 'text',
        'question': 'Warna?',
        'explanation': 'Ya.',
        'answers': [
          {'answer': 'coklat'},
          {'answer': 'cokelat'},
        ],
      });
      expect(text.answerText, 'coklat; cokelat');

      final order = Question.fromAi({
        'type': 'ordering',
        'question': 'Urutkan',
        'explanation': 'Ya.',
        'items': [
          {'text': 'Dua', 'correct_order': 2},
          {'text': 'Satu', 'correct_order': 1},
        ],
      });
      expect(order.options, ['Satu', 'Dua']);
    });
  });

  testWidgets('dibuka dari halaman kelas: pilih materi, dan bisa diganti', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    _server().install();
    await _open(tester);

    final row = find.bySemanticsLabel('Pilih materi ScratchJR');
    expect(row, findsOneWidget);
    expect(find.bySemanticsLabel('Pilih materi Menabung'), findsOneWidget);
    await tester.tap(find.text('ScratchJR'));
    await tester.pumpAndSettle();
    expect(_said(tester), contains('Materi ScratchJR dipilih.'));
    expect(find.text('Buat soal Pre-test'), findsOneWidget);

    await tester.tap(find.text('Ganti materi'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih materi'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('mulai, selesai, dan hasil masuk draf walaupun layar ditutup', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    final server = _server(
      statuses: [
        _empty,
        _job(running: true),
        _job(questions: [_ai('Soal satu'), _ai('Soal dua')]),
        _empty,
      ],
    )..install();
    await _open(tester, material: _m1);
    _said(tester);

    await tester.tap(find.text('Post-test'));
    await tester.pumpAndSettle();
    expect(find.text('Buat soal Post-test'), findsOneWidget);
    await tester.tap(find.text('Pre-test'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Benar atau Salah'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();

    expect(server.bodyOf(_post), {
      'test_kind': 'pre',
      'quiz_type': 'multiple_choice',
      'total_questions': 2,
    });
    expect(_said(tester), [
      'Sedang membuat soal Pre-test. Hasilnya diumumkan saat selesai atau '
          'gagal.',
    ]);
    expect(find.text('Sedang membuat soal Pre-test'), findsOneWidget);
    expect(find.text('Sedang membuat soal...'), findsOneWidget);

    // Masih berjalan: tidak ada pengumuman baru.
    await _poll(tester);
    expect(_said(tester), isEmpty);
    expect(store.questionDrafts('m1', TestKind.pre), isEmpty);

    // Guru pindah layar; pemantauan tetap berjalan di store.
    await tester.pumpWidget(testApp(const SizedBox()));
    await _poll(tester);
    expect(_said(tester), ['2 soal draf Pre-test siap. Periksa, lalu simpan.']);
    final drafts = store.questionDrafts('m1', TestKind.pre);
    expect([for (final q in drafts) q.prompt], ['Soal satu', 'Soal dua']);
    expect(store.draftType('m1'), GameType.quiz);
    expect(server.requests.where((r) => r.method == 'DELETE').length, 1);
    handle.dispose();
  });

  testWidgets('hasil tidak masuk dua kali walaupun penghapusan gagal', (
    tester,
  ) async {
    tallScreen(tester);
    final done = _job(questions: [_ai('Soal satu')]);
    final server = FakeServer({
      'GET /teacher/subjects/s1/materials': (_) => {
        'materials': [
          {
            'id': 'm1',
            'title': 'ScratchJR',
            'is_published': false,
            'quizzes': [_quiz('pre')],
          },
        ],
      },
      'GET /quizzes/q-pre': (_) => {'questions': []},
      'GET /teacher/materials/m1/images': (_) => {'images': []},
      _get: (r) => r.url.queryParameters['test_kind'] == 'pre'
          ? done
          : _job(id: null, total: 0),
      _delete: (_) => jsonResponse({'detail': 'Gagal'}, 500),
    })..install();
    await store.resumeQuestionGeneration('m1');
    await store.resumeQuestionGeneration('m1');
    expect(store.questionDrafts('m1', TestKind.pre).length, 1);
    expect(server.requests.where((r) => r.method == 'DELETE').length, 1);
  });

  testWidgets('gagal: alasan diumumkan dan tidak ada draf', (tester) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    _server(
      statuses: [
        _empty,
        _job(error: 'AI gagal membuat soal. Coba lagi'),
        _empty,
      ],
    ).install();
    await _open(tester, material: _m1);
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();
    _said(tester);

    await _poll(tester);
    const message =
        'Soal Pre-test belum dibuat. AI gagal membuat soal. Coba lagi';
    expect(_said(tester), [message]);
    expect(find.text(message), findsOneWidget);
    expect(store.questionDrafts('m1', TestKind.pre), isEmpty);
    expect(find.text('Periksa draf Pre-test'), findsNothing);
    // Bisa dicoba lagi.
    expect(find.text('Buat soal Pre-test'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('gagal di tengah: soal yang sudah jadi tetap masuk draf', (
    tester,
  ) async {
    tallScreen(tester);
    _server(
      statuses: [
        _empty,
        _job(
          total: 15,
          questions: [_ai('Soal satu')],
          error: 'AI gagal membuat soal. Coba lagi',
        ),
        _empty,
      ],
    ).install();
    await _open(tester, material: _m1);
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();
    _said(tester);

    await _poll(tester);
    expect(_said(tester), [
      '1 dari 15 soal draf Pre-test dibuat. AI gagal membuat soal. Coba lagi',
    ]);
    expect(store.questionDrafts('m1', TestKind.pre).length, 1);
    expect(find.text('Periksa draf Pre-test'), findsOneWidget);
  });

  testWidgets('backend dimulai ulang di tengah proses: alasannya diumumkan', (
    tester,
  ) async {
    tallScreen(tester);
    _server(statuses: [_empty, _empty]).install();
    await _open(tester, material: _m1);
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();
    _said(tester);
    await _poll(tester);
    expect(_said(tester), [
      'Pembuatan soal Pre-test terhenti karena server dimulai ulang. Coba lagi.',
    ]);
    expect(store.isGeneratingQuestions('m1'), isFalse);
  });

  testWidgets('pemeriksaan gagal terus: guru diberi tahu, lalu berhenti', (
    tester,
  ) async {
    tallScreen(tester);
    final server = _server(statuses: [_empty, null])..install();
    await _open(tester, material: _m1);
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();
    _said(tester);

    await _poll(tester);
    await _poll(tester);
    expect(_said(tester), isEmpty);
    await _poll(tester);
    final message = _said(tester);
    expect(message.single, startsWith('Status soal Pre-test tidak bisa'));
    final before = server.requests.length;
    await tester.pump(kQuestionPollInterval * 3);
    expect(server.requests.length, before);
  });

  testWidgets('jumlah soal di luar batas ditolak dengan liveRegion', (
    tester,
  ) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    final server = _server()..install();
    await _open(tester, material: _m1);
    for (final value in ['0', '31', 'lima', '']) {
      await tester.enterText(find.byType(TextField), value);
      await tester.tap(find.text('Buat soal Pre-test'));
      await tester.pumpAndSettle();
      expectLive(tester, 'Jumlah soal harus 1 sampai 30.');
    }
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
    handle.dispose();
  });

  testWidgets('penolakan server dibacakan dengan liveRegion', (tester) async {
    tallScreen(tester);
    final handle = tester.ensureSemantics();
    _server(
      onStart: () => jsonResponse({
        'detail': 'Materi belum memiliki teks yang dapat digunakan.',
      }, 422),
    ).install();
    await _open(tester, material: _m1);
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();
    expectLive(tester, 'Materi belum memiliki teks yang dapat digunakan.');
    expect(store.isGeneratingQuestions('m1'), isFalse);
    handle.dispose();
  });

  testWidgets('kuis tanpa jadwal: harus mengatur jadwal dulu', (tester) async {
    tallScreen(tester);
    final server = _server(scheduled: false)..install();
    await _open(tester, material: _m1);
    expect(find.text('Atur jadwal Pre-test'), findsOneWidget);
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('jenis soal terkunci kalau sudah ada soal tersimpan', (
    tester,
  ) async {
    tallScreen(tester);
    final server = _server(
      saved: [
        {
          'id': 'x',
          'type': 'true_false',
          'question': 'Lama',
          'correct_answer': true,
        },
      ],
    )..install();
    await _open(tester, material: _m1);
    expect(find.textContaining('Jenis soal terkunci'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Quiz'),
    );
    expect(chip.onSelected, isNull);
    await tester.tap(find.text('Buat soal Pre-test'));
    await tester.pumpAndSettle();
    expect(server.bodyOf(_post)['quiz_type'], 'true_false');
    store.resetQuestionGeneration();
  });

  group('draf di Kelola materi', () {
    testWidgets('hasil yang belum diambil masuk saat layar dibuka, lalu bisa '
        'diperiksa, dihapus, dan disimpan', (tester) async {
      tallScreen(tester);
      final handle = tester.ensureSemantics();
      final server = _server(
        statuses: [
          _job(questions: [_ai('Soal satu'), _ai('Soal dua')]),
          _empty,
        ],
      )..install();
      await _openEditor(tester);

      expect(
        _said(tester),
        contains('2 soal draf Pre-test siap. Periksa, lalu simpan.'),
      );
      expect(
        find.bySemanticsLabel(
          'Pre-test draf soal 1, belum tersimpan. Soal satu. Jawaban benar: '
          'Coklat. Penjelasan: Karena.. Ketuk untuk ubah',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Jenis soal terkunci'), findsOneWidget);

      await tester.tap(find.byTooltip('Hapus draf Pre-test soal 1'));
      await tester.pumpAndSettle();
      expect(_said(tester), contains('Draf Pre-test soal 1 dihapus.'));
      expect(find.text('Soal satu'), findsNothing);

      await tester.tap(find.text('Simpan 1 soal Pre-test ke server'));
      await tester.pumpAndSettle();
      final body = server.bodyOf('POST /quizzes/q-pre/questions');
      final saved = (body['questions'] as List).single as Map<String, dynamic>;
      expect(saved['question'], 'Soal dua');
      expect(saved['explanation'], 'Karena.');
      expect(store.questionDrafts('m1', TestKind.pre), isEmpty);
      // Pesan "periksa, lalu simpan" tidak relevan lagi.
      expect(store.questionGeneration('m1', TestKind.pre), isNull);
      handle.dispose();
    });

    testWidgets('draf tetap ada setelah layar ditutup dan dibuka lagi', (
      tester,
    ) async {
      tallScreen(tester);
      _server(
        statuses: [
          _job(questions: [_ai('Soal satu')]),
          _empty,
        ],
      ).install();
      await _openEditor(tester);
      await tester.pumpWidget(const SizedBox());
      await _openEditor(tester);
      expect(find.text('Soal satu'), findsOneWidget);
    });

    testWidgets('proses yang berjalan dilanjutkan setelah aplikasi dibuka '
        'lagi', (tester) async {
      tallScreen(tester);
      _server(
        statuses: [
          _job(running: true),
          _empty,
          _job(running: true),
          _job(questions: [_ai('Soal satu')]),
          _empty,
        ],
      ).install();
      await _openEditor(tester);
      expect(find.text('Sedang membuat soal Pre-test'), findsOneWidget);
      await _poll(tester);
      await _poll(tester);
      expect(find.text('Soal satu'), findsOneWidget);
      expect(find.text('Sedang membuat soal Pre-test'), findsNothing);
    });
  });

  group('form draf AI', () {
    Future<Question?> edit(WidgetTester tester, Question initial) async {
      Question? result;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<Question>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuestionFormScreen(
                      type: GameType.quiz,
                      initial: initial,
                    ),
                  ),
                );
              },
              child: const Text('Buka'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan soal'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('tiga pilihan boleh disimpan dan jawaban benarnya tetap', (
      tester,
    ) async {
      tallScreen(tester);
      final result = await edit(tester, Question.fromAi(_ai('Warna?')));
      expect(result?.options, ['Merah', 'Coklat', 'Biru']);
      expect(result?.correctIndex, 1);
      expect(result?.aiGenerated, isTrue);
    });

    testWidgets('penjelasan wajib diisi', (tester) async {
      tallScreen(tester);
      final result = await edit(
        tester,
        Question.fromAi(_ai('Warna?', explanation: null)),
      );
      expect(result, isNull);
      expect(find.text('Penjelasan jawaban belum diisi.'), findsOneWidget);
    });

    testWidgets('soal ketikan guru tetap wajib empat pilihan dan penjelasan '
        'boleh kosong', (tester) async {
      tallScreen(tester);
      final result = await edit(
        tester,
        Question(prompt: 'Warna?', options: const ['A', 'B', 'C']),
      );
      expect(result, isNull);
      expect(find.text('Isi keempat pilihan jawaban.'), findsOneWidget);
    });
  });
}
