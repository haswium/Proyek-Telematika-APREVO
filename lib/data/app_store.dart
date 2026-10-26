import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, Supabase, User;

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/settings.dart';

/// Akun lewat Supabase Auth, semua data lain lewat backend FastAPI
/// (`docs/kontrak-api.md`).
///
/// Method data melempar [ApiException] dengan pesan berbahasa Indonesia
/// yang siap dibacakan. Setelah data berubah (gabung, unggah, kumpulkan
/// kuis, dan lainnya), [notifyListeners] dipanggil supaya layar yang
/// sedang terbuka memuat ulang datanya (lihat `widgets/load_view.dart`).
class AppStore extends ChangeNotifier {
  AppStore({ApiClient? api}) : api = api ?? _supabaseApi();

  /// Diganti di tes dengan klien yang memakai `MockClient`.
  ApiClient api;

  static ApiClient _supabaseApi() => ApiClient(
    token: () async {
      if (!store.online) return null;
      return Supabase.instance.client.auth.currentSession?.accessToken;
    },
    refreshToken: () async {
      if (!store.online) return false;
      try {
        final response = await Supabase.instance.client.auth.refreshSession();
        return response.session != null;
      } catch (_) {
        return false;
      }
    },
  );

  // ---- Akun.

  /// Diisi `true` oleh `main()` setelah `Supabase.initialize` berhasil.
  /// Widget test tidak menjalankan `main()`, jadi tes tidak pernah
  /// menghubungi Supabase.
  bool online = false;

  Account? currentUser;

  static const String _notConfigured =
      'Aplikasi belum tersambung ke Supabase. Isi kunci anon di '
      'lib/config/supabase_config.dart.';

  /// Nama dan peran disimpan di metadata akun Supabase saat daftar.
  Account _fromUser(User user) {
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final email = user.email ?? '';
    final name = (meta['name'] ?? '').toString().trim();
    return Account(
      name: name.isNotEmpty ? name : email.split('@').first,
      email: email,
      role: meta['role'] == 'teacher' ? UserRole.teacher : UserRole.student,
    );
  }

  /// Pesan error Supabase (bahasa Inggris) ke bahasa Indonesia.
  String _authMessage(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login')) return 'Email atau password salah.';
    if (m.contains('not confirmed')) {
      return 'Email belum dikonfirmasi. Buka email dari Supabase, klik '
          'tautannya, lalu masuk lagi.';
    }
    if (m.contains('already registered')) {
      return 'Email ini sudah terdaftar. Silakan masuk.';
    }
    if (m.contains('rate limit')) {
      return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
    }
    return message;
  }

  /// Kalau pengguna masih masuk dari sesi sebelumnya, pakai akun itu.
  Account? restoreSession() {
    if (!online) return null;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    return currentUser = _fromUser(user);
  }

