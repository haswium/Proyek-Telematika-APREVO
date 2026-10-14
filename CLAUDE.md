# APREVO

Aplikasi belajar interaktif audio-first untuk siswa tunanetra. Proyek Telematika,
Teknik Komputer ITS.

- Frontend: Flutter (folder `lib/`), dikerjakan Luby.
- Backend: FastAPI + Supabase (folder `backend/`), dikerjakan Hasna.
- Pengguna utama memakai screen reader (TalkBack). Aksesibilitas adalah syarat
  utama, bukan tambahan.

## Perintah

```bash
flutter pub get
flutter analyze        # wajib bersih sebelum selesai
flutter test
flutter run -d chrome

# backend, dijalankan dari folder backend/
.venv\Scripts\python.exe -m uvicorn main:app --reload
```

Selalu jalankan `flutter analyze` setelah mengubah kode Dart, dan perbaiki
semua error sebelum menganggap tugas selesai.

## Struktur frontend

- `lib/main.dart`: inisialisasi Supabase (kalau kunci terisi), lalu `SplashScreen`.
- `lib/config/supabase_config.dart`: URL proyek dan kunci anon. Kalau kunci
  belum diisi, aplikasi berjalan dalam mode demo.
- `lib/theme/app_theme.dart`: `AppColors`, `AppType`, gaya tombol, `kTouchTarget`.
- `lib/models/models.dart`: `LessonMaterial`, `Question`, `GameType`, `TestKind`,
  `Attempt`, `Account`, `starsFor`.
- `lib/data/app_store.dart`: `AppStore` (ChangeNotifier, singleton `store`).
  Akun memakai Supabase Auth. Materi, soal, dan hasil MASIH data contoh di
  memori, belum tersambung ke tabel Supabase.
- `lib/services/speech.dart`: `Speech.speak` (TTS id-ID), `Speech.announce`
  (pengumuman screen reader).
- `lib/widgets/`: `common.dart` (PrimaryButton, AppCard, ListRow, dll),
  `playful.dart` (PurpleScaffold, animasi), `mascot.dart` (maskot Odi),
  `nav_bar.dart` (menu bawah).
- `lib/screens/`: splash, welcome, login, register, `student/`, `teacher/`.

## Konsep aplikasi (keputusan terbaru)

- Dua peran: guru dan siswa. Peran dipilih saat daftar dan disimpan di
  metadata akun Supabase (`name`, `role`).
- Guru membuat mata pelajaran. Tiap mata pelajaran punya satu kode akses
  berupa 6 huruf kapital A-Z tanpa strip (contoh `KXPRTA`). Kode akses
  tidak lagi per materi.
- Siswa bergabung ke mata pelajaran dengan kode itu, lalu melihat semua
  materi yang sudah dipublikasikan di mata pelajaran tersebut.
- Satu materi memakai satu jenis soal pilihan guru: pilihan ganda,
  benar/salah, isian singkat, atau puzzle urutan.
- Soal pilihan ganda hanya punya satu jawaban benar.
- Tiap materi punya pre-test dan post-test. Post-test terkunci sampai
  pre-test selesai.
- Tiap jawaban mendapat umpan balik rinci: jawaban siswa, jawaban benar, dan
  penjelasan.
- Skor 0 sampai 3 bintang (85% ke atas = 3, 60% ke atas = 2, ada yang benar =
  1) dan apresiasi dari maskot Odi.

## Aturan tampilan

- Hanya empat warna: ungu tua, ungu muda, putih, kuning. Jangan pakai merah,
  hijau, atau warna lain, termasuk di animasi. Benar dan salah dibedakan
  lewat ikon dan kata-kata.
- Latar ungu di semua layar (`PurpleScaffold`).
- Huruf hanya Poppins Bold (w700) dan Poppins SemiBold (w600), dibundel di
  `assets/fonts/` dan dipasang lewat `fontFamily` di tema. Gaya teks yang
  tidak mewarisi tema (tombol, chip, menu bawah) memakai `AppType.poppins`.
- Gaya playful dan tidak terlihat seperti template AI. Tanpa hiasan bintang
  atau garis di latar.
- Pakai warna dari `AppColors` dan gaya teks dari `AppType`. Jangan menulis
  kode warna baru di layar.

## Aturan aksesibilitas

- Area sentuh minimal `kTouchTarget` (56).
- Baris daftar dan pilihan jawaban dibungkus `Semantics` dengan satu label
  utuh dan `excludeSemantics: true`.
- Umpan balik dan pesan error memakai `liveRegion: true`.
- Urutan fokus layar soal diatur dengan `OrdinalSortKey`.
- Puzzle urutan memakai tombol Naikkan/Turunkan, jangan drag and drop.
- Hiasan (logo, ikon status, animasi) disembunyikan dari screen reader.
- Animasi berhenti kalau `MediaQuery.disableAnimations` aktif.
- Kalau TalkBack mati, umpan balik penting dibacakan lewat `Speech.speak`.

## Keamanan

- Repo ini publik.
- Jangan pernah membaca, menampilkan, atau meng-commit `backend/.env`.
- Kunci `service_role` hanya boleh ada di backend, tidak boleh masuk ke
  aplikasi Flutter. Aplikasi hanya memakai kunci anon.
- Jangan menulis email atau password akun asli di kode.

## Belum dikerjakan

- Menyambungkan materi, soal, dan hasil ke tabel Supabase. Struktur tabel
  perlu disepakati dengan backend dulu (misalnya pembeda pre-test dan
  post-test, kolom penjelasan, dan skor).
- AI pembuat soal (`generateQuestions` di `app_store.dart` masih tiruan).
- Unggah PDF materi.
- Pengujian dengan TalkBack di perangkat Android.