import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, Supabase, User;

import '../models/models.dart';

/// Penyimpanan sementara di memori supaya UI bisa dicoba tanpa backend.
///
/// Setiap method di sini adalah titik sambung ke Supabase nanti:
/// ganti isinya dengan query, tanda tangannya biarkan sama supaya layar
/// tidak perlu diubah.
class AppStore extends ChangeNotifier {
  AppStore() {
    _seed();
  }

  final List<Subject> subjects = [];
  final Random _random = Random();
  int _nextId = 1;

  String _id() => 'local-${_nextId++}';

  // ---- Akun.
  // Kalau kunci anon sudah diisi di supabase_config.dart, masuk dan daftar
  // memakai Supabase Auth (akun asli, tersimpan). Kalau belum, memakai akun
  // contoh di bawah ini (mode demo, hilang saat aplikasi ditutup).

  /// Diisi `true` oleh `main()` setelah `Supabase.initialize` berhasil.
  /// Widget test tidak menjalankan `main()`, jadi tes otomatis memakai mode
  /// demo dan tidak pernah menghubungi Supabase.
  bool online = false;

  final List<Account> _accounts = [
    Account(
      name: 'Bu Rina',
      email: 'guru@aprevo.id',
      password: '123456',
      role: UserRole.teacher,
    ),
    Account(
      name: 'Dimas',
      email: 'siswa@aprevo.id',
      password: '123456',
      role: UserRole.student,
    ),
  ];

  Account? currentUser;

