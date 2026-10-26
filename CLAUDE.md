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
# supaya bisa diakses dari HP di Wi-Fi yang sama
.venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000

# alamat backend saat build (bisa juga diubah di layar "Alamat server")
flutter run --dart-define=API_BASE_URL=http://192.168.1.7:8000
```

Selalu jalankan `flutter analyze` setelah mengubah kode Dart, dan perbaiki
semua error sebelum menganggap tugas selesai.

## Struktur frontend

- `lib/main.dart`: memuat `Settings`, inisialisasi Supabase (kalau kunci
  terisi), lalu `SplashScreen`.
- `lib/config/supabase_config.dart`: URL proyek dan kunci anon. Kalau kunci
  belum diisi, aplikasi tidak bisa masuk atau daftar.
- `lib/config/api_config.dart`: alamat backend bawaan (`API_BASE_URL`,
  `10.0.2.2:8000` di Android, `localhost:8000` di web) dan `normalize`.
- `lib/services/settings.dart`: alamat server dan status onboarding yang
  disimpan di perangkat (`shared_preferences`).
- `lib/services/api_client.dart`: `ApiClient` (http + token Supabase, ulang
  sekali setelah 401) dan `ApiException` dengan pesan bahasa Indonesia.
- `lib/services/time_format.dart`: `formatDateTime` (bahasa Indonesia) dan
  `isoWithOffset` (waktu berzona untuk backend).
- `lib/theme/app_theme.dart`: `AppColors`, `AppType`, gaya tombol, `kTouchTarget`.
- `lib/models/models.dart`: model dari respons backend (`Subject`,
  `LessonMaterial`, `QuizInfo`, `MaterialSection`, `StudentQuestion`,
  `ReviewItem`, `SubjectResults`, dll), `Question` (soal guru), `starsFor`.
- `lib/data/app_store.dart`: `AppStore` (ChangeNotifier, singleton `store`).
  Akun memakai Supabase Auth, data lain lewat backend sesuai
  `docs/kontrak-api.md`. Setelah data berubah, `notifyListeners` membuat
  layar yang terbuka memuat ulang.
- `lib/services/speech.dart`: `Speech.speak` (TTS id-ID), `Speech.announce`
  (pengumuman screen reader).
- `lib/widgets/`: `load_view.dart` (`LoadView`: pesan memuat diumumkan,
  error di `ErrorCard` + tombol Coba lagi), `common.dart` (PrimaryButton,
  AppCard, ListRow, dll),
  `playful.dart` (PurpleScaffold, animasi), `mascot.dart` (maskot Odi),
  `nav_bar.dart` (menu bawah).
- `lib/screens/`: splash, welcome, login, register, `server_settings_screen`,
  `student/` (beranda, materi, `section_reader_screen`, kuis, hasil,
  `review_screen`), `teacher/` (mata pelajaran, unggah PDF, editor materi,
  `quiz_schedule_screen`, `results_screen`).
- `test/fake_server.dart`: server tiruan (`MockClient`) untuk tes. Tes tidak
  pernah menghubungi backend atau Supabase.

## Konsep aplikasi (keputusan terbaru)

- Dua peran: guru dan siswa. Peran dipilih saat daftar dan disimpan di
  metadata akun Supabase (`name`, `role`).
- Guru membuat mata pelajaran. Tiap mata pelajaran punya satu kode akses
  berupa 6 huruf kapital A-Z tanpa strip (contoh `KXPRTA`). Kode akses
  tidak lagi per materi.
- Siswa bergabung ke mata pelajaran dengan kode itu, lalu melihat semua
  materi yang sudah dipublikasikan di mata pelajaran tersebut.
- Materi ditampilkan per sub-bab. Siswa bisa mendengarkan tiap sub-bab dan
  berpindah antar sub-bab.
- Satu materi memakai satu jenis soal pilihan guru: pilihan ganda,
  benar/salah, isian singkat, atau puzzle urutan.
- Soal pilihan ganda hanya punya satu jawaban benar.
- Tiap materi punya pre-test dan post-test. Post-test terkunci sampai
  pre-test selesai.
- Guru mengatur jadwal tiap kuis: waktu buka dan waktu tutup (tenggat).
- Saat mengerjakan, tiap soal hanya diberi tahu benar atau salah, tanpa
  jawaban benar dan pembahasan.
- Setelah kuis selesai, siswa bisa melihat ulang soal dan jawabannya sendiri.
- Jawaban benar dan pembahasan baru terbuka setelah tenggat kuis lewat.
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
- Layar yang memuat data dari backend memakai `LoadView`, supaya pesan
  memuat dan error selalu dibacakan.

## Keamanan

- Repo ini publik.
- Jangan pernah membaca, menampilkan, atau meng-commit `backend/.env`.
- Kunci `service_role` hanya boleh ada di backend, tidak boleh masuk ke
  aplikasi Flutter. Aplikasi hanya memakai kunci anon.
- Jangan menulis email atau password akun asli di kode.

## Belum dikerjakan

- AI pembuat soal (`generateQuestions` di `app_store.dart` masih tiruan).
- Pengujian dengan TalkBack di perangkat Android.
- Butuh endpoint backend dulu:
  - Ubah dan hapus soal yang sudah tersimpan. Sekarang soal disusun sebagai
    draf di aplikasi lalu dikirim sekaligus, setelah itu hanya bisa dilihat.
  - Materi yang diketik tanpa PDF. Sekarang materi hanya dari unggah PDF.
  - Jenis soal per materi. Sekarang diambil dari soal pertama.
  - Deskripsi gambar per soal. Yang dibacakan baru `image_description` per
    sub-bab.
  - Daftar anggota mata pelajaran. Tab Siswa guru disusun dari data hasil.