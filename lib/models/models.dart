/// Model data APREVO, dipetakan dari respons backend
/// (lihat `docs/kontrak-api.md`).
library;

import '../services/time_format.dart';

enum GameType { quiz, trueFalse, shortAnswer, ordering }

extension GameTypeInfo on GameType {
  String get label {
    switch (this) {
      case GameType.quiz:
        return 'Quiz';
      case GameType.trueFalse:
        return 'Benar atau Salah';
      case GameType.shortAnswer:
        return 'Isian Singkat';
      case GameType.ordering:
        return 'Puzzle Urutan';
    }
  }

  /// Instruksi singkat yang dibacakan ke siswa di awal soal.
  String get instruction {
    switch (this) {
      case GameType.quiz:
        return 'Pilih satu jawaban yang benar.';
      case GameType.trueFalse:
        return 'Tentukan pernyataan ini benar atau salah.';
      case GameType.shortAnswer:
        return 'Ketik jawaban singkat.';
      case GameType.ordering:
        return 'Susun urutan dengan tombol naik dan turun.';
    }
  }

  /// Nilai `type` di backend.
  String get api {
    switch (this) {
      case GameType.quiz:
        return 'multiple_choice';
      case GameType.trueFalse:
        return 'true_false';
      case GameType.shortAnswer:
        return 'text';
      case GameType.ordering:
        return 'ordering';
    }
  }
}

GameType gameTypeFromApi(Object? value) {
  switch (value) {
    case 'true_false':
      return GameType.trueFalse;
    case 'text':
      return GameType.shortAnswer;
    case 'ordering':
      return GameType.ordering;
    default:
      return GameType.quiz;
  }
}

String _str(Object? value) => value == null ? '' : value.toString();

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_str(value)) ?? 0;

List<Map<String, dynamic>> _list(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map<String, dynamic>) item,
      ]
    : const [];

/// Soal milik guru: draf yang sedang disusun di aplikasi ([id] `null`), atau
/// soal yang sudah tersimpan di server.
class Question {
  Question({
    this.id,
    required this.prompt,
    this.options = const [],
    this.correctIndex = 0,
    this.answerText = '',
    this.explanation,
  });

  /// `null` selama soal masih draf di aplikasi.
  final String? id;

  final String prompt;

  /// quiz: pilihan jawaban. trueFalse: ['Benar', 'Salah'].
  /// ordering: item dalam urutan yang BENAR. shortAnswer: kosong.
  final List<String> options;

  /// Indeks jawaban benar (quiz dan trueFalse).
  final int correctIndex;

  /// Jawaban benar (shortAnswer). Beberapa jawaban yang diterima dipisah
  /// titik koma: "ketiga; 3".
  final String answerText;

  /// Pembahasan, baru dibuka ke siswa setelah tenggat kuis lewat.
  final String? explanation;

  bool get saved => id != null;

  List<String> get acceptedAnswers => [
    for (final a in answerText.split(';'))
      if (a.trim().isNotEmpty) a.trim(),
  ];

  String correctText(GameType type) {
    switch (type) {
      case GameType.quiz:
      case GameType.trueFalse:
        return options[correctIndex];
      case GameType.shortAnswer:
        return acceptedAnswers.join(' atau ');
      case GameType.ordering:
        return options.join(', lalu ');
    }
  }

  /// Bentuk satu soal di body `POST /quizzes/{id}/questions`.
  Map<String, dynamic> toApi(GameType type) {
    final body = <String, dynamic>{
      'type': type.api,
      'question': prompt,
      if (explanation != null && explanation!.isNotEmpty)
        'explanation': explanation,
    };
    switch (type) {
      case GameType.quiz:
        body['options'] = [
          for (var i = 0; i < options.length; i++)
            {'text': options[i], 'is_correct': i == correctIndex},
        ];
      case GameType.trueFalse:
        body['correct_answer'] = correctIndex == 0;
      case GameType.shortAnswer:
        body['answers'] = [
          for (final a in acceptedAnswers) {'answer': a},
        ];
      case GameType.ordering:
        body['items'] = [
          for (var i = 0; i < options.length; i++)
            {'text': options[i], 'correct_order': i + 1},
        ];
    }
    return body;
  }

  /// Soal tersimpan dari `GET /quizzes/{id}` (berisi kunci jawaban).
  static Question fromApi(Map<String, dynamic> json) {
    final type = gameTypeFromApi(json['type']);
    final explanation = json['explanation'] as String?;
    switch (type) {
      case GameType.quiz:
        final options = _list(json['options']);
        final correct = options.indexWhere((o) => o['is_correct'] == true);
        return Question(
          id: _str(json['id']),
          prompt: _str(json['question']),
          options: [for (final o in options) _str(o['text'])],
          correctIndex: correct < 0 ? 0 : correct,
          explanation: explanation,
        );
      case GameType.trueFalse:
        return Question(
          id: _str(json['id']),
          prompt: _str(json['question']),
          options: const ['Benar', 'Salah'],
          correctIndex: json['correct_answer'] == false ? 1 : 0,
          explanation: explanation,
        );
      case GameType.shortAnswer:
        return Question(
          id: _str(json['id']),
          prompt: _str(json['question']),
          answerText: [for (final a in _list(json['answer'])) _str(a['answer'])]
              .join('; '),
          explanation: explanation,
        );
      case GameType.ordering:
        final items = _list(json['items'])
          ..sort((a, b) => _int(a['correct_order']) - _int(b['correct_order']));
        return Question(
          id: _str(json['id']),
          prompt: _str(json['question']),
          options: [for (final i in items) _str(i['text'])],
          explanation: explanation,
        );
    }
  }
}

enum TestKind { pre, post }

extension TestKindInfo on TestKind {
  String get label => this == TestKind.pre ? 'Pre-test' : 'Post-test';
  String get api => this == TestKind.pre ? 'pre' : 'post';
}

/// Panjang kode akses kelas: 6 huruf kapital A-Z, tanpa strip.
const int kAccessCodeLength = 6;

/// Merapikan ketikan kode akses: huruf kecil jadi kapital, karakter selain
/// huruf A-Z dibuang. "kx-prta" menjadi "KXPRTA".
String cleanAccessCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');

/// Kelas, misalnya "7A Geografi". Guru melihat kode akses dan
/// jumlah siswa; siswa melihat nama gurunya.
class Subject {
  Subject({
    required this.id,
    required this.name,
    this.accessCode = '',
    this.studentCount = 0,
    this.materialCount = 0,
    this.teacherName,
  });

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    id: _str(json['id']),
    name: _str(json['name']),
    accessCode: _str(json['access_code']),
    studentCount: _int(json['student_count']),
    materialCount: _int(json['material_count']),
    teacherName: json['teacher_name'] as String?,
  );

  final String id;
  final String name;

  /// Kode unik 6 huruf kapital, dibuat backend. Kosong di sisi siswa.
  final String accessCode;

  final int studentCount;

  /// Guru: semua materi termasuk draf. Siswa: hanya yang dipublikasikan.
  final int materialCount;

  final String? teacherName;
}

enum QuizStatus { unscheduled, upcoming, open, closed }

QuizStatus _status(Object? value) {
  switch (value) {
    case 'upcoming':
      return QuizStatus.upcoming;
    case 'open':
      return QuizStatus.open;
    case 'closed':
      return QuizStatus.closed;
    default:
      return QuizStatus.unscheduled;
  }
}

/// Skor bintang: 3 bintang untuk 85% ke atas, 2 untuk 60% ke atas,
/// 1 kalau ada yang benar, 0 kalau belum ada yang benar.
int starsFor(int score, int total) {
  if (total <= 0 || score <= 0) return 0;
  final ratio = score / total;
  if (ratio >= 0.85) return 3;
  if (ratio >= 0.6) return 2;
  return 1;
}

/// Percobaan kuis yang sudah dikumpulkan.
class Attempt {
  Attempt({
    required this.id,
    required this.score,
    required this.total,
    this.submittedAt,
  });

  static Attempt? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return Attempt(
      id: _str(json['attempt_id']),
      score: _int(json['correct_count']),
      total: _int(json['total_questions']),
      submittedAt: parseTime(json['submitted_at']),
    );
  }

  final String id;
  final int score;
  final int total;
  final DateTime? submittedAt;

  int get stars => starsFor(score, total);
}

