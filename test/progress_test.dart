import 'package:flutter_test/flutter_test.dart';

import 'package:aprevo/data/app_store.dart';
import 'package:aprevo/models/models.dart';
import 'package:aprevo/models/progress.dart';
import 'package:aprevo/screens/teacher/progress_screen.dart';
import 'package:aprevo/services/time_format.dart';

import 'fake_server.dart';

final _subject = Subject(id: 's1', name: '7 Geografi');
const _classUrl = 'GET /teacher/subjects/s1/progress';
const _andiUrl = 'GET /teacher/subjects/s1/students/u1/progress';

// Waktu lokal, supaya tanggal sama di zona waktu mana pun mesin tesnya.
final _submitted = DateTime(2026, 11, 9, 8, 15);

Map<String, dynamic> _score(
  String quizId,
  int? score, {
  int attempts = 1,
  int? correct,
  int? total,
  int? stars,
}) => {
  'quiz_id': quizId,
  'attempt_count': score == null ? 0 : attempts,
  'score': score,
  'correct_count': correct,
  'total_questions': total,
  'stars': stars,
  'submitted_at': score == null ? null : isoWithOffset(_submitted),
};

Map<String, dynamic> get _classData => {
  'subject': {'id': 's1', 'name': '7 Geografi'},
  'summary': {
    'student_count': 2,
    'material_count': 1,
    'average_pre': 51.0,
    'average_post': 77.5,
    'average_gain': 7.5,
    'complete_count': 1,
    'improved': 1,
    'same': 0,
    'declined': 0,
  },
  'materials': [
    {
      'id': 'm1',
      'title': 'Fotosintesis',
      'has_pre': true,
      'has_post': true,
      'average_pre': 51.0,
      'average_post': 85.0,
      'average_gain': 25.0,
      'rows': [
        {
          'student_id': 'u1',
          'name': 'Andi',
          'pre': _score('pre1', 60),
          'post': _score('post1', 85, attempts: 2),
          'gain': 25,
        },
        {
          'student_id': 'u2',
          'name': 'Budi',
          'pre': _score('pre1', 42),
          'post': _score('post1', null),
          'gain': null,
        },
      ],
    },
  ],
};

Map<String, dynamic> get _andiData => {
  'subject': {'id': 's1', 'name': '7 Geografi'},
  'student': {'id': 'u1', 'name': 'Andi', 'joined_at': null},
  'average_gain': 25.0,
  'complete_count': 1,
  'materials': [
    {
      'id': 'm1',
      'title': 'Fotosintesis',
      'pre': _score('pre1', 60, correct: 3, total: 5, stars: 2),
      'post': _score(
        'post1',
        85,
        attempts: 2,
        correct: 17,
        total: 20,
        stars: 3,
      ),
      'gain': 25,
    },
  ],
};

List<String> _said(WidgetTester tester) => [
  for (final a in tester.takeAnnouncements()) a.message,
];

void main() {
  const summary =
      'Progres 7 Geografi: 2 siswa, 1 materi berkuis. Rata-rata pre-test '
      '51, post-test 77,5, naik 7,5. 1 siswa naik, 0 tetap, 0 turun.';

  Future<FakeServer> open(WidgetTester tester) async {
    tallScreen(tester);
    final fake = FakeServer({
      _classUrl: (_) => _classData,
      _andiUrl: (_) => _andiData,
    })..install();
    await tester.pumpWidget(testApp(SubjectProgressScreen(subject: _subject)));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('ringkasan kelas diumumkan sekali dan dibaca satu label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    expect(_said(tester).where((m) => m.startsWith('Progres')), [summary]);
    expect(find.bySemanticsLabel(summary), findsOneWidget);
    // Keterangan aturan ikut dibaca TalkBack.
    expect(find.bySemanticsLabel(kProgressRule), findsOneWidget);

    // Muat ulang tidak mengumumkan lagi.
    store.notifyListeners();
    await tester.pumpAndSettle();
    expect(_said(tester), isEmpty);
    handle.dispose();
  });

  testWidgets('tiap baris tabel satu label utuh', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'Andi, Kuis Fotosintesis, pre-test 60, post-test 85, naik 25. '
          'Dikerjakan: pre-test 1 kali, post-test 2 kali',
        ),
      ),
      matchesSemantics(
        label:
            'Andi, Kuis Fotosintesis, pre-test 60, post-test 85, naik 25. '
            'Dikerjakan: pre-test 1 kali, post-test 2 kali',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Budi, Kuis Fotosintesis, pre-test 42, post-test belum dikerjakan',
      ),
      findsOneWidget,
    );
    // Kepala kolom hanya untuk mata.
    expect(find.bySemanticsLabel('Selisih'), findsNothing);
    expect(find.text('Selisih'), findsOneWidget);
    expect(find.text('+25'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('baris membuka progres siswa dengan ringkasannya', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    tester.takeAnnouncements();

    await tester.tap(find.text('Andi'));
    await tester.pumpAndSettle();

    expect(_said(tester), contains('Andi: rata-rata naik 25 dari 1 materi.'));
    final date = formatDateTime(_submitted);
    expect(
      find.bySemanticsLabel(
        'Pre-test Fotosintesis: nilai 60, benar 3 dari 5, 2 bintang, '
        'dikerjakan $date, 1 kali percobaan',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Post-test Fotosintesis: nilai 85, benar 17 dari 20, 3 bintang, '
        'dikerjakan $date, 2 kali percobaan, yang dihitung percobaan '
        'terakhir',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Kenaikan Fotosintesis: naik 25'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(kProgressRule), findsOneWidget);
    handle.dispose();
  });

  group('kalimat', () {
    test('kenaikan, penurunan, dan tetap', () {
      expect(gainWords(25), 'naik 25');
      expect(gainWords(-10), 'turun 10');
      expect(gainWords(0), 'tetap');
      expect(gainWords(7.5), 'naik 7,5');
      expect(gainSigned(-10), '-10');
      expect(formatAverage(51.0), '51');
      expect(formatAverage(77.5), '77,5');
    });

    test('baris dengan kuis yang belum dibuat', () {
      final row = ProgressRow.fromJson({
        'student_id': 'u1',
        'name': 'Andi',
        'pre': _score('pre1', 60),
        'post': null,
        'gain': null,
      });
      expect(
        row.labelFor('Fotosintesis'),
        'Andi, Kuis Fotosintesis, pre-test 60, post-test belum dibuat',
      );
      expect(row.labelFor('Kuis Bab 1'), startsWith('Andi, Kuis Bab 1,'));
    });

    test('ringkasan tanpa nilai', () {
      final s = ClassProgressSummary.fromJson({
        'student_count': 3,
        'material_count': 0,
      });
      expect(
        s.sentence('IPA'),
        'Progres IPA: 3 siswa, 0 materi berkuis. Belum ada nilai.',
      );
    });

    test('siswa tanpa pasangan lengkap', () {
      final p = StudentProgress.fromJson({
        'student': {'id': 'u3', 'name': 'Citra'},
        'average_gain': null,
        'complete_count': 0,
        'materials': [],
      });
      expect(p.sentence, startsWith('Citra: rata-rata kenaikan belum bisa'));
    });
  });
}
