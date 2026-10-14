/// Model data APREVO. Untuk sekarang hanya dipakai oleh data contoh di
/// `data/app_store.dart`; nanti dipetakan ke tabel Supabase.
library;

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
}

class Question {
  Question({
    required this.prompt,
    this.options = const [],
    this.correctIndex = 0,
    this.answerText = '',
    this.explanation,
    this.imageDescription,
  });

  final String prompt;

  /// quiz: pilihan jawaban. trueFalse: ['Benar', 'Salah'].
  /// ordering: item dalam urutan yang BENAR. shortAnswer: kosong.
  final List<String> options;

  /// Indeks jawaban benar (quiz dan trueFalse).
  final int correctIndex;

  /// Jawaban benar (shortAnswer).
  final String answerText;

  /// Pembahasan yang dibacakan setelah siswa menjawab.
  final String? explanation;

  /// Deskripsi gambar/peta/diagram, dibacakan sebagai pengganti visual.
  final String? imageDescription;

  String correctText(GameType type) {
    switch (type) {
      case GameType.quiz:
      case GameType.trueFalse:
        return options[correctIndex];
      case GameType.shortAnswer:
        return answerText;
      case GameType.ordering:
        return options.join(', lalu ');
    }
  }
}

enum TestKind { pre, post }

extension TestKindInfo on TestKind {
  String get label => this == TestKind.pre ? 'Pre-test' : 'Post-test';
}

/// Satu materi = satu paket belajar: isi materi, satu jenis soal yang
/// dipilih guru, lalu pre-test dan post-test dengan jenis soal itu.
/// Tiap materi punya kode akses sendiri; siswa bergabung per materi.
class LessonMaterial {
  LessonMaterial({
    required this.id,
    required this.title,
    required this.body,
    required this.accessCode,
    this.questionType = GameType.quiz,
    this.published = false,
  });

  final String id;
  final String title;
  final String body;

  /// Kode unik materi ini, dibuat otomatis oleh sistem. Contoh: APV-7K29.
  final String accessCode;

  /// Nama siswa yang sudah bergabung lewat kode akses.
  final List<String> students = [];
  final List<Attempt> attempts = [];

  /// Jenis soal untuk materi ini. Hanya satu, dipilih guru.
  GameType questionType;
  bool published;
  final List<Question> preTest = [];
  final List<Question> postTest = [];

  List<Question> questionsFor(TestKind kind) =>
      kind == TestKind.pre ? preTest : postTest;

  bool get hasQuestions => preTest.isNotEmpty || postTest.isNotEmpty;
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

class Attempt {
  Attempt({
    required this.studentName,
    required this.materialId,
    required this.materialTitle,
    required this.kind,
    required this.score,
    required this.total,
  });

  final String studentName;
  final String materialId;
  final String materialTitle;
  final TestKind kind;
  final int score;
  final int total;

  int get stars => starsFor(score, total);
}

enum UserRole { teacher, student }

extension UserRoleInfo on UserRole {
  String get label => this == UserRole.teacher ? 'Guru' : 'Siswa';
}

class Account {
  Account({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
  });

  final String name;
  final String email;
  final String password;
  final UserRole role;
}