/// Pre-test atau post-test satu materi beserta jadwalnya. Kolom siswa
/// ([locked], [attemptsUsed], dan seterusnya) bernilai bawaan di sisi guru.
class QuizInfo {
  QuizInfo({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    this.availableFrom,
    this.deadlineAt,
    this.attemptLimit,
    this.attemptsUsed = 0,
    this.unfinishedAttemptId,
    this.locked = false,
    this.discussionAvailable = false,
    this.latestAttempt,
  });

  factory QuizInfo.fromJson(Map<String, dynamic> json) {
    final limit = json['attempt_limit'];
    return QuizInfo(
      id: _str(json['id']),
      kind: json['kind'] == 'post' ? TestKind.post : TestKind.pre,
      title: _str(json['title']),
      status: _status(json['status']),
      availableFrom: parseTime(json['available_from']),
      deadlineAt: parseTime(json['deadline_at']),
      attemptLimit: limit is num ? limit.toInt() : null,
      attemptsUsed: _int(json['attempts_used']),
      unfinishedAttemptId: json['unfinished_attempt_id'] as String?,
      locked: json['locked'] == true,
      discussionAvailable: json['discussion_available'] == true,
      latestAttempt: Attempt.fromJson(json['latest_attempt']),
    );
  }

  final String id;
  final TestKind kind;
  final String title;
  final QuizStatus status;
  final DateTime? availableFrom;
  final DateTime? deadlineAt;

  /// `null` berarti tidak dibatasi.
  final int? attemptLimit;
  final int attemptsUsed;
  final String? unfinishedAttemptId;

  /// Post-test terkunci sampai pre-test dikumpulkan.
  final bool locked;
  final bool discussionAvailable;
  final Attempt? latestAttempt;

  bool get limitReached =>
      attemptLimit != null &&
      unfinishedAttemptId == null &&
      attemptsUsed >= attemptLimit!;

  /// Jadwal dalam satu kalimat, misalnya "Dibuka sampai Senin, 3 November
  /// 2026 pukul 21.00".
  String get scheduleText {
    final from = availableFrom;
    final until = deadlineAt;
    switch (status) {
      case QuizStatus.unscheduled:
        return 'Jadwal belum diatur';
      case QuizStatus.upcoming:
        return 'Belum dibuka. Dibuka ${formatDateTime(from!)}';
      case QuizStatus.open:
        return 'Dibuka sampai ${formatDateTime(until!)}';
      case QuizStatus.closed:
        return 'Sudah ditutup ${formatDateTime(until!)}';
    }
  }
}

/// Satu materi di kelas. Isinya per sub-bab, diambil terpisah
/// lewat `GET /materials/{id}/sections`.
class LessonMaterial {
  LessonMaterial({
    required this.id,
    required this.title,
    this.published = true,
    this.sectionCount = 0,
    this.quizzes = const [],
  });

  factory LessonMaterial.fromJson(Map<String, dynamic> json) => LessonMaterial(
    id: _str(json['id']),
    title: _str(json['title']),
    // Daftar materi siswa hanya berisi materi yang dipublikasikan.
    published: json['is_published'] != false,
    sectionCount: _int(json['section_count']),
    quizzes: [for (final q in _list(json['quizzes'])) QuizInfo.fromJson(q)],
  );

  final String id;
  final String title;
  final bool published;
  final int sectionCount;
  final List<QuizInfo> quizzes;

  QuizInfo? quiz(TestKind kind) {
    for (final q in quizzes) {
      if (q.kind == kind) return q;
    }
    return null;
  }
}

/// Satu sub-bab materi hasil pemecahan PDF.
class MaterialSection {
  MaterialSection({
    required this.id,
    required this.position,
    required this.title,
    this.content = '',
    this.imageDescription,
    this.imageCount = 0,
    this.pageStart,
    this.pageEnd,
  });

