/// Progres siswa: nilai pre-test, post-test, dan kenaikannya, dari endpoint
/// `/teacher/subjects/{id}/progress` backend.
///
/// Pre-test memakai percobaan pertama yang dikumpulkan, post-test memakai
/// percobaan terakhir. Nilai berupa persen bulat (0 sampai 100).
library;

import '../services/time_format.dart';

/// Keterangan aturan yang tampil dan dibacakan di layar progres.
const String kProgressRule =
    'Nilai pre-test diambil dari percobaan pertama, nilai post-test dari '
    'percobaan terakhir, dan kenaikan adalah selisih keduanya.';

int? _intOrNull(Object? value) => value is num ? value.toInt() : null;
double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : null;
int _int(Object? value) => value is num ? value.toInt() : 0;

/// "77,5" atau "51": koma desimal, tanpa ",0".
String formatAverage(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return '${rounded.round()}';
  return rounded.toStringAsFixed(1).replaceAll('.', ',');
}

/// "naik 25", "turun 10", atau "tetap".
String gainWords(num gain) {
  if (gain > 0) return 'naik ${_number(gain)}';
  if (gain < 0) return 'turun ${_number(-gain)}';
  return 'tetap';
}

/// "+25", "-10", atau "0", untuk kolom selisih di tabel.
String gainSigned(num gain) {
  if (gain > 0) return '+${_number(gain)}';
  if (gain < 0) return '-${_number(-gain)}';
  return '0';
}

String _number(num value) =>
    value is int ? '$value' : formatAverage(value.toDouble());

/// Hasil satu siswa di satu kuis.
class QuizScore {
  QuizScore({
    required this.quizId,
    required this.attemptCount,
    this.score,
    this.correct,
    this.total,
    this.stars,
    this.submittedAt,
  });

  factory QuizScore.fromJson(Map<String, dynamic> json) => QuizScore(
    quizId: '${json['quiz_id']}',
    attemptCount: _int(json['attempt_count']),
    score: _intOrNull(json['score']),
    correct: _intOrNull(json['correct_count']),
    total: _intOrNull(json['total_questions']),
    stars: _intOrNull(json['stars']),
    submittedAt: parseTime(json['submitted_at']),
  );

  /// `null` kalau kuis ada tetapi siswa belum mengumpulkan.
  static QuizScore? parse(Object? json) =>
      json is Map<String, dynamic> ? QuizScore.fromJson(json) : null;

  final String quizId;
  final int attemptCount;
  final int? score;
  final int? correct;
  final int? total;
  final int? stars;
  final DateTime? submittedAt;

  bool get done => score != null;
}

/// "pre-test 60", "pre-test belum dikerjakan", atau "pre-test belum dibuat".
String scorePhrase(String kind, QuizScore? quiz) {
  if (quiz == null) return '$kind belum dibuat';
  final score = quiz.score;
  return score == null ? '$kind belum dikerjakan' : '$kind $score';
}

/// Nilai pre-test, post-test, dan kenaikan satu siswa di satu materi.
class MaterialScores {
  MaterialScores({this.pre, this.post, this.gain});

  factory MaterialScores.fromJson(Map<String, dynamic> json) => MaterialScores(
    pre: QuizScore.parse(json['pre']),
    post: QuizScore.parse(json['post']),
    gain: _intOrNull(json['gain']),
  );

  final QuizScore? pre;
  final QuizScore? post;
  final int? gain;

  /// "pre-test 60, post-test 85, naik 25"
  String get text => [
    scorePhrase('pre-test', pre),
    scorePhrase('post-test', post),
    if (gain != null) gainWords(gain!),
  ].join(', ');

  /// "Pre-test 2 kali, post-test 3 kali", hanya kalau ada yang lebih dari
  /// sekali dikerjakan. Selain itu kosong.
  String get attemptsNote {
    final pre = this.pre;
    final post = this.post;
    if ((pre?.attemptCount ?? 0) <= 1 && (post?.attemptCount ?? 0) <= 1) {
      return '';
    }
    return [
      if (pre != null) 'pre-test ${pre.attemptCount} kali',
      if (post != null) 'post-test ${post.attemptCount} kali',
    ].join(', ');
  }
}