  /// Nama dan peran disimpan di metadata akun Supabase saat daftar.
  Account _fromUser(User user) {
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final email = user.email ?? '';
    final name = (meta['name'] ?? '').toString().trim();
    return Account(
      name: name.isNotEmpty ? name : email.split('@').first,
      email: email,
      password: '',
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
    final clean = email.trim().toLowerCase();
    if (!online) {
      for (final account in _accounts) {
        if (account.email == clean) {
          if (account.password != password) return 'Password salah.';
          currentUser = account;
          return null;
        }
      }
      return 'Akun dengan email ini tidak ditemukan.';
    }
    try {
      final response = await Supabase.instance.client.auth
          .signInWithPassword(email: clean, password: password);
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

  /// Email siswa yang sudah melihat layar sambutan.
  final Set<String> _onboarded = {};

  bool needsOnboarding(Account account) =>
      account.role == UserRole.student && !_onboarded.contains(account.email);

  void markOnboarded(Account account) => _onboarded.add(account.email);

  /// Mengembalikan pesan error, atau `null` kalau akun dibuat dan langsung
  /// masuk. Kalau Supabase meminta konfirmasi email, pesannya menjelaskan itu.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final clean = email.trim().toLowerCase();
    if (!online) {
      if (_accounts.any((a) => a.email == clean)) {
        return 'Email ini sudah terdaftar. Silakan masuk.';
      }
      final account = Account(
        name: name.trim(),
        email: clean,
        password: password,
        role: role,
      );
      _accounts.add(account);
      currentUser = account;
      return null;
    }
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

  /// Semua materi dari semua mata pelajaran, termasuk draf.
  List<LessonMaterial> get materials => [
    for (final subject in subjects) ...subject.materials,
  ];

  static const String _codeLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  String _generateAccessCode() {
    while (true) {
      final code = List.generate(
        kAccessCodeLength,
        (_) => _codeLetters[_random.nextInt(_codeLetters.length)],
      ).join();
      if (!subjects.any((s) => s.accessCode == code)) return code;
    }
  }

  /// Guru membuat mata pelajaran. Kode aksesnya dibuat otomatis di sini.
  Subject createSubject(String name) {
    final subject = Subject(
      id: _id(),
      name: name,
      accessCode: _generateAccessCode(),
    );
    subjects.add(subject);
    notifyListeners();
    return subject;
  }

  /// Guru menambah materi ke satu mata pelajaran. Materi baru selalu draf.
  LessonMaterial createMaterial(Subject subject, String title, String body) {
    final material = LessonMaterial(
      id: _id(),
      subjectId: subject.id,
      title: title,
      body: body,
    );
    subject.materials.add(material);
    notifyListeners();
    return material;
  }

  /// Guru mengunggah PDF sebagai materi baru (draf) di satu mata pelajaran.
  ///
  /// TIRUAN untuk mode demo: [bytes] belum dikirim ke mana pun, dan isi
  /// materinya teks contoh. Nanti diganti dengan POST
  /// /teacher/materials/upload ke backend (branch feat/backend-materials).
  /// Kalau unggahan gagal, method ini melempar exception.
  Future<LessonMaterial> uploadMaterialPdf(
    Subject subject, {
    required String title,
    required String fileName,
    required Uint8List bytes,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final material = LessonMaterial(
      id: _id(),
      subjectId: subject.id,
      title: title,
      sourceFileName: fileName,
      body:
          'Materi $title diunggah dari file $fileName. Di mode demo, isi '
          'PDF belum dibaca. Setelah aplikasi tersambung ke server, teks dari '
          'PDF akan muncul di sini dan bisa didengarkan.',
    );
    subject.materials.add(material);
    notifyListeners();
    return material;
  }

  /// Siswa bergabung ke mata pelajaran lewat kode aksesnya. Huruf kecil,
  /// spasi, dan strip dalam ketikan siswa tetap diterima.
  JoinResult joinSubject(String code, String studentName) {
    final clean = cleanAccessCode(code);
    for (final subject in subjects) {
      if (subject.accessCode != clean) continue;
      if (subject.students.contains(studentName)) {
        return JoinResult(JoinStatus.alreadyJoined, subject);
      }
      subject.students.add(studentName);
      notifyListeners();
      return JoinResult(JoinStatus.joined, subject);
    }
    return const JoinResult(JoinStatus.notFound);
  }

  /// Mata pelajaran yang sudah diikuti seorang siswa.
  List<Subject> subjectsOf(String studentName) =>
      subjects.where((s) => s.students.contains(studentName)).toList();

  /// Materi yang boleh dilihat siswa: hanya yang sudah dipublikasikan.
  List<LessonMaterial> publishedMaterials(Subject subject) =>
      subject.materials.where((m) => m.published).toList();

  /// Materi publik dari semua mata pelajaran yang diikuti seorang siswa.
  List<LessonMaterial> materialsOf(String studentName) => [
    for (final subject in subjectsOf(studentName))
      ...publishedMaterials(subject),
  ];

  /// Mata pelajaran tempat sebuah materi berada.
  Subject subjectOf(LessonMaterial material) =>
      subjects.firstWhere((s) => s.id == material.subjectId);

  /// Dipanggil setelah mengubah isi materi (jenis soal, daftar soal).
  void touch() => notifyListeners();

  void setPublished(LessonMaterial material, bool value) {
    material.published = value;
    notifyListeners();
  }

  void addAttempt(LessonMaterial material, Attempt attempt) {
    material.attempts.add(attempt);
    notifyListeners();
  }

  /// Pengerjaan terakhir seorang siswa untuk satu tes, atau `null`.
  Attempt? latestAttempt(
    LessonMaterial material,
    String studentName,
    TestKind kind,
  ) {
    for (final a in material.attempts.reversed) {
      if (a.studentName == studentName && a.kind == kind) return a;
    }
    return null;
  }

  /// TIRUAN AI Game Generator. Hanya membuat soal contoh dari judul materi
  /// supaya alur "generate lalu review" bisa didemokan. Ganti dengan
  /// pemanggilan backend AI.
  Future<List<Question>> generateQuestions(
    GameType type,
    LessonMaterial material,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final topic = material.title;
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

  void _seed() {
    final ipa = Subject(id: _id(), name: 'IPA Kelas 5', accessCode: 'KXPRTA');
    final bumi = Subject(
      id: _id(),
      name: 'Bumi dan Antariksa',
      accessCode: 'BMRANT',
    );

    // Materi 1: jenis soal Quiz.
    final foto = LessonMaterial(
      id: _id(),
      subjectId: ipa.id,
      title: 'Fotosintesis',
      questionType: GameType.quiz,
      published: true,
      body:
          'Fotosintesis adalah proses tumbuhan membuat makanannya sendiri. '
          'Proses ini terjadi di daun, pada bagian yang disebut kloroplas. '
          'Di dalam kloroplas ada klorofil, zat hijau daun yang menyerap '
          'cahaya matahari. Tumbuhan memerlukan cahaya matahari, air, dan '
          'karbon dioksida. Hasilnya adalah glukosa sebagai makanan dan '
          'oksigen yang dilepaskan ke udara.',
    );
    foto.preTest.addAll([
      Question(
        prompt: 'Di bagian tumbuhan mana fotosintesis terutama terjadi?',
        options: ['Akar', 'Batang', 'Daun', 'Bunga'],
        correctIndex: 2,
        explanation:
            'Fotosintesis terjadi di daun karena daun punya banyak '
            'kloroplas. Akar bertugas menyerap air, dan batang '
            'menyalurkannya ke daun.',
      ),
      Question(
        prompt: 'Apa yang dibutuhkan tumbuhan untuk fotosintesis?',
        options: [
          'Cahaya matahari, air, dan karbon dioksida',
          'Oksigen dan glukosa',
          'Tanah dan pupuk saja',
          'Angin dan hujan',
        ],
        correctIndex: 0,
        explanation:
            'Bahan fotosintesis ada tiga: cahaya matahari, air, dan karbon '
            'dioksida. Oksigen dan glukosa adalah hasilnya, bukan bahannya.',
      ),
    ]);
    foto.postTest.addAll([
      Question(
        prompt: 'Gas apa yang dilepaskan tumbuhan saat fotosintesis?',
        options: ['Oksigen', 'Karbon dioksida', 'Nitrogen', 'Hidrogen'],
        correctIndex: 0,
        imageDescription:
            'Diagram sehelai daun. Panah dari matahari menuju daun. '
            'Panah karbon dioksida masuk ke daun, dan panah oksigen '
            'keluar dari daun.',
        explanation:
            'Tumbuhan menyerap karbon dioksida dan melepaskan oksigen. '
            'Oksigen inilah yang kita hirup saat bernapas.',
      ),
      Question(
        prompt: 'Zat hijau daun yang menyerap cahaya matahari disebut apa?',
        options: ['Glukosa', 'Klorofil', 'Stomata', 'Kloroplas'],
        correctIndex: 1,
        explanation:
            'Zat hijau daun adalah klorofil. Kloroplas adalah tempatnya, '
            'sedangkan klorofil adalah zat di dalamnya yang menyerap cahaya.',
      ),
      Question(
        prompt: 'Apa hasil fotosintesis yang menjadi makanan tumbuhan?',
        options: ['Air', 'Oksigen', 'Glukosa', 'Karbon dioksida'],
        correctIndex: 2,
        explanation:
            'Makanan tumbuhan adalah glukosa, sejenis gula. Oksigen juga '
            'dihasilkan, tetapi dilepaskan ke udara.',
      ),
    ]);

    // Materi 2: jenis soal Benar atau Salah.
    final napas = LessonMaterial(
      id: _id(),
      subjectId: ipa.id,
      title: 'Sistem Pernapasan',
      questionType: GameType.trueFalse,
      published: true,
      body:
          'Saat bernapas, udara masuk lewat hidung, melewati tenggorokan, '
          'lalu sampai ke paru-paru. Di paru-paru, oksigen diserap ke dalam '
          'darah dan karbon dioksida dikeluarkan. Otot diafragma di bawah '
          'paru-paru membantu kita menarik dan menghembuskan napas.',
    );
    napas.preTest.add(
      Question(
        prompt: 'Udara yang kita hirup berakhir di lambung.',
        options: const ['Benar', 'Salah'],
        correctIndex: 1,
        explanation:
            'Udara berakhir di paru-paru, bukan lambung. Lambung adalah '
            'bagian dari sistem pencernaan.',
      ),
    );
    napas.postTest.addAll([
      Question(
        prompt: 'Di paru-paru, oksigen diserap ke dalam darah.',
        options: const ['Benar', 'Salah'],
        correctIndex: 0,
        explanation:
            'Benar. Di paru-paru terjadi pertukaran gas: oksigen masuk ke '
            'darah dan karbon dioksida keluar.',
      ),
      Question(
        prompt: 'Diafragma adalah otot yang membantu kita bernapas.',
        options: const ['Benar', 'Salah'],
        correctIndex: 0,
        explanation:
            'Benar. Diafragma berada di bawah paru-paru dan bergerak naik '
            'turun saat kita menarik dan menghembuskan napas.',
      ),
    ]);

    // Materi 3: jenis soal Puzzle Urutan.
    final air = LessonMaterial(
      id: _id(),
      subjectId: ipa.id,
      title: 'Daur Air',
      questionType: GameType.ordering,
      published: true,
      body:
          'Daur air adalah perjalanan air yang berulang. Pertama, panas '
          'matahari menguapkan air laut. Uap air naik dan mendingin menjadi '
          'awan. Awan yang berat menurunkan hujan. Air hujan mengalir lewat '
          'sungai kembali ke laut.',
    );
    air.preTest.add(
      Question(
        prompt: 'Susun perjalanan air dari awal sampai akhir.',
        options: [
          'Air laut menguap',
          'Uap air menjadi awan',
          'Hujan turun',
        ],
        explanation:
            'Air harus menguap dulu supaya bisa menjadi awan, dan awan '
            'harus terbentuk dulu sebelum hujan turun.',
      ),
    );
    air.postTest.add(
      Question(
        prompt: 'Susun daur air secara lengkap dari awal sampai akhir.',
        options: [
          'Panas matahari menguapkan air laut',
          'Uap air mendingin menjadi awan',
          'Awan menurunkan hujan',
          'Air mengalir lewat sungai ke laut',
        ],
        explanation:
            'Urutannya: menguap, menjadi awan, turun sebagai hujan, lalu '
            'mengalir kembali ke laut. Setelah itu daurnya berulang.',
      ),
    );

    // Materi 4: jenis soal Isian Singkat.
    final planet = LessonMaterial(
      id: _id(),
      subjectId: bumi.id,
      title: 'Tata Surya',
      questionType: GameType.shortAnswer,
      published: true,
      body:
          'Tata surya terdiri atas Matahari dan delapan planet yang '
          'mengelilinginya. Planet terdekat dari Matahari adalah Merkurius. '
          'Bumi adalah planet ketiga. Planet terbesar adalah Jupiter.',
    );
    planet.preTest.add(
      Question(
        prompt: 'Bumi adalah planet ke berapa dari Matahari? Jawab dengan kata.',
        answerText: 'ketiga',
        explanation:
            'Urutannya Merkurius, Venus, lalu Bumi. Jadi Bumi adalah planet '
            'ketiga dari Matahari.',
      ),
    );
    planet.postTest.addAll([
      Question(
        prompt: 'Apa nama planet terbesar di tata surya?',
        answerText: 'Jupiter',
        explanation: 'Jupiter adalah planet terbesar di tata surya.',
      ),
      Question(
        prompt: 'Apa nama planet yang paling dekat dengan Matahari?',
        answerText: 'Merkurius',
        explanation:
            'Merkurius adalah planet terdekat dari Matahari, sebelum Venus '
            'dan Bumi.',
      ),
    ]);

    // Materi 5: masih draf, jadi tidak terlihat oleh siswa.
    final gerhana = LessonMaterial(
      id: _id(),
      subjectId: bumi.id,
      title: 'Gerhana',
      questionType: GameType.quiz,
      body:
          'Gerhana matahari terjadi saat Bulan berada di antara Matahari dan '
          'Bumi, sehingga cahaya Matahari tertutup Bulan.',
    );

    // Dimas belum ikut Bumi dan Antariksa, supaya alur memasukkan kode
    // BMRANT bisa didemokan.
    ipa.students.addAll(['Dimas', 'Sari']);
    foto.attempts.addAll([
      Attempt(
        studentName: 'Sari',
        materialId: foto.id,
        materialTitle: foto.title,
        kind: TestKind.pre,
        score: 1,
        total: 2,
      ),
      Attempt(
        studentName: 'Sari',
        materialId: foto.id,
        materialTitle: foto.title,
        kind: TestKind.post,
        score: 3,
        total: 3,
      ),
    ]);
    ipa.materials.addAll([foto, napas, air]);
    bumi.materials.addAll([planet, gerhana]);
    subjects.addAll([ipa, bumi]);
  }
}

/// Satu instance untuk seluruh aplikasi. Cukup untuk tahap prototipe.
final AppStore store = AppStore();