  factory MaterialSection.fromJson(Map<String, dynamic> json) {
    final start = json['page_start'];
    final end = json['page_end'];
    return MaterialSection(
      id: _str(json['id']),
      position: _int(json['position']),
      title: _str(json['title']),
      content: _str(json['content']),
      imageDescription: json['image_description'] as String?,
      imageCount: _int(json['image_count']),
      pageStart: start is num ? start.toInt() : null,
      pageEnd: end is num ? end.toInt() : null,
    );
  }

  final String id;
  final int position;
  final String title;
  final String content;
  final String? imageDescription;
  final int imageCount;
  final int? pageStart;
  final int? pageEnd;

  /// "Halaman 3" atau "Halaman 3 sampai 4", kosong kalau tidak diketahui.
  String get pagesText {
    final start = pageStart;
    final end = pageEnd;
    if (start == null) return '';
    if (end == null || end == start) return 'Halaman $start';
    return 'Halaman $start sampai $end';
  }
}

/// Hasil `POST /teacher/materials/upload`.
class UploadResult {
  UploadResult({required this.material, required this.sections});

  final LessonMaterial material;
  final List<MaterialSection> sections;
}

/// Pilihan jawaban atau item urutan, tanpa kunci jawaban.
class Choice {
  const Choice(this.id, this.text);

  final String id;
  final String text;
}

/// Soal untuk siswa dari `GET /student/quizzes/{id}`.
class StudentQuestion {
  StudentQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    this.choices = const [],
  });

  factory StudentQuestion.fromJson(Map<String, dynamic> json) {
    final type = gameTypeFromApi(json['type']);
    final raw = type == GameType.ordering ? json['items'] : json['options'];
    return StudentQuestion(
      id: _str(json['id']),
      type: type,
      prompt: _str(json['question']),
      choices: [
        for (final c in _list(raw)) Choice(_str(c['id']), _str(c['text'])),
      ],
    );
  }

  final String id;
  final GameType type;
  final String prompt;

  /// quiz: pilihan jawaban. ordering: item dalam urutan acak. Lainnya
  /// kosong.
  final List<Choice> choices;
}

/// Jawaban siswa untuk satu soal. Hanya satu format yang terisi.
class StudentAnswer {
  const StudentAnswer.option(String optionId)
    : _optionId = optionId,
      booleanValue = null,
      textValue = null,
      orderedItemIds = null;

  const StudentAnswer.boolean(bool value)
    : _optionId = null,
      booleanValue = value,
      textValue = null,
      orderedItemIds = null;

  const StudentAnswer.text(String value)
    : _optionId = null,
      booleanValue = null,
      textValue = value,
      orderedItemIds = null;

  const StudentAnswer.order(List<String> itemIds)
    : _optionId = null,
      booleanValue = null,
      textValue = null,
      orderedItemIds = itemIds;

  final String? _optionId;
  final bool? booleanValue;
  final String? textValue;
  final List<String>? orderedItemIds;

  Map<String, dynamic> toJson(String questionId) => {
    'question_id': questionId,
    if (_optionId != null) 'selected_option_ids': [_optionId],
    if (booleanValue != null) 'boolean_value': booleanValue,
    if (textValue != null) 'text_value': textValue,
    if (orderedItemIds != null) 'ordered_item_ids': orderedItemIds,
  };
}

/// Kuis yang siap dikerjakan: soal dan percobaan yang sedang berjalan.
class QuizSession {
  QuizSession({
    required this.quizId,
    required this.attemptId,
    required this.title,
    required this.questions,
    required this.resumed,
  });

  final String quizId;
  final String attemptId;
  final String title;
  final List<StudentQuestion> questions;

  /// `true` kalau melanjutkan percobaan yang belum dikumpulkan.
  final bool resumed;
}

/// Hasil `POST /student/attempts/{id}/submit`.
class SubmitResult {
  SubmitResult({
    required this.attemptId,
    required this.score,
    required this.total,
    required this.deadlinePassed,
  });

  final String attemptId;
  final int score;
  final int total;
  final bool deadlinePassed;
}

class ReviewOption {
  ReviewOption({required this.text, required this.selected, this.isCorrect});

  final String text;
  final bool selected;

  /// Hanya terisi di pembahasan.
  final bool? isCorrect;
}

class ReviewOrderItem {
  ReviewOrderItem({required this.text, this.selectedOrder, this.correctOrder});