/// "Kuis Fotosintesis". Tidak menambah "Kuis" kalau judulnya sudah diawali
/// kata itu.
String quizName(String materialTitle) =>
    materialTitle.toLowerCase().startsWith('kuis ')
    ? materialTitle
    : 'Kuis $materialTitle';

class ProgressRow {
  ProgressRow({
    required this.studentId,
    required this.name,
    required this.scores,
  });

  factory ProgressRow.fromJson(Map<String, dynamic> json) => ProgressRow(
    studentId: '${json['student_id']}',
    name: '${json['name'] ?? ''}',
    scores: MaterialScores.fromJson(json),
  );

  final String studentId;
  final String name;
  final MaterialScores scores;

  /// "Andi, Kuis Fotosintesis, pre-test 60, post-test 85, naik 25". Kalau
  /// ada kuis yang dikerjakan lebih dari sekali, jumlahnya disebut di akhir.
  String labelFor(String materialTitle) {
    final note = scores.attemptsNote;
    final base = '$name, ${quizName(materialTitle)}, ${scores.text}';
    return note.isEmpty ? base : '$base. Dikerjakan: $note';
  }
}

class MaterialProgress {
  MaterialProgress({
    required this.id,
    required this.title,
    required this.hasPre,
    required this.hasPost,
    required this.rows,
    this.averagePre,
    this.averagePost,
    this.averageGain,
  });

  factory MaterialProgress.fromJson(Map<String, dynamic> json) =>
      MaterialProgress(
        id: '${json['id']}',
        title: '${json['title'] ?? ''}',
        hasPre: json['has_pre'] == true,
        hasPost: json['has_post'] == true,
        averagePre: _doubleOrNull(json['average_pre']),
        averagePost: _doubleOrNull(json['average_post']),
        averageGain: _doubleOrNull(json['average_gain']),
        rows: [
          for (final r in json['rows'] as List? ?? const [])
            ProgressRow.fromJson(r as Map<String, dynamic>),
        ],
      );

  final String id;
  final String title;
  final bool hasPre;
  final bool hasPost;
  final double? averagePre;
  final double? averagePost;
  final double? averageGain;
  final List<ProgressRow> rows;

  /// "Rata-rata pre-test 36,5, post-test 85, naik 25"
  String get averageText =>
      averagesSentence(averagePre, averagePost, averageGain);
}

/// "Rata-rata pre-test 51, post-test 77,5, naik 7,5", atau "Belum ada
/// nilai".
String averagesSentence(double? pre, double? post, double? gain) {
  if (pre == null && post == null) return 'Belum ada nilai';
  return [
    'Rata-rata pre-test ${pre == null ? 'belum ada' : formatAverage(pre)}',
    'post-test ${post == null ? 'belum ada' : formatAverage(post)}',
    gain == null ? 'kenaikan belum bisa dihitung' : gainWords(gain),
  ].join(', ');
}

class ClassProgressSummary {
  ClassProgressSummary({
    required this.studentCount,
    required this.materialCount,
    required this.completeCount,
    required this.improved,
    required this.same,
    required this.declined,
    this.averagePre,
    this.averagePost,
    this.averageGain,
  });

  factory ClassProgressSummary.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return ClassProgressSummary(
      studentCount: _int(map['student_count']),
      materialCount: _int(map['material_count']),
      completeCount: _int(map['complete_count']),
      improved: _int(map['improved']),
      same: _int(map['same']),
      declined: _int(map['declined']),
      averagePre: _doubleOrNull(map['average_pre']),
      averagePost: _doubleOrNull(map['average_post']),
      averageGain: _doubleOrNull(map['average_gain']),
    );
  }

  final int studentCount;
  final int materialCount;
  final int completeCount;
  final int improved;
  final int same;
  final int declined;
  final double? averagePre;
  final double? averagePost;
  final double? averageGain;

  /// "Progres IPA: 3 siswa, 2 materi berkuis. Rata-rata pre-test 51,
  /// post-test 77,5, naik 7,5. 1 siswa naik, 0 tetap, 0 turun."
  String sentence(String subjectName) {
    final parts = [
      'Progres $subjectName: $studentCount siswa, $materialCount materi '
          'berkuis.',
      '${averagesSentence(averagePre, averagePost, averageGain)}.',
      if (completeCount > 0)
        '$improved siswa naik, $same tetap, $declined turun.',
    ];
    return parts.join(' ');
  }
}

class ClassProgress {
  ClassProgress({
    required this.subjectName,
    required this.summary,
    required this.materials,
  });

  factory ClassProgress.fromJson(Map<String, dynamic> json) => ClassProgress(
    subjectName: '${(json['subject'] as Map?)?['name'] ?? ''}',
    summary: ClassProgressSummary.fromJson(json['summary']),
    materials: [
      for (final m in json['materials'] as List? ?? const [])
        MaterialProgress.fromJson(m as Map<String, dynamic>),
    ],
  );

  final String subjectName;
  final ClassProgressSummary summary;
  final List<MaterialProgress> materials;
}

class StudentMaterialProgress {
  StudentMaterialProgress({
    required this.id,
    required this.title,
    required this.scores,
  });

  factory StudentMaterialProgress.fromJson(Map<String, dynamic> json) =>
      StudentMaterialProgress(
        id: '${json['id']}',
        title: '${json['title'] ?? ''}',
        scores: MaterialScores.fromJson(json),
      );

  final String id;
  final String title;
  final MaterialScores scores;
}

/// "Pre-test Fotosintesis: nilai 60, benar 3 dari 5, 2 bintang, dikerjakan
/// Senin, 2 November 2026 pukul 08.00, 2 kali percobaan, yang dihitung
/// percobaan pertama"
String quizScoreLabel(String kindLabel, String title, QuizScore? quiz) {
  final head = '$kindLabel $title';
  if (quiz == null) return '$head: belum dibuat';
  final score = quiz.score;
  if (score == null) return '$head: belum dikerjakan';
  final which = kindLabel == 'Pre-test' ? 'pertama' : 'terakhir';
  return [
    '$head: nilai $score',
    if (quiz.correct != null && quiz.total != null)
      'benar ${quiz.correct} dari ${quiz.total}',
    '${quiz.stars ?? 0} bintang',
    if (quiz.submittedAt != null)
      'dikerjakan ${formatDateTime(quiz.submittedAt!)}',
    quiz.attemptCount > 1
        ? '${quiz.attemptCount} kali percobaan, yang dihitung percobaan $which'
        : '1 kali percobaan',
  ].join(', ');
}

class StudentProgress {
  StudentProgress({
    required this.studentId,
    required this.name,
    required this.completeCount,
    required this.materials,
    this.averageGain,
  });

  factory StudentProgress.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map? ?? const {};
    return StudentProgress(
      studentId: '${student['id']}',
      name: '${student['name'] ?? ''}',
      averageGain: _doubleOrNull(json['average_gain']),
      completeCount: _int(json['complete_count']),
      materials: [
        for (final m in json['materials'] as List? ?? const [])
          StudentMaterialProgress.fromJson(m as Map<String, dynamic>),
      ],
    );
  }

  final String studentId;
  final String name;
  final double? averageGain;
  final int completeCount;
  final List<StudentMaterialProgress> materials;

  /// "Andi: rata-rata naik 7,5 dari 2 materi."
  String get sentence {
    final gain = averageGain;
    if (gain == null) {
      return '$name: rata-rata kenaikan belum bisa dihitung, belum ada '
          'materi dengan pre-test dan post-test yang sudah dikerjakan.';
    }
    return '$name: rata-rata ${gainWords(gain)} dari $completeCount materi.';
  }
}
