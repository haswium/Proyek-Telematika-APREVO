import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/models/models.dart';
import 'package:aprevo/screens/student/play_game_screen.dart';
import 'package:aprevo/screens/student/review_screen.dart';
import 'package:aprevo/services/time_format.dart';

import 'fake_server.dart';

final _deadline = DateTime(2026, 11, 3, 21);

QuizInfo _quiz() => QuizInfo(
  id: 'k1',
  kind: TestKind.pre,
  title: 'Pre-test',
  status: QuizStatus.open,
  availableFrom: DateTime(2026, 11, 1, 7),
  deadlineAt: _deadline,
);

Map<String, dynamic> _review({required bool withKey}) => {
  'attempt_id': 'a1',
  'quiz_id': 'k1',
  'quiz_title': 'Pre-test',
  'score': 1,
  'total_questions': 2,
  'deadline_at': isoWithOffset(_deadline),
  if (!withKey) 'discussion_available': false,
  'review': [
    {
      'question_id': 'q1',
      'type': 'multiple_choice',
      'question': 'Di mana fotosintesis terjadi?',
      'is_correct': true,
      'answer': null,
      'options': [
        {
          'option_id': 'o1',
          'text': 'Akar',
          'selected': false,
          if (withKey) 'is_correct': false,
        },
        {
          'option_id': 'o2',
          'text': 'Daun',
          'selected': true,
          if (withKey) 'is_correct': true,
        },
      ],
      if (withKey) 'explanation': 'Daun punya kloroplas.',
    },
    {
      'question_id': 'q2',
      'type': 'true_false',
      'question': 'Akar membuat makanan.',
      'is_correct': false,
      'answer': true,
      if (withKey) 'correct_answer': false,
      if (withKey) 'explanation': null,
    },
  ],
};

void main() {
  testWidgets('kuis: tiap soal hanya benar/salah, lalu hasil', (tester) async {
    tallScreen(tester);
    final server = FakeServer({
      'GET /student/quizzes/k1': (_) => {
        'quiz': {'id': 'k1', 'title': 'Pre-test', 'attempt_limit': null},
        'questions': [
          {
            'id': 'q1',
            'type': 'multiple_choice',
            'question': 'Di mana fotosintesis terjadi?',
            'options': [
              {'id': 'o1', 'text': 'Akar'},
              {'id': 'o2', 'text': 'Daun'},
            ],
          },
          {
            'id': 'q2',
            'type': 'true_false',
            'question': 'Akar membuat makanan.',
          },
        ],
      },
      'POST /quizzes/k1/attempts': (_) => {
        'message': 'Percobaan kuis berhasil dimulai',
        'attempt': {'id': 'a1', 'submitted_at': null},
      },
      'PUT /student/attempts/a1/answers/q1': (_) => {'is_correct': true},
      'PUT /student/attempts/a1/answers/q2': (_) => {'is_correct': false},
      'POST /student/attempts/a1/submit': (_) => {
        'attempt_id': 'a1',
        'correct_count': 1,
        'total_questions': 2,
        'deadline_passed': false,
      },
    })..install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        PlayGameScreen(
          quiz: _quiz(),
          materialTitle: 'Tumbuhan',
          studentName: 'Dimas',
        ),
      ),
    );
    expect(find.bySemanticsLabel('Menyiapkan soal Pre-test.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Soal 1 dari 2'), findsOneWidget);
    // Hanya TalkBack: tidak ada tombol suara aplikasi.
    expect(find.textContaining('Dengarkan'), findsNothing);

    await tapAndPump(tester, find.bySemanticsLabel('Pilihan B, Daun'));
    await tapAndPump(tester, find.text('Periksa Jawaban'));
    await tester.pumpAndSettle();
    expect(server.bodyOf('PUT /student/attempts/a1/answers/q1'), {
      'question_id': 'q1',
      'selected_option_ids': ['o2'],
    });
    expectLive(tester, 'Benar! Hebat! Jawabanmu: Pilihan B, Daun. ');

    await tapAndPump(tester, find.text('Soal berikutnya'));
    await tapAndPump(tester, find.bySemanticsLabel('Benar'));
    await tapAndPump(tester, find.text('Periksa Jawaban'));
    await tester.pumpAndSettle();
    expect(server.bodyOf('PUT /student/attempts/a1/answers/q2'), {
      'question_id': 'q2',
      'boolean_value': true,
    });
    // Tanpa jawaban benar dan pembahasan.
    expectLive(
      tester,
      'Belum tepat, tidak apa-apa. Jawabanmu: Benar. Tetap semangat, kamu '
      'pasti bisa!',
    );
    expect(find.textContaining('Jawaban yang benar'), findsNothing);

    await tapAndPump(tester, find.text('Kumpulkan dan lihat hasil'));
    await tester.pumpAndSettle();
    expect(find.text('Benar 1 dari 2'), findsOneWidget);
    expect(find.text('Lihat jawabanku'), findsOneWidget);
    expect(find.textContaining('Dengarkan'), findsNothing);
    expect(find.text('Buka pembahasan'), findsNothing);
    expect(
      find.text(
        'Jawaban benar dan pembahasan terbuka setelah '
        '${formatDateTime(_deadline)}.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('kuis di luar jadwal: pesan backend dibacakan', (tester) async {
    FakeServer({
      'GET /student/quizzes/k1': (_) =>
          jsonResponse({'detail': 'Deadline kuis telah lewat'}, 403),
    }).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        PlayGameScreen(
          quiz: _quiz(),
          materialTitle: 'Tumbuhan',
          studentName: 'Dimas',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectLive(tester, 'Deadline kuis telah lewat.');
    expect(find.text('Coba lagi'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('lihat ulang: tanpa kunci sebelum tenggat', (tester) async {
    tallScreen(tester);
    FakeServer({
      'GET /student/attempts/a1/result': (_) => _review(withKey: false),
    }).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(const ReviewScreen(attemptId: 'a1', withKey: false)),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Soal 1. Di mana fotosintesis terjadi? Jawabanmu: Daun. Benar.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Soal 2. Akar membuat makanan. Jawabanmu: Benar. Salah.',
      ),
      findsOneWidget,
    );
    expect(find.text('Jawaban benar'), findsNothing);
    expect(find.text('Buka pembahasan'), findsNothing);
    handle.dispose();
  });

  testWidgets('pembahasan: jawaban benar dan penjelasan', (tester) async {
    tallScreen(tester);
    FakeServer({
      'GET /student/attempts/a1/discussion': (_) => _review(withKey: true),
    }).install();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(const ReviewScreen(attemptId: 'a1', withKey: true)),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Soal 1. Di mana fotosintesis terjadi? Jawabanmu: Daun. Benar. '
        'Jawaban benar: Daun. Penjelasan: Daun punya kloroplas.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Soal 2. Akar membuat makanan. Jawabanmu: Benar. Salah. Jawaban '
        'benar: Salah.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
