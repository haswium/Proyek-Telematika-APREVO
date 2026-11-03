import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, Supabase, User;

import '../models/models.dart';
import '../services/announce.dart';
import '../services/api_client.dart';
import '../services/settings.dart';

/// Seberapa sering status pembuatan soal AI diperiksa.
const Duration kQuestionPollInterval = Duration(seconds: 3);

/// Pemeriksaan gagal sebanyak ini berturut-turut baru dilaporkan.
const int kQuestionPollFailures = 3;

class _WatchedJob {
  _WatchedJob(this.materialId, this.kind);

  final String materialId;
  final TestKind kind;
  int failures = 0;
}

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
    forgetOpenSubject();
    resetQuestionGeneration();
    if (online) Supabase.instance.client.auth.signOut();
  }

  // ---- Bersama guru dan siswa.

  /// Halaman satu materi, urut dari `position`, beserta gambarnya.
  Future<MaterialPages> sections(String materialId) async {
    final data = await _watchingSubject(
      () => api.get('/materials/$materialId/sections'),
    );
    return MaterialPages(
      sections: [
        for (final s in data['sections'] as List? ?? const [])
          MaterialSection.fromJson(s as Map<String, dynamic>),
      ],
      images: {for (final image in _images(data)) image.imageKey: image},
    );
  }

  static List<PageImage> _images(Map<String, dynamic> data) => [
    for (final i in data['images'] as List? ?? const [])
      PageImage.fromJson(i as Map<String, dynamic>),
  ];

  // ---- Guru.

  Future<SubjectDeleteSummary> subjectDeleteSummary(String subjectId) async =>
      SubjectDeleteSummary.fromJson(
        await api.get('/teacher/subjects/$subjectId/delete-summary'),
      );

  /// Menghapus kelas beserta seluruh isinya.
  ///
  /// Juga melanjutkan penghapusan yang berhenti di tengah. Kalau gagal, kelasnya
  /// mungkin sudah hilang dari daftar, jadi layar tetap perlu memuat ulang.
  Future<void> deleteSubject(String subjectId) async {
    try {
      await api.delete('/teacher/subjects/$subjectId');
    } finally {
      notifyListeners();
    }
  }

  /// Daftar anggota kelas untuk guru pemilik.
  Future<List<SubjectMember>> subjectMembers(String subjectId) async {
    final data = await api.get('/teacher/subjects/$subjectId/members');
    return [
      for (final s in data['students'] as List? ?? const [])
        SubjectMember.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Mengeluarkan siswa dari kelas. Mengembalikan jumlah siswa yang tersisa.
  Future<int> removeSubjectMember(String subjectId, String studentId) async {
    final data = await api.delete(
      '/teacher/subjects/$subjectId/members/$studentId',
    );
    notifyListeners();
    return (data['student_count'] as num?)?.toInt() ?? 0;
  }

  /// Nama guru dan teman sekelas untuk siswa.
  Future<ClassmateList> classmates(String subjectId) async =>
      ClassmateList.fromJson(
        await api.get('/student/subjects/$subjectId/members'),
      );

  /// Kelas yang penghapusannya berhenti di tengah. Diperbarui [teacherSubjects].
  List<Subject> unfinishedDeletions = const [];

  Future<List<Subject>> teacherSubjects() async {
    final data = await api.get('/teacher/subjects');
    unfinishedDeletions = [
      for (final s in data['unfinished_deletions'] as List? ?? const [])
        Subject.fromJson(s as Map<String, dynamic>),
    ];
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

  /// Semua materi satu kelas, termasuk draf.
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

  /// Gambar materi dengan tautan pratinjau, untuk diperiksa guru.
  Future<List<PageImage>> teacherImages(String materialId) async =>
      _images(await api.get('/teacher/materials/$materialId/images'));

  /// Memulai pembuatan deskripsi gambar oleh AI di latar belakang.
  /// Server langsung menjawab; progresnya dibaca dengan [describeStatus].
  Future<DescribeStatus> startDescribeImages(String materialId) async =>
      DescribeStatus.fromJson(
        await api.post(
          '/teacher/materials/$materialId/generate-image-description',
        ),
      );

  Future<DescribeStatus> describeStatus(String materialId) async =>
      DescribeStatus.fromJson(
        await api.get('/teacher/materials/$materialId/image-description'),
      );

  /// Mencoba ulang deskripsi AI untuk satu gambar yang gagal.
  Future<PageImage> retryImageDescription(
    String materialId,
    String imageId,
  ) async {
    final data = await api.post(
      '/teacher/materials/$materialId/images/$imageId/describe',
    );
    notifyListeners();
    return PageImage.fromJson(data['image'] as Map<String, dynamic>);
  }

  Future<void> updateImage(
    String materialId,
    String imageId, {
    String? description,
    bool? isDecorative,
  }) async {
    await api.patch('/teacher/materials/$materialId/images/$imageId', {
      'description': ?description,
      'is_decorative': ?isDecorative,
    });
    notifyListeners();
  }

  /// Menyimpan isi tabel ke-[index] di satu halaman.
  Future<void> updateTable(
    String materialId,
    String sectionId,
    int index,
    ContentTable table,
  ) async {
    await api.patch(
      '/teacher/materials/$materialId/sections/$sectionId/tables/$index',
      {'title': table.title, 'columns': table.columns, 'rows': table.rows},
    );
    notifyListeners();
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

  /// Hasil semua kelas guru, untuk tab Siswa dan Hasil.
  Future<List<SubjectResults>> teacherOverview() async {
    final subjects = await teacherSubjects();
    return Future.wait([for (final s in subjects) subjectResults(s.id)]);
  }

  // ---- Draf soal dan pembuatan soal oleh AI.

  final Map<String, List<Question>> _questionDrafts = {};
  final Map<String, GameType> _draftTypes = {};
  final Map<String, QuestionGeneration> _generations = {};
  final Map<String, _WatchedJob> _watchedJobs = {};
  final Set<String> _takenJobs = {};
  Timer? _questionPoll;
  bool _checkingQuestions = false;

  String _draftKey(String materialId, TestKind kind) =>
      '$materialId:${kind.api}';

  /// Draf soal satu kuis. Disimpan di sini, bukan di layar, supaya tidak
  /// hilang saat guru keluar dari layar, dan hasil AI punya tempat masuk
  /// walaupun layarnya sudah ditutup.
  List<Question> questionDrafts(String materialId, TestKind kind) =>
      _questionDrafts.putIfAbsent(_draftKey(materialId, kind), () => []);

  bool hasQuestionDrafts(String materialId) => TestKind.values.any(
    (kind) => questionDrafts(materialId, kind).isNotEmpty,
  );

  /// Jenis soal pilihan guru sebelum ada soal tersimpan.
  GameType? draftType(String materialId) => _draftTypes[materialId];

  void setDraftType(String materialId, GameType type) {
    _draftTypes[materialId] = type;
  }

  QuestionGeneration? questionGeneration(String materialId, TestKind kind) =>
      _generations[_draftKey(materialId, kind)];

  bool isGeneratingQuestions(String materialId) => TestKind.values.any(
    (kind) => questionGeneration(materialId, kind)?.running ?? false,
  );

  /// Pesan hasil tidak relevan lagi setelah drafnya disimpan.
  void dismissQuestionMessage(String materialId, TestKind kind) {
    final key = _draftKey(materialId, kind);
    if (_generations[key]?.running == false) _generations.remove(key);
  }

  /// Memulai pembuatan soal di backend. Pemeriksaan statusnya berjalan di
  /// sini, jadi tetap diumumkan walaupun guru sudah pindah layar.
  Future<void> startQuestionGeneration({
    required String materialId,
    required TestKind kind,
    required GameType type,
    required int count,
  }) async {
    await api.post('/teacher/materials/$materialId/generate-questions', {
      'test_kind': kind.api,
      'quiz_type': type.api,
      'total_questions': count,
    });
    _draftTypes[materialId] = type;
    _generations[_draftKey(materialId, kind)] = const QuestionGeneration(
      running: true,
    );
    _watchQuestionJob(materialId, kind);
    announce(
      'Sedang membuat soal ${kind.label}. Hasilnya diumumkan saat selesai '
      'atau gagal.',
    );
    notifyListeners();
  }

  /// Melanjutkan proses yang dimulai sebelum aplikasi ditutup, dan mengambil
  /// hasil yang belum diambil. Kalau server gagal, cukup dicoba lagi nanti.
  Future<void> resumeQuestionGeneration(String materialId) async {
    for (final kind in TestKind.values) {
      final key = _draftKey(materialId, kind);
      if (_watchedJobs.containsKey(key)) continue;
      final QuestionJob job;
      try {
        job = await _questionJob(materialId, kind);
      } on ApiException {
        continue;
      }
      if (job.jobId == null || _takenJobs.contains(job.jobId)) continue;
      if (job.running) {
        _draftTypes[materialId] = job.type;
        _generations[key] = const QuestionGeneration(running: true);
        _watchQuestionJob(materialId, kind);
        notifyListeners();
      } else {
        await _takeQuestionJob(materialId, kind, job);
      }
    }
  }

  Future<QuestionJob> _questionJob(String materialId, TestKind kind) async =>
      QuestionJob.fromJson(
        await api.get(
          '/teacher/materials/$materialId/generate-questions'
          '?test_kind=${kind.api}',
        ),
      );

  void _watchQuestionJob(String materialId, TestKind kind) {
    _watchedJobs[_draftKey(materialId, kind)] = _WatchedJob(materialId, kind);
    _questionPoll ??= Timer.periodic(
      kQuestionPollInterval,
      (_) => _checkQuestionJobs(),
    );
  }

  Future<void> _checkQuestionJobs() async {
    // Server lambat: jangan menumpuk pemeriksaan.
    if (_checkingQuestions) return;
    _checkingQuestions = true;
    for (final entry in _watchedJobs.entries.toList()) {
      final watched = entry.value;
      try {
        final job = await _questionJob(watched.materialId, watched.kind);
        watched.failures = 0;
        if (job.running) continue;
        _watchedJobs.remove(entry.key);
        if (job.jobId == null) {
          _finishQuestionGeneration(
            entry.key,
            'Pembuatan soal ${watched.kind.label} terhenti karena server '
            'dimulai ulang. Coba lagi.',
          );
          continue;
        }
        await _takeQuestionJob(watched.materialId, watched.kind, job);
      } on ApiException {
        watched.failures++;
        if (watched.failures < kQuestionPollFailures) continue;
        _watchedJobs.remove(entry.key);
        _finishQuestionGeneration(
          entry.key,
          'Status soal ${watched.kind.label} tidak bisa diperiksa. Periksa '
          'koneksi, lalu buka lagi layar Kelola materi.',
        );
      }
    }
    _checkingQuestions = false;
    if (_watchedJobs.isEmpty) {
      _questionPoll?.cancel();
      _questionPoll = null;
    }
  }

  /// Hasil masuk ke draf, lalu dihapus dari backend. Kalau penghapusan gagal,
  /// [_takenJobs] mencegah hasil yang sama masuk dua kali.
  Future<void> _takeQuestionJob(
    String materialId,
    TestKind kind,
    QuestionJob job,
  ) async {
    final id = job.jobId;
    if (id != null) _takenJobs.add(id);
    if (job.questions.isNotEmpty) _draftTypes[materialId] = job.type;
    questionDrafts(materialId, kind).addAll(job.questions);
    try {
      await api.delete(
        '/teacher/materials/$materialId/generate-questions'
        '?test_kind=${kind.api}',
      );
    } on ApiException {
      // Tidak mengganggu: hasilnya sudah masuk draf.
    }
    final made = job.questions.length;
    final label = kind.label;
    _finishQuestionGeneration(
      _draftKey(materialId, kind),
      made == 0
          ? 'Soal $label belum dibuat. ${job.error ?? ''}'
          : job.error != null
          ? '$made dari ${job.total} soal draf $label dibuat. ${job.error}'
          : '$made soal draf $label siap. Periksa, lalu simpan.',
    );
  }

  void _finishQuestionGeneration(String key, String message) {
    _generations[key] = QuestionGeneration(running: false, message: message);
    announce(message);
    notifyListeners();
  }

  /// Dipanggil saat keluar akun, dan di akhir setiap tes.
  void resetQuestionGeneration() {
    _questionPoll?.cancel();
    _questionPoll = null;
    _checkingQuestions = false;
    _questionDrafts.clear();
    _draftTypes.clear();
    _generations.clear();
    _watchedJobs.clear();
    _takenJobs.clear();
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
    if (_openSubjectId != subjectId) openSubjectGone = null;
    _openSubjectId = subjectId;
    final materials = await _watchingSubject(() => studentMaterials(subjectId));
    for (final m in materials) {
      if (m.id == materialId) return m;
    }
    throw const ApiException(
      'Materi ini tidak lagi tersedia. Mungkin guru menariknya kembali '
      'menjadi draf.',
      statusCode: 404,
    );
  }

  // ---- Kelas yang dihapus saat layarnya terbuka.

  /// Kelas dari materi yang sedang dibuka siswa. Setelah kelas dihapus, baris
  /// materi dan kuisnya ikut hilang, jadi server hanya bisa menjawab "tidak
  /// ditemukan". Hanya aplikasi yang tahu materi itu milik kelas mana.
  String? _openSubjectId;

  /// Pesan dari server kalau kelas yang sedang dibuka sudah dihapus guru.
  String? openSubjectGone;

  /// Dipanggil saat keluar akun, dan di akhir setiap tes.
  void forgetOpenSubject() {
    _openSubjectId = null;
    openSubjectGone = null;
  }

  /// Memeriksa kelas yang sedang dibuka. Mengembalikan pengecualian dari server
  /// kalau kelasnya sudah dihapus. Gangguan lain diabaikan.
  Future<ApiException?> checkOpenSubject() async {
    final id = _openSubjectId;
    if (id == null) return null;
    try {
      await api.get('/student/subjects/$id/materials');
    } on ApiException catch (e) {
      if (e.statusCode == 410) {
        _markSubjectGone(e);
        return e;
      }
    }
    return null;
  }

  void _markSubjectGone(ApiException e) {
    if (openSubjectGone == e.message) return;
    openSubjectGone = e.message;
    notifyListeners();
  }

  /// Permintaan materi atau kuis. Kalau server menjawab "tidak ditemukan" atau
  /// "tidak berhak", periksa apakah kelasnya sudah dihapus, supaya siswa
  /// mendapat alasan yang sebenarnya.
  Future<T> _watchingSubject<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiException catch (e) {
      if (e.statusCode == 410) {
        _markSubjectGone(e);
        rethrow;
      }
      if (e.statusCode != 403 && e.statusCode != 404) rethrow;
      final gone = await checkOpenSubject();
      if (gone != null) throw gone;
      rethrow;
    }
  }

  /// Semua kelas siswa beserta materinya, untuk tab Progres.
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
    final quiz = await _watchingSubject(
      () => api.get('/student/quizzes/$quizId'),
    );
    final attempt = await _watchingSubject(
      () => api.post('/quizzes/$quizId/attempts'),
    );
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
    final data = await _watchingSubject(
      () => api.put(
        '/student/attempts/$attemptId/answers/$questionId',
        answer.toJson(questionId),
      ),
    );
    return data['is_correct'] == true;
  }

  Future<SubmitResult> submitAttempt(String attemptId) async {
    final data = await _watchingSubject(
      () => api.post('/student/attempts/$attemptId/submit'),
    );
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
    final data = await _watchingSubject(
      () => api.get('/student/attempts/$attemptId/$path'),
    );
    return AttemptReview.fromJson(data, withKey: withKey);
  }
}

/// Satu instance untuk seluruh aplikasi.
final AppStore store = AppStore();
