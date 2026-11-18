import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/mascot.dart';

/// Ilustrasi satu halaman panduan: Odi dengan suasana tertentu, atau ikon
/// fitur. Selalu dekoratif; isi halaman ada di judul dan penjelasannya.
class GuideArt {
  const GuideArt.odi(MascotMood this.mood) : icon = null;
  const GuideArt.icon(IconData this.icon) : mood = null;

  final MascotMood? mood;
  final IconData? icon;
}

/// Satu halaman buku panduan: satu langkah.
class GuidePage {
  const GuidePage(this.title, this.body, this.art);

  final String title;
  final String body;
  final GuideArt art;
}

/// Satu bab buku panduan.
class GuideChapter {
  const GuideChapter(this.title, this.icon, this.pages);

  final String title;
  final IconData icon;
  final List<GuidePage> pages;
}

const _odiHappy = GuideArt.odi(MascotMood.happy);
const _odiCheer = GuideArt.odi(MascotMood.cheer);
const _odiThinking = GuideArt.odi(MascotMood.thinking);

const _talkBackPage = GuidePage(
  'Bergerak dengan TalkBack',
  'Geser satu jari ke kanan untuk pindah ke elemen berikutnya, ke kiri untuk '
      'kembali. Ketuk dua kali di mana saja untuk menekan. Di laptop, tekan '
      'Tab untuk pindah dan Enter untuk menekan.',
  GuideArt.icon(Icons.touch_app_outlined),
);

const studentGuide = [
  GuideChapter('Masuk dan daftar', Icons.login, [
    GuidePage(
      'Membuka APREVO',
      'Nyalakan TalkBack, lalu buka APREVO. Layar sambutan membacakan pilihan '
          'Masuk dan Daftar.',
      _odiHappy,
    ),
    GuidePage(
      'Daftar akun baru',
      'Pilih Daftar, isi nama, email, dan password, lalu pilih peran Siswa. '
          'Peran tidak bisa diganti setelah dipilih.',
      GuideArt.icon(Icons.person_add_alt_1_outlined),
    ),
    GuidePage(
      'Masuk',
      'Pilih Masuk, lalu isi email dan password. Tombol mata membuat password '
          'terlihat supaya bisa dicek. Bisa juga masuk dengan Google.',
      GuideArt.icon(Icons.key_outlined),
    ),
    _talkBackPage,
  ]),
  GuideChapter('Kelas', Icons.groups_outlined, [
    GuidePage(
      'Bergabung ke kelas',
      'Minta kode akses 6 huruf dari guru. Di Beranda, ketik kodenya; huruf '
          'yang diketik dibacakan satu per satu. Lalu tekan Gabung.',
      GuideArt.icon(Icons.vpn_key_outlined),
    ),
    GuidePage(
      'Membuka kelas',
      'Kelasmu ada di Beranda. Pilih satu kelas untuk melihat materi, '
          'presensi, dan teman sekelas.',
      _odiHappy,
    ),
  ]),
  GuideChapter('Baca materi', Icons.menu_book_outlined, [
    GuidePage(
      'Memilih materi',
      'Di dalam kelas, pilih materi. Kerjakan pre-test dulu kalau diminta, '
          'lalu tekan Baca materi.',
      GuideArt.icon(Icons.library_books_outlined),
    ),
    GuidePage(
      'Pindah halaman',
      'Tombol Halaman berikutnya dan Halaman sebelumnya ada di bawah teks. '
          'Setiap pindah, nomor dan judul halaman dibacakan.',
      GuideArt.icon(Icons.import_contacts_outlined),
    ),
    GuidePage(
      'Gambar dan audio',
      'Gambar dibacakan sebagai "Gambar:" lalu deskripsinya. Kalau materinya '
          'rekaman suara, tombol Putar audio, Jeda audio, Mundur 10 detik, dan '
          'Maju 10 detik ada di atas transkrip.',
      GuideArt.icon(Icons.headphones_outlined),
    ),
    GuidePage(
      'Mencari di materi',
      'Buka Daftar halaman untuk lompat ke halaman tertentu, atau ketik kata '
          'di kolom Cari isi materi.',
      GuideArt.icon(Icons.search),
    ),
  ]),
  GuideChapter('Kuis', Icons.quiz_outlined, [
    GuidePage(
      'Pre-test dan post-test',
      'Setiap materi punya pre-test sebelum membaca dan post-test sesudahnya. '
          'Post-test terbuka setelah pre-test selesai.',
      _odiThinking,
    ),
    GuidePage(
      'Menjawab soal',
      'Dengarkan soal, pilih satu jawaban, lalu tekan Periksa Jawaban. Kamu '
          'mendengar bunyi pendek dan pesan benar atau salah.',
      GuideArt.icon(Icons.check_circle_outline),
    ),
    GuidePage(
      'Soal berikutnya',
      'Tekan Soal berikutnya. Setelah soal terakhir, tekan Kumpulkan dan lihat '
          'hasil. Jawaban yang sudah dikirim tidak bisa diganti.',
      GuideArt.icon(Icons.arrow_forward),
    ),
    GuidePage(
      'Jawaban dan pembahasan',
      'Tekan Lihat jawabanku untuk mendengar jawabanmu. Jawaban benar dan '
          'pembahasan terbuka setelah tenggat kuis lewat.',
      _odiCheer,
    ),
  ]),
  GuideChapter('Presensi', Icons.how_to_reg_outlined, [
    GuidePage(
      'Menekan Hadir',
      'Di dalam kelas, pilih Presensi. Saat guru membuka sesi, tekan tombol '
          'Hadir. Tombolnya menyebutkan jam tutup sesi.',
      GuideArt.icon(Icons.front_hand_outlined),
    ),
    GuidePage(
      'Riwayat presensi',
      'Setelah tercatat, pesan Presensi tercatat dibacakan. Rekap dan riwayat '
          'kehadiranmu ada di bawahnya.',
      _odiCheer,
    ),
  ]),
];