  final String text;
  final int? selectedOrder;

  /// Hanya terisi di pembahasan.
  final int? correctOrder;
}

/// Satu soal di lihat ulang jawaban atau pembahasan.
class ReviewItem {
  ReviewItem({
    required this.type,
    required this.prompt,
    required this.isCorrect,
    this.answer,
    this.options = const [],
    this.items = const [],
    this.correctAnswer,
    this.acceptedAnswers,
    this.explanation,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    final accepted = json['accepted_answers'];
    return ReviewItem(
      type: gameTypeFromApi(json['type']),
      prompt: _str(json['question']),
      isCorrect: json['is_correct'] == true,
      answer: json['answer'],
      options: [
        for (final o in _list(json['options']))
          ReviewOption(
            text: _str(o['text']),
            selected: o['selected'] == true,
            isCorrect: o['is_correct'] as bool?,
          ),
      ],
      items: [
        for (final i in _list(json['items']))
          ReviewOrderItem(
            text: _str(i['text']),
            selectedOrder: (i['selected_order'] as num?)?.toInt(),
            correctOrder: (i['correct_order'] as num?)?.toInt(),
          ),
      ],
      correctAnswer: json['correct_answer'] as bool?,
      acceptedAnswers: accepted is List
          ? [for (final a in accepted) _str(a)]
          : null,
      explanation: json['explanation'] as String?,
    );
  }

  final GameType type;
  final String prompt;
  final bool isCorrect;

  /// Benar/salah: `bool`. Isian: `String`. Lainnya `null`.
  final Object? answer;
  final List<ReviewOption> options;
  final List<ReviewOrderItem> items;
  final bool? correctAnswer;
  final List<String>? acceptedAnswers;
  final String? explanation;

  /// Jawaban siswa dalam kalimat.
  String get yourAnswer {
    switch (type) {
      case GameType.quiz:
        for (final o in options) {
          if (o.selected) return o.text;
        }
        return 'Tidak dijawab';
      case GameType.trueFalse:
        final a = answer;
        if (a is! bool) return 'Tidak dijawab';
        return a ? 'Benar' : 'Salah';
      case GameType.shortAnswer:
        final a = answer;
        if (a is! String || a.trim().isEmpty) return 'Tidak dijawab';
        return a;
      case GameType.ordering:
        final chosen = [
          for (final i in items)
            if (i.selectedOrder != null) i,
        ]..sort((a, b) => a.selectedOrder! - b.selectedOrder!);
        if (chosen.isEmpty) return 'Tidak dijawab';
        return chosen.map((i) => i.text).join(', lalu ');
    }
  }

  /// Jawaban benar, `null` kalau belum boleh dibuka (sebelum tenggat).
  String? get rightAnswer {
    switch (type) {
      case GameType.quiz:
        for (final o in options) {
          if (o.isCorrect == true) return o.text;
        }
        return null;
      case GameType.trueFalse:
        final c = correctAnswer;
        if (c == null) return null;
        return c ? 'Benar' : 'Salah';
      case GameType.shortAnswer:
        final accepted = acceptedAnswers;
        if (accepted == null || accepted.isEmpty) return null;
        return accepted.join(' atau ');
      case GameType.ordering:
        if (items.any((i) => i.correctOrder == null)) return null;
        final sorted = [...items]
          ..sort((a, b) => a.correctOrder! - b.correctOrder!);
        return sorted.map((i) => i.text).join(', lalu ');
    }
  }
}

/// Hasil `GET /student/attempts/{id}/result` atau `/discussion`.
class AttemptReview {
  AttemptReview({
    required this.attemptId,
    required this.quizTitle,
    required this.score,
    required this.total,
    required this.withKey,
    required this.items,
    this.deadlineAt,
    this.discussionAvailable = false,
  });

  factory AttemptReview.fromJson(
    Map<String, dynamic> json, {
    required bool withKey,
  }) => AttemptReview(
    attemptId: _str(json['attempt_id']),
    quizTitle: _str(json['quiz_title']),
    score: _int(json['score']),
    total: _int(json['total_questions']),
    withKey: withKey,
    deadlineAt: parseTime(json['deadline_at']),
    // Respons pembahasan tidak berisi kolom ini; kalau pembahasannya
    // berhasil dibuka, berarti tersedia.
    discussionAvailable: withKey || json['discussion_available'] == true,
    items: [for (final i in _list(json['review'])) ReviewItem.fromJson(i)],
  );

