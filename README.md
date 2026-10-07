# APREVO

Media pembelajaran interaktif audio-first untuk siswa tunanetra (Flutter + Supabase).

Folder `lib/` ini berisi frontend tahap awal. Datanya masih data contoh di memori
(`lib/data/app_store.dart`), belum tersambung ke Supabase.

## Menjalankan di VS Code

Di dalam folder repo (hasil `git clone`), jalankan sekali:

```bash
flutter create --project-name aprevo --org id.ac.its .
flutter pub add flutter_tts supabase_flutter google_fonts
```

Lalu salin `lib/` dan `test/` dari zip ini ke folder repo (timpa `lib/main.dart`
dan `test/widget_test.dart` buatan `flutter create`), kemudian:

```bash
flutter analyze
flutter run
```

Supaya tombol "Dengarkan" berbunyi di Android 11 ke atas, tambahkan ini di
`android/app/src/main/AndroidManifest.xml`, di dalam `<manifest>` (sejajar
dengan `<application>`):

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.TTS_SERVICE" />
    </intent>
</queries>
```

## Menyambungkan ke Supabase

Buka `lib/config/supabase_config.dart` dan tempel kunci `anon` `public` dari
dashboard Supabase (Settings > API Keys) ke `anonKey`. Jangan pernah menaruh
kunci `service_role` di aplikasi.

- Kunci terisi: masuk dan daftar memakai Supabase Auth. Akun tersimpan, dan
  aplikasi mengingat sesi masuk terakhir.
- Kunci belum terisi: mode demo dengan akun contoh di bawah.

Yang sudah tersambung baru akun (masuk, daftar, keluar). Materi, soal, dan
hasil masih data contoh di `lib/data/app_store.dart`.

## Mencoba

- Dengan Supabase: pilih Daftar, isi nama, email, password, dan peran. Kalau
  Supabase meminta konfirmasi, klik tautan di email lalu Masuk.
- Mode demo: guru `guru@aprevo.id`, siswa `siswa@aprevo.id`, password `123456`.
- Kode materi contoh: `APV-7K29` (Fotosintesis), `APV-3NPS` (Sistem
  Pernapasan), `APV-D4AR` (Daur Air), `APV-TS8X` (Tata Surya).
- "Lupa password" dan "Masuk dengan Google" baru tombolnya saja.

## Tampilan

- **Empat warna saja:** ungu tua, ungu muda, putih, kuning. Tidak ada merah
  atau hijau; benar dan salah dibedakan lewat ikon dan kata-kata.
- **Latar ungu** di semua layar (`PurpleScaffold` di `widgets/playful.dart`),
  dengan kartu putih bergaya stiker: garis tepi ungu tua dan bayangan padat.
- **Huruf:** Poppins, dua ketebalan saja: Bold untuk judul dan SemiBold untuk
  isi (lewat `google_fonts`, diunduh saat pertama dipakai).
- **Menu bawah** berwarna ungu tua dengan pil kuning di tab aktif. Guru: Materi, Siswa, Hasil, Profil. Siswa: Belajar, Progres,
  Profil. Tab "Games" dari Figma tidak ada karena soal dan tes dibuka dari
  dalam materinya.

## Alur layar awal (mengikuti Figma)

Splash (pindah sendiri) -> Sambutan (Masuk / Daftar) -> Masuk atau Daftar ->
untuk siswa: layar "Siap untuk belajar?" -> beranda. Masuk memakai satu form
untuk guru dan siswa; peran dipilih sekali saat daftar.

## Alur belajar

Tidak ada ruang belajar: **tiap materi punya kode akses sendiri**, dibuat
otomatis saat guru membuat materi. Siswa memasukkan kode untuk membuka materi
itu, dan bisa mengikuti banyak materi.

Satu materi = satu paket: isi materi, **satu jenis soal** pilihan guru (quiz,
benar/salah, isian singkat, atau puzzle urutan), lalu **pre-test** dan
**post-test** dengan jenis soal itu.

Siswa menjalani tiga langkah per materi: pre-test, dengarkan materi, post-test
(terkunci sampai pre-test selesai). Tiap jawaban mendapat umpan balik rinci:
jawaban siswa, jawaban yang benar, dan penjelasan dari guru. Hasil akhir berupa
0 sampai 3 bintang (85% ke atas = 3, 60% ke atas = 2, ada yang benar = 1) dan
apresiasi dari Odi, plus perbandingan dengan pre-test.

## Odi, maskot APREVO

Gurita kecil ungu muda dengan headphone kuning, digambar dengan kode di
`lib/widgets/mascot.dart` (tanpa file gambar). TalkBack membacakan deskripsinya,
dan mengetuk Odi membacakan deskripsi itu dengan suara.

## Struktur

```
lib/
  main.dart
  config/supabase_config.dart   URL proyek dan kunci anon
  theme/app_theme.dart          palet empat warna, gaya teks, gaya tombol
  models/models.dart            LessonMaterial, Question, Attempt, Account
  data/app_store.dart           data contoh; titik sambung ke Supabase
  services/speech.dart          announce (TalkBack) dan speak (TTS)
  widgets/common.dart           tombol, kartu, baris daftar
  widgets/mascot.dart           Odi dan balon ucapannya
  widgets/nav_bar.dart          menu bawah
  widgets/playful.dart          animasi, logo gelombang suara, skor bintang
  screens/
    splash_screen.dart, welcome_screen.dart
    login_screen.dart, register_screen.dart
    auth_flow.dart              pindah ke beranda, keluar, kolom isian
    profile_tab.dart            tab Profil untuk guru dan siswa
    student/  onboarding, beranda (kode akses + daftar materi), langkah belajar, tes, hasil
    teacher/  daftar materi, editor materi (kode, soal, siswa, hasil), form soal
```

## Pola aksesibilitas yang sudah diterapkan

- Setiap baris daftar dan pilihan jawaban dibaca sebagai satu tombol dengan
  satu label (`Semantics` + `excludeSemantics`).
- Urutan fokus layar soal diatur dengan `OrdinalSortKey`: info soal, tombol
  dengarkan, deskripsi gambar, pertanyaan, jawaban, umpan balik, tombol kirim.
- Umpan balik benar/salah dan pesan error memakai `liveRegion`, jadi langsung
  dibacakan tanpa perlu dicari.
- Pindah soal dan pindah item diumumkan lewat `SemanticsService.announce`.
- Puzzle urutan memakai tombol "Naikkan" dan "Turunkan", tanpa drag and drop.
- Elemen hiasan (logo, batang progres, ikon status) disembunyikan dari
  screen reader.
- Area sentuh minimal 56 dp.
- Semua animasi hanya hiasan dan berhenti kalau "Hapus animasi" dinyalakan
  di pengaturan aksesibilitas HP.
- Kalau TalkBack mati, umpan balik dan hasil dibacakan otomatis lewat TTS.

## Belum dikerjakan

- Sambungan Supabase untuk tabel dan storage, serta AI Game Generator asli.
  `generateQuestions` di `app_store.dart` masih tiruan.
- Unggah PDF. Materi sementara diketik sebagai teks.
- Pengujian TalkBack di perangkat asli.