  /// Mengembalikan pesan error, atau `null` kalau berhasil masuk.
  /// Peran (guru atau siswa) diambil dari akunnya, tidak dipilih saat masuk.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    if (!online) return _notConfigured;
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = response.user;
      if (user == null) return 'Gagal masuk. Coba lagi.';
      currentUser = _fromUser(user);
      return null;
    } on AuthException catch (e) {
      return _authMessage(e.message);
    } catch (_) {
      return 'Tidak bisa terhubung ke server. Periksa sambungan internet.';
    }
  }

  bool needsOnboarding(Account account) =>
      account.role == UserRole.student && !Settings.isOnboarded(account.email);

  void markOnboarded(Account account) => Settings.markOnboarded(account.email);

  /// Mengembalikan pesan error, atau `null` kalau akun dibuat dan langsung
  /// masuk. Kalau Supabase meminta konfirmasi email, pesannya menjelaskan itu.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    if (!online) return _notConfigured;
    final clean = email.trim().toLowerCase();
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: clean,
        password: password,
        data: {
          'name': name.trim(),
          'role': role == UserRole.teacher ? 'teacher' : 'student',
        },
      );
      final user = response.user;
      if (user == null) return 'Gagal membuat akun. Coba lagi.';
      if (response.session == null) {
        return 'Akun dibuat. Buka email $clean, klik tautan konfirmasi dari '
            'Supabase, lalu kembali ke sini dan pilih Masuk.';
      }
      currentUser = _fromUser(user);
      return null;
    } on AuthException catch (e) {
      return _authMessage(e.message);
    } catch (_) {
      return 'Tidak bisa terhubung ke server. Periksa sambungan internet.';
    }
  }

  void signOut() {
    currentUser = null;
    if (online) Supabase.instance.client.auth.signOut();
  }

  // ---- Bersama guru dan siswa.

  /// Sub-bab satu materi, urut dari `position`.
  Future<List<MaterialSection>> sections(String materialId) async {
    final data = await api.get('/materials/$materialId/sections');
    return [
      for (final s in data['sections'] as List? ?? const [])
        MaterialSection.fromJson(s as Map<String, dynamic>),
    ];
  }

  // ---- Guru.

  Future<List<Subject>> teacherSubjects() async {
    final data = await api.get('/teacher/subjects');
    return [
      for (final s in data['subjects'] as List? ?? const [])
        Subject.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Kode aksesnya dibuat backend.
  Future<Subject> createSubject(String name) async {
    final data = await api.post('/teacher/subjects', {'name': name.trim()});
    notifyListeners();
    return Subject.fromJson(data['subject'] as Map<String, dynamic>);
  }

  /// Semua materi satu mata pelajaran, termasuk draf.
  Future<List<LessonMaterial>> teacherMaterials(String subjectId) async {
    final data = await api.get('/teacher/subjects/$subjectId/materials');
    return [
      for (final m in data['materials'] as List? ?? const [])
        LessonMaterial.fromJson(m as Map<String, dynamic>),
    ];
  }

  Future<LessonMaterial> teacherMaterial(
    String subjectId,
    String materialId,
  ) async {
    final materials = await teacherMaterials(subjectId);
    for (final m in materials) {
      if (m.id == materialId) return m;
    }
    throw const ApiException('Materi tidak ditemukan.', statusCode: 404);
  }

  /// PDF dikirim ke backend, disimpan, lalu dipecah per sub-bab.
  /// Materi baru selalu draf.
  Future<UploadResult> uploadMaterialPdf(
    Subject subject, {
    required String title,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final data = await api.upload(
      '/teacher/materials/upload',
      fields: {'title': title, 'subject_id': subject.id},
      fileField: 'file',
      fileName: fileName,
      bytes: bytes,
      contentType: MediaType('application', 'pdf'),
    );
    final sections = [
      for (final s in data['sections'] as List? ?? const [])
        MaterialSection.fromJson(s as Map<String, dynamic>),
    ];
    final material = data['material'] as Map<String, dynamic>? ?? const {};
    notifyListeners();
    return UploadResult(
      material: LessonMaterial.fromJson({
        ...material,
        'section_count': sections.length,
      }),
      sections: sections,
    );
  }

  Future<void> setPublished(String materialId, bool value) async {
    await api.patch('/teacher/materials/$materialId', {'is_published': value});
    notifyListeners();
  }

  Future<void> createQuiz(
    String materialId,
    TestKind kind, {
    required String availableFrom,
    required String deadlineAt,
  }) async {
    await api.post('/teacher/materials/$materialId/quizzes', {
      'kind': kind.api,
      'available_from': availableFrom,
      'deadline_at': deadlineAt,
    });
    notifyListeners();
  }

  Future<void> updateSchedule(
    String quizId, {
    required String availableFrom,
    required String deadlineAt,
  }) async {
    await api.patch('/teacher/quizzes/$quizId/schedule', {
      'available_from': availableFrom,
      'deadline_at': deadlineAt,
    });
    notifyListeners();
  }

  /// Soal tersimpan satu kuis, lengkap dengan kunci jawaban.
  Future<TeacherQuiz> teacherQuiz(QuizInfo info) async {
    final data = await api.get('/quizzes/${info.id}');
    final raw = [
      for (final q in data['questions'] as List? ?? const [])
        q as Map<String, dynamic>,
    ];
    return TeacherQuiz(
      info: info,
      questions: [for (final q in raw) Question.fromApi(q)],
      type: raw.isEmpty ? null : gameTypeFromApi(raw.first['type']),
    );
  }

  /// Mengirim soal draf ke satu kuis sekaligus.
  Future<void> addQuestions(
    String quizId,
    GameType type,
    List<Question> questions,
  ) async {
    await api.post('/quizzes/$quizId/questions', {
      'questions': [for (final q in questions) q.toApi(type)],
    });
    notifyListeners();
  }

  Future<SubjectResults> subjectResults(String subjectId) async {
    final data = await api.get('/teacher/subjects/$subjectId/results');
    return SubjectResults.fromJson(data);
  }

  /// Hasil semua mata pelajaran guru, untuk tab Siswa dan Hasil.
  Future<List<SubjectResults>> teacherOverview() async {
    final subjects = await teacherSubjects();
    return Future.wait([for (final s in subjects) subjectResults(s.id)]);
  }

  /// TIRUAN AI Game Generator. Hanya membuat soal contoh dari judul materi
  /// supaya alur "generate lalu review" bisa didemokan. Ganti dengan
  /// pemanggilan backend AI.
  Future<List<Question>> generateQuestions(GameType type, String topic) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    const note = 'Tulis penjelasan yang membantu siswa memahami jawabannya.';
    switch (type) {
      case GameType.quiz:
        return [
          Question(
            prompt: 'Contoh soal AI 1 tentang $topic. Ubah soal ini.',
            options: ['Pilihan A', 'Pilihan B', 'Pilihan C', 'Pilihan D'],
            correctIndex: 0,
            explanation: note,
          ),
          Question(
            prompt: 'Contoh soal AI 2 tentang $topic. Ubah soal ini.',
            options: ['Pilihan A', 'Pilihan B', 'Pilihan C', 'Pilihan D'],
            correctIndex: 1,
            explanation: note,
          ),
        ];
      case GameType.trueFalse:
        return [
          Question(
            prompt: 'Contoh pernyataan AI tentang $topic. Ubah pernyataan ini.',
            options: const ['Benar', 'Salah'],
            correctIndex: 0,
            explanation: note,
          ),
          Question(
            prompt: 'Contoh pernyataan AI kedua tentang $topic.',
            options: const ['Benar', 'Salah'],
            correctIndex: 1,
            explanation: note,
          ),
        ];
      case GameType.shortAnswer:
        return [
          Question(
            prompt: 'Contoh isian AI tentang $topic. Ubah soal ini.',
            answerText: 'jawaban',
            explanation: note,
          ),
        ];
      case GameType.ordering:
        return [
          Question(
            prompt: 'Contoh urutan AI tentang $topic. Ubah langkahnya.',
            options: ['Langkah pertama', 'Langkah kedua', 'Langkah ketiga'],
            explanation: note,
          ),
        ];
    }
  }

  // ---- Siswa.

  Future<List<Subject>> studentSubjects() async {
    final data = await api.get('/student/subjects');
    return [
      for (final s in data['subjects'] as List? ?? const [])
        Subject.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Siswa bergabung lewat kode akses. Huruf kecil, spasi, dan strip
  /// dirapikan dulu. Kode yang tidak ada menjadi [JoinStatus.notFound];
  /// error lain dilempar sebagai [ApiException].
  Future<JoinResult> joinSubject(String code) async {
    try {
      final data = await api.post('/student/subjects/join', {
        'code': cleanAccessCode(code),
      });
      notifyListeners();
      return JoinResult(
        data['already_joined'] == true
            ? JoinStatus.alreadyJoined
            : JoinStatus.joined,
        Subject.fromJson(data['subject'] as Map<String, dynamic>),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const JoinResult(JoinStatus.notFound);
      rethrow;
    }
  }

  /// Materi yang dipublikasikan beserta status kuisnya.
  Future<List<LessonMaterial>> studentMaterials(String subjectId) async {
    final data = await api.get('/student/subjects/$subjectId/materials');
    return [
      for (final m in data['materials'] as List? ?? const [])
        LessonMaterial.fromJson(m as Map<String, dynamic>),
    ];
  }

  Future<LessonMaterial> studentMaterial(
    String subjectId,
    String materialId,
  ) async {
    final materials = await studentMaterials(subjectId);
    for (final m in materials) {
      if (m.id == materialId) return m;
    }
    throw const ApiException(
      'Materi ini tidak lagi tersedia. Mungkin guru menariknya kembali '
      'menjadi draf.',
      statusCode: 404,
    );
  }

  /// Semua mata pelajaran siswa beserta materinya, untuk tab Progres.
  Future<List<(Subject, List<LessonMaterial>)>> studentProgress() async {
    final subjects = await studentSubjects();
    final materials = await Future.wait([
      for (final s in subjects) studentMaterials(s.id),
    ]);
    return [
      for (var i = 0; i < subjects.length; i++) (subjects[i], materials[i]),
    ];
  }

  /// Mengambil soal lalu memulai percobaan. Kalau ada percobaan yang belum
  /// dikumpulkan, backend mengembalikan percobaan itu.
  Future<QuizSession> startQuiz(String quizId) async {
    final quiz = await api.get('/student/quizzes/$quizId');
    final attempt = await api.post('/quizzes/$quizId/attempts');
    final info = quiz['quiz'] as Map<String, dynamic>? ?? const {};
    final row = attempt['attempt'] as Map<String, dynamic>? ?? const {};
    return QuizSession(
      quizId: quizId,
      attemptId: row['id'].toString(),
      title: (info['title'] ?? '').toString(),
      resumed: (attempt['message'] ?? '').toString().startsWith('Melanjutkan'),
      questions: [
        for (final q in quiz['questions'] as List? ?? const [])
          StudentQuestion.fromJson(q as Map<String, dynamic>),
      ],
    );
  }

  /// Menyimpan jawaban satu soal. Mengembalikan benar atau salah saja,
  /// tanpa jawaban benar dan pembahasan.
  Future<bool> saveAnswer(
    String attemptId,
    String questionId,
    StudentAnswer answer,
  ) async {
    final data = await api.put(
      '/student/attempts/$attemptId/answers/$questionId',
      answer.toJson(questionId),
    );
    return data['is_correct'] == true;
  }

  Future<SubmitResult> submitAttempt(String attemptId) async {
    final data = await api.post('/student/attempts/$attemptId/submit');
    notifyListeners();
    return SubmitResult(
      attemptId: attemptId,
      score: (data['correct_count'] as num?)?.toInt() ?? 0,
      total: (data['total_questions'] as num?)?.toInt() ?? 0,
      deadlinePassed: data['deadline_passed'] == true,
    );
  }

  /// [withKey] `false`: lihat ulang jawaban sendiri (tanpa kunci).
  /// `true`: pembahasan, hanya setelah tenggat lewat.
  Future<AttemptReview> attemptReview(
    String attemptId, {
    required bool withKey,
  }) async {
    final path = withKey ? 'discussion' : 'result';
    final data = await api.get('/student/attempts/$attemptId/$path');
    return AttemptReview.fromJson(data, withKey: withKey);
  }
}

/// Satu instance untuk seluruh aplikasi.
final AppStore store = AppStore();
