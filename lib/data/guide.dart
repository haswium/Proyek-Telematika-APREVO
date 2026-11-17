import '../models/models.dart';

/// Satu fitur di panduan: judul (dibaca sebagai header) dan langkah singkat.
class GuideSection {
  const GuideSection(this.title, this.steps);

  final String title;
  final List<String> steps;
}

/// Langkah memakai APREVO dengan TalkBack di HP, untuk semua peran.
const _talkBack = GuideSection('Memakai APREVO dengan TalkBack', [
  'Geser satu jari ke kanan untuk pindah ke elemen berikutnya, ke kiri untuk '
      'kembali.',
  'Ketuk dua kali di mana saja untuk menekan tombol yang sedang difokus.',
  'Untuk lompat antarjudul, pilih navigasi Judul di menu TalkBack, lalu geser '
      'ke atas atau ke bawah.',
  'Di laptop, tekan Tab untuk pindah tombol dan Enter untuk menekan. Dengan '
      'NVDA, tekan H untuk lompat antarjudul.',
]);

const studentGuide = [
  _talkBack,
  GuideSection('Bergabung ke kelas', [
    'Minta kode akses 6 huruf dari guru.',
    'Di Beranda, ketik kode itu di kolom kode akses. Huruf yang kamu ketik '
        'dibacakan satu per satu.',
    'Tekan Gabung. Kelas baru muncul di daftar kelasmu.',
  ]),
  GuideSection('Membaca materi', [
    'Buka kelas, lalu pilih materi.',
    'Kerjakan pre-test dulu kalau diminta, lalu tekan Baca materi.',
    'Pindah halaman dengan tombol Halaman berikutnya dan Halaman sebelumnya di '
        'bawah teks. Nomor dan judul halaman dibacakan setiap pindah.',
    'Gambar dibacakan sebagai "Gambar:" lalu deskripsinya.',
    'Untuk lompat ke halaman tertentu atau mencari kata, buka Daftar halaman.',
  ]),
  GuideSection('Mengerjakan kuis', [
    'Tekan Mulai pre-test atau Mulai post-test. Post-test terbuka setelah '
        'pre-test selesai.',
    'Dengarkan soal, pilih satu jawaban, lalu tekan Periksa Jawaban.',
    'Kamu mendengar bunyi pendek dan pesan benar atau salah. Jawaban yang sudah '
        'dikirim tidak bisa diganti.',
    'Tekan Soal berikutnya. Setelah soal terakhir, tekan Kumpulkan dan lihat '
        'hasil.',
  ]),
  GuideSection('Melihat jawaban dan pembahasan', [
    'Setelah kuis selesai, tekan Lihat jawabanku untuk mendengar soal dan '
        'jawabanmu.',
    'Jawaban benar dan pembahasan terbuka setelah tenggat kuis lewat. '
        'Sebelumnya, aplikasi menyebutkan kapan pembahasan terbuka.',
  ]),
  GuideSection('Presensi', [
    'Buka kelas, lalu pilih Presensi.',
    'Saat guru membuka sesi, tekan tombol Hadir. Tombolnya menyebutkan jam '
        'tutup sesi.',
    'Pesan "Presensi tercatat" dibacakan. Riwayat dan rekap kehadiranmu ada di '
        'bawahnya.',
  ]),
  GuideSection('Efek bunyi', [
    'Bunyi pendek terdengar setelah menjawab soal: dua nada naik untuk benar, '
        'satu nada rendah untuk salah.',
    'Untuk mematikannya, buka Profil, lalu matikan saklar Efek bunyi benar dan '
        'salah.',
  ]),
];

const teacherGuide = [
  _talkBack,
  GuideSection('Membuat kelas', [
    'Di tab Kelas, tekan Buat Kelas, lalu ketik nama kelas, misalnya "7A '
        'Geografi".',
    'Bagikan kode akses 6 huruf ke siswa. Tombol Salin menyalin kodenya.',
    'Siswa yang bergabung muncul di Anggota kelas.',
  ]),
  GuideSection('Menambah materi', [
    'Buka kelas, lalu pilih Unggah Materi PDF, atau Tempel teks kalau isinya '
        'dari dokumen lain.',
    'Untuk tempel teks, salin teks dari dokumen, tempel di kolom isi, lalu '
        'periksa pratinjau pembagian halaman sebelum menyimpan.',
    'Periksa isi tiap halaman dan deskripsi gambar. Deskripsi buatan AI bisa '
        'salah, jadi perbaiki sebelum terbit.',
    'Materi masih draf sampai saklar Publikasikan ke siswa dinyalakan.',
  ]),
  GuideSection('Membuat soal dan jadwal', [
    'Di Kelola materi, tambahkan soal pre-test dan post-test. Masing-masing '
        'perlu minimal satu soal supaya materi bisa diterbitkan.',
    'Soal juga bisa dibuat dengan AI dari isi materi, lalu diperiksa dulu.',
    'Atur jadwal tiap kuis: waktu buka dan tenggat. Pembahasan terbuka untuk '
        'siswa setelah tenggat.',
  ]),
  GuideSection('Presensi', [
    'Buka kelas, pilih Presensi, lalu tekan Buka sesi presensi.',
    'Isi judul pertemuan, lalu pilih waktu tutup: 15 menit, 30 menit, 1 jam, '
        'akhir hari, atau atur sendiri.',
    'Siswa yang tidak menekan Hadir sampai sesi ditutup dihitung alpa.',
    'Untuk mengubah status siswa menjadi hadir, izin, sakit, atau alpa, buka '
        'sesinya lalu pilih nama siswa.',
  ]),
  GuideSection('Hasil dan progres siswa', [
    'Tab Hasil berisi nilai pre-test, post-test, dan rata-rata tiap materi.',
    'Di halaman kelas, Progres siswa menampilkan nilai pre-test, post-test, '
        'dan kenaikannya per siswa.',
    'Pre-test memakai percobaan pertama, post-test memakai percobaan terakhir.',
  ]),
  GuideSection('Memakai versi web di laptop', [
    'Buka alamat web APREVO di Chrome atau Edge, lalu masuk dengan akun yang '
        'sama.',
    'Tekan Tab untuk pindah tombol. Tombol yang sedang difokus diberi cincin '
        'kuning.',
  ]),
];

List<GuideSection> guideFor(UserRole role) =>
    role == UserRole.teacher ? teacherGuide : studentGuide;