const teacherGuide = [
  GuideChapter('Masuk dan daftar', Icons.login, [
    GuidePage(
      'Daftar sebagai guru',
      'Pilih Daftar, isi nama, email, dan password, lalu pilih peran Guru. '
          'Peran tidak bisa diganti setelah dipilih.',
      _odiHappy,
    ),
    _talkBackPage,
    GuidePage(
      'Memakai di laptop',
      'APREVO juga bisa dibuka di browser laptop dengan akun yang sama. Tombol '
          'yang sedang dipilih dengan Tab diberi cincin kuning.',
      GuideArt.icon(Icons.laptop_outlined),
    ),
  ]),
  GuideChapter('Kelas', Icons.groups_outlined, [
    GuidePage(
      'Membuat kelas',
      'Di tab Kelas, tekan Buat Kelas, lalu ketik nama kelas, misalnya "7A '
          'Geografi".',
      GuideArt.icon(Icons.add_circle_outline),
    ),
    GuidePage(
      'Membagikan kode akses',
      'Setiap kelas punya kode akses 6 huruf. Bagikan ke siswa; tombol Salin '
          'menyalin kodenya.',
      GuideArt.icon(Icons.vpn_key_outlined),
    ),
    GuidePage(
      'Anggota kelas',
      'Siswa yang sudah bergabung ada di Anggota kelas. Dari sana, siswa juga '
          'bisa dikeluarkan.',
      _odiHappy,
    ),
  ]),
  GuideChapter('Baca materi', Icons.menu_book_outlined, [
    GuidePage(
      'Memeriksa halaman',
      'Di Kelola materi, pilih Lihat halaman materi untuk membaca materi '
          'seperti yang didengar siswa.',
      GuideArt.icon(Icons.import_contacts_outlined),
    ),
    GuidePage(
      'Memperbaiki teks dan gambar',
      'Tulisan dari foto, transkrip audio, dan deskripsi AI bisa salah. '
          'Perbaiki di Ubah teks halaman dan Gambar dan deskripsi.',
      GuideArt.icon(Icons.edit_note),
    ),
    GuidePage(
      'Menerbitkan materi',
      'Materi masih draf sampai saklar Publikasikan ke siswa dinyalakan. '
          'Siswa hanya melihat materi yang sudah terbit.',
      _odiCheer,
    ),
  ]),
  GuideChapter('Kuis', Icons.quiz_outlined, [
    GuidePage(
      'Pre-test dan post-test',
      'Setiap materi punya pre-test dan post-test. Masing-masing perlu minimal '
          'satu soal supaya materi bisa diterbitkan.',
      _odiThinking,
    ),
    GuidePage(
      'Jadwal kuis',
      'Atur waktu buka dan tenggat setiap kuis. Jawaban benar dan pembahasan '
          'terbuka untuk siswa setelah tenggat.',
      GuideArt.icon(Icons.event_outlined),
    ),
    GuidePage(
      'Hasil kuis',
      'Tab Hasil berisi nilai pre-test, post-test, rata-rata, dan soal yang '
          'paling banyak salah.',
      GuideArt.icon(Icons.insights_outlined),
    ),
  ]),
  GuideChapter('Presensi', Icons.how_to_reg_outlined, [
    GuidePage(
      'Membuka sesi',
      'Di dalam kelas, pilih Presensi, lalu Buka sesi presensi. Pilih waktu '
          'tutup: 15 menit, 30 menit, 1 jam, akhir hari, atau atur sendiri.',
      GuideArt.icon(Icons.timer_outlined),
    ),
    GuidePage(
      'Mengubah status',
      'Siswa yang tidak menekan Hadir sampai sesi ditutup dihitung alpa. Buka '
          'sesinya lalu pilih nama siswa untuk mengubah ke hadir, izin, sakit, '
          'atau alpa.',
      GuideArt.icon(Icons.fact_check_outlined),
    ),
  ]),
  GuideChapter('Unggah materi', Icons.cloud_upload_outlined, [
    GuidePage(
      'Memilih file',
      'Di halaman kelas, tekan Unggah materi. Bisa dokumen, presentasi, tabel, '
          'teks, foto halaman buku, atau rekaman audio.',
      GuideArt.icon(Icons.attach_file),
    ),
    GuidePage(
      'Menunggu proses',
      'File diubah menjadi halaman di latar belakang. Setiap langkahnya '
          'dibacakan sampai selesai.',
      _odiThinking,
    ),
    GuidePage(
      'Tempel teks',
      'Kalau isinya dari dokumen lain, tekan Tempel teks, tempel isinya, lalu '
          'periksa pratinjau pembagian halaman sebelum menyimpan.',
      GuideArt.icon(Icons.content_paste),
    ),
  ]),
  GuideChapter('Buat soal', Icons.edit_outlined, [
    GuidePage(
      'Menambah soal',
      'Di Kelola materi, tekan Tambah soal. Pilih jenis soal: pilihan ganda, '
          'benar atau salah, isian singkat, atau puzzle urutan.',
      GuideArt.icon(Icons.playlist_add),
    ),
    GuidePage(
      'Soal dengan AI',
      'Tekan Buat soal dengan AI untuk membuat draf soal dari isi materi. '
          'Periksa setiap draf sebelum disimpan.',
      GuideArt.icon(Icons.auto_awesome),
    ),
    GuidePage(
      'Menyalin soal',
      'Post-test bisa memakai soal pre-test lewat Salin soal dari pre-test, '
          'supaya kenaikan nilai bisa dibandingkan.',
      GuideArt.icon(Icons.copy),
    ),
  ]),
  GuideChapter('Progres siswa', Icons.trending_up, [
    GuidePage(
      'Tabel progres',
      'Di halaman kelas, pilih Progres siswa. Tabelnya berisi nilai pre-test, '
          'post-test, dan kenaikannya per siswa.',
      GuideArt.icon(Icons.table_chart_outlined),
    ),
    GuidePage(
      'Progres per siswa',
      'Pilih nama siswa untuk melihat semua kuisnya. Pre-test memakai '
          'percobaan pertama, post-test memakai percobaan terakhir.',
      _odiCheer,
    ),
  ]),
];

List<GuideChapter> guideFor(UserRole role) =>
    role == UserRole.teacher ? teacherGuide : studentGuide;