  final String attemptId;
  final String quizTitle;
  final int score;
  final int total;

  /// `true` untuk pembahasan (berisi jawaban benar dan penjelasan).
  final bool withKey;
  final DateTime? deadlineAt;
  final bool discussionAvailable;
  final List<ReviewItem> items;
}

/// Soal tersimpan satu kuis, untuk guru.
class TeacherQuiz {
  TeacherQuiz({required this.info, required this.questions, this.type});

  final QuizInfo info;
  final List<Question> questions;

  /// Jenis soal kuis ini, diambil dari soal pertama. `null` kalau belum
  /// ada soal.
  final GameType? type;
}

class StudentResult {
  StudentResult({
    required this.studentId,
    required this.name,
    required this.attemptCount,
    this.latest,
  });

  factory StudentResult.fromJson(Map<String, dynamic> json) => StudentResult(
    studentId: _str(json['student_id']),
    name: _str(json['name']),
    attemptCount: _int(json['attempt_count']),
    latest: Attempt.fromJson(json['latest_attempt']),
  );

  final String studentId;
  final String name;
  final int attemptCount;

  /// Percobaan terakhir yang sudah dikumpulkan.
  final Attempt? latest;
}

class QuizResult {
  QuizResult({
    required this.kind,
    required this.status,
    required this.submittedCount,
    required this.students,
    this.averagePercent,
  });

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
    kind: json['kind'] == 'post' ? TestKind.post : TestKind.pre,
    status: _status(json['status']),
    submittedCount: _int(json['submitted_count']),
    averagePercent: (json['average_percent'] as num?)?.toDouble(),
    students: [
      for (final s in _list(json['students'])) StudentResult.fromJson(s),
    ],
  );

  final TestKind kind;
  final QuizStatus status;
  final int submittedCount;

  /// `null` kalau belum ada yang mengumpulkan.
  final double? averagePercent;
  final List<StudentResult> students;
}

class MaterialResult {
  MaterialResult({
    required this.id,
    required this.title,
    required this.published,
    required this.quizzes,
  });

  factory MaterialResult.fromJson(Map<String, dynamic> json) => MaterialResult(
    id: _str(json['id']),
    title: _str(json['title']),
    published: json['is_published'] == true,
    quizzes: [for (final q in _list(json['quizzes'])) QuizResult.fromJson(q)],
  );

  final String id;
  final String title;
  final bool published;
  final List<QuizResult> quizzes;

  QuizResult? quiz(TestKind kind) {
    for (final q in quizzes) {
      if (q.kind == kind) return q;
    }
    return null;
  }
}

/// Hasil `GET /teacher/subjects/{id}/results`.
class SubjectResults {
  SubjectResults({
    required this.subject,
    required this.studentCount,
    required this.materials,
  });

  factory SubjectResults.fromJson(Map<String, dynamic> json) => SubjectResults(
    subject: Subject.fromJson(
      json['subject'] is Map<String, dynamic>
          ? json['subject'] as Map<String, dynamic>
          : const {},
    ),
    studentCount: _int(json['student_count']),
    materials: [
      for (final m in _list(json['materials'])) MaterialResult.fromJson(m),
    ],
  );

  final Subject subject;
  final int studentCount;
  final List<MaterialResult> materials;
}

enum JoinStatus { joined, alreadyJoined, notFound }

/// Hasil siswa memasukkan kode akses. [subject] terisi kecuali
/// [JoinStatus.notFound].
class JoinResult {
  const JoinResult(this.status, [this.subject]);

  final JoinStatus status;
  final Subject? subject;
}

enum UserRole { teacher, student }

extension UserRoleInfo on UserRole {
  String get label => this == UserRole.teacher ? 'Guru' : 'Siswa';
}

class Account {
  Account({required this.name, required this.email, required this.role});

  final String name;
  final String email;
  final UserRole role;
}
