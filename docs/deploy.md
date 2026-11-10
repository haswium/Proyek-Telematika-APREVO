# Deploy APREVO

Backend berjalan di Render, sehingga aplikasi bisa dipakai tanpa laptop. Siswa
cukup memasang APK, tanpa mengisi alamat server.

Repo ini publik. Jangan menulis kunci, kata sandi, atau keystore di repo.

## 1. Sebelum mulai

- Kode yang mau dipakai sudah ada di branch `main` di GitHub. Render membaca dari
  sana, bukan dari laptop.
- Semua migrasi di `backend/migrations/` sudah dijalankan di Supabase.

## 2. Buat akun Render dan sambungkan repo

1. Buat akun di <https://render.com>. Paling mudah daftar memakai akun GitHub.
2. Di dashboard, pilih **New > Blueprint**.
3. Sambungkan akun GitHub, lalu pilih repo APREVO. Render membaca `render.yaml` dan
   menampilkan layanan `aprevo-backend`.
4. Isi variabel lingkungan yang diminta (langkah 3), lalu buat layanannya.
5. Tunggu sampai statusnya **Live**, lalu catat alamatnya, misalnya
   `https://aprevo-backend.onrender.com`. Kalau nama itu sudah dipakai orang lain,
   Render menambahkan akhiran, jadi alamat yang tampil di dashboard yang berlaku.

Setiap push ke `main` membuat Render men-deploy ulang secara otomatis.

## 3. Variabel lingkungan

Wajib diisi di dashboard Render (**Environment**):

| Variabel | Cara mendapatkan | Catatan |
|---|---|---|
| `SUPABASE_URL` | Supabase > Project Settings > API | Alamat proyek |
| `SUPABASE_KEY` | Supabase > Project Settings > API Keys, kunci `anon` | Sama dengan kunci di aplikasi |
| `SUPABASE_SERVICE_KEY` | Supabase > Project Settings > API Keys, kunci `service_role` | **Rahasia.** Hanya untuk backend, jangan pernah masuk ke aplikasi Flutter |
| `GEMINI_API_KEY` | Google AI Studio | **Rahasia.** Kalau kosong, backend tetap menyala, hanya fitur AI yang menolak |

Sudah diisi oleh `render.yaml`, tidak perlu diubah:

| Variabel | Nilai | Catatan |
|---|---|---|
| `PYTHON_VERSION` | `3.12.0` | Versi yang sudah diuji. Bawaan Render lebih baru |
| `ENABLE_DEBUG_ENDPOINTS` | `0` | Endpoint debug mati. Di Render tetap mati walau nilainya diubah menjadi `1`, karena kode juga memeriksa variabel `RENDER` |

Opsional, tambahkan sendiri kalau perlu:

| Variabel | Kegunaan |
|---|---|
| `CORS_ORIGINS` | Origin versi web, dipisah koma. Aplikasi Android tidak memerlukannya |
| `GEMINI_DELAY_SECONDS` | Jeda antar panggilan Gemini, bawaan 4 detik |
| `GEMINI_RATE_LIMIT_PAUSE_SECONDS` | Jeda setelah kena batas Gemini, bawaan 30 detik |

`TEST_LOGIN_EMAIL` dan `TEST_LOGIN_PASSWORD` tidak perlu diisi di Render, karena
hanya dipakai endpoint debug.

Render hanya meminta variabel `sync: false` saat layanan pertama kali dibuat.
Variabel baru setelahnya ditambahkan sendiri di dashboard.

## 4. Periksa backend

Ganti alamatnya dengan alamat layananmu:

```bash
curl https://proyek-telematika-aprevo.onrender.com/health
# {"status":"ok"}

curl -i https://proyek-telematika-aprevo.onrender.com/test-supabase
# HTTP 404: endpoint debug mati
```

Permintaan pertama bisa lama kalau layanannya sedang tidur.

Periksa juga variabel Supabase. Endpoint ini tidak pernah menampilkan nilai
variabel, hanya nama variabel yang bermasalah:

```bash
curl https://proyek-telematika-aprevo.onrender.com/health/config
# {"ok":true,"problems":[]}
```

### Kalau aplikasi menampilkan "Token tidak valid"

Backend memeriksa token login dengan memanggil Supabase Auth
(`<SUPABASE_URL>/auth/v1/user`) memakai `SUPABASE_URL` dan `SUPABASE_KEY`. Tidak
ada JWT secret atau JWKS yang perlu diisi. Satu-satunya perbedaan perilaku di
Render (variabel `RENDER` terisi) adalah endpoint debug yang selalu mati, dan itu
tidak memengaruhi login. Jadi kalau token yang sama diterima backend lokal tetapi
ditolak Render, penyebabnya hampir selalu variabel di dashboard Render.

1. Buka `/health/config`. Kalau `ok` bernilai `false`, `problems` menyebut
   variabel mana yang salah, misalnya:
   - `SUPABASE_URL kosong`, atau `SUPABASE_URL bukan alamat proyek <ref>.supabase.co`
   - `SUPABASE_KEY adalah kunci service_role, seharusnya anon`
   - `SUPABASE_KEY milik proyek Supabase lain, bukan proyek di SUPABASE_URL`
2. Bandingkan tanpa menyalin nilainya ke mana pun. Di Render > layanan >
   **Environment**, klik ikon mata di `SUPABASE_URL` dan `SUPABASE_KEY`, lalu
   cocokkan dengan Supabase > Project Settings > API:
   - `SUPABASE_URL` harus sama dengan Project URL, yaitu proyek yang sama dengan
     `SUPABASE_URL` di `config/app_env.json` aplikasi.
   - `SUPABASE_KEY` harus kunci `anon` (atau `publishable`) dari proyek itu, sama
     dengan `SUPABASE_ANON_KEY` di `config/app_env.json`.
   - `SUPABASE_SERVICE_KEY` harus kunci `service_role` (atau `secret`) dari
     proyek yang sama.
   Spasi, baris baru, dan tanda kutip di awal atau akhir nilai dibuang otomatis
   oleh backend.
3. Setelah mengubah variabel, pilih **Save, rebuild, and deploy**. Render tidak
   memakai nilai baru sebelum layanan di-deploy ulang.
4. Buka Render > **Logs**. Alasan gagal dicatat tanpa token:
   - `Konfigurasi Supabase: ...` saat server menyala, isinya sama dengan
     `/health/config`.
   - `Verifikasi token gagal: status 403, kode bad_jwt, ...` artinya Supabase
     menolak tokennya. Penyebabnya token dari proyek lain (cek langkah 2), atau
     memang kedaluwarsa.
   - `SUPABASE_KEY ditolak Supabase` artinya kunci anon salah. Aplikasi mendapat
     pesan "Server belum dikonfigurasi dengan benar", bukan "Token tidak valid".
   - `Verifikasi token gagal: ConnectError ...` artinya Render tidak bisa
     menghubungi Supabase, biasanya karena `SUPABASE_URL` salah ketik.

## 5. Arahkan aplikasi ke Render

Di `lib/config/api_config.dart`, ganti `productionBaseUrl` dengan alamat dari
langkah 2:

```dart
static const String productionBaseUrl = 'https://proyek-telematika-aprevo.onrender.com';
```

Untuk pengembangan dengan backend di laptop, alamatnya diberikan saat menjalankan
aplikasi:

```bash
flutter run --dart-define-from-file=config/app_env.json --dart-define=API_BASE_URL=http://10.0.2.2:8000       # emulator
flutter run --dart-define-from-file=config/app_env.json --dart-define=API_BASE_URL=http://192.168.1.7:8000    # HP, Wi-Fi sama
```

### Menu pengembang

Alamat server tidak tampil untuk siswa. Untuk membukanya, ketuk baris **Tentang
APREVO** 7 kali di layar Masuk atau Profil. Dengan TalkBack, ketuk dua kali 7 kali.
TalkBack menyebutkan sisa ketukannya.

- APK release hanya bisa memakai alamat `https`. Alamat `http` hanya jalan di build
  debug dan profile, supaya token login tidak terkirim tanpa enkripsi.
- HP yang pernah menyimpan alamat lain tetap memakai alamat itu. Tekan **Pakai
  alamat bawaan** di menu ini untuk kembali ke Render.

## 6. Buat keystore (sekali saja)

APK untuk siswa ditandatangani dengan kunci milik proyek. Update hanya bisa dipasang
kalau kuncinya sama dengan APK sebelumnya.

1. Buat keystore **di luar folder repo**. `keytool` ada di folder
   `jbr\bin` di dalam folder instalasi Android Studio.

   ```bash
   keytool -genkeypair -v -keystore D:/rahasia/aprevo-release.jks -alias aprevo -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Buat file `android/key.properties`:

   ```properties
   storeFile=D:/rahasia/aprevo-release.jks
   storePassword=<kata sandi keystore>
   keyAlias=aprevo
   keyPassword=<kata sandi kunci>
   ```

3. Pastikan keduanya tidak ikut git. Perintah ini harus menampilkan aturan
   `.gitignore` untuk tiap file:

   ```bash
   git check-ignore -v android/key.properties android/aprevo-release.jks
   ```

> **Simpan cadangannya sekarang.** Simpan file `.jks` dan kedua kata sandinya di dua
> tempat yang aman di luar laptop ini, misalnya pengelola kata sandi dan penyimpanan
> pribadi yang terenkripsi. Bagikan ke anggota tim yang berhak saja, jangan lewat grup
> atau repo. Kalau keystore atau kata sandinya hilang, update tidak bisa dipasang di
> atas aplikasi lama: setiap siswa harus mencopot aplikasi dulu, lalu memasang ulang.

Tanpa `android/key.properties`, `flutter build apk --release` sengaja gagal, supaya
APK tidak terbagikan dengan kunci yang salah.

## 7. Build APK release

Alamat dan kunci Supabase tidak ada di kode. Keduanya masuk saat build dari
`config/app_env.json`, yang tidak di-commit.

1. Kalau `config/app_env.json` belum ada, salin contohnya:

   ```bash
   cp config/app_env.example.json config/app_env.json
   ```

   Lalu isi `SUPABASE_URL` dan `SUPABASE_ANON_KEY` dari Supabase > Project Settings >
   API Keys. Pakai kunci `anon`, jangan pernah kunci `service_role`.
2. Untuk update, naikkan angka setelah `+` pada `version` di `pubspec.yaml`, misalnya
   dari `1.0.0+1` ke `1.0.1+2`. Android menolak update dengan angka yang sama atau
   lebih kecil.
3. Jalankan:

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --release --dart-define-from-file=config/app_env.json
   ```

   Tanpa file itu, atau kalau isinya kosong atau belum benar, build sengaja gagal,
   supaya tidak ada APK yang tidak bisa dipakai masuk atau daftar.
4. Hasilnya ada di `build/app/outputs/flutter-apk/app-release.apk`.
5. Pasang dulu di satu HP, lalu cek `docs/uji-talkback.md` bagian 25.

## Login Google

Lakukan sekali, sebelum APK dengan tombol Google dibagikan. Nama menu di dashboard
bisa sedikit berubah. Ganti `ID-PROYEK` dengan ID proyek Supabase (bagian depan
`SUPABASE_URL`).

### A. Database Supabase

Buka **SQL Editor**, lalu jalankan isi `backend/migrations/006_pilih_peran.sql`.
Lakukan ini sebelum Google diaktifkan. Tanpa migrasi ini akun Google baru otomatis
menjadi siswa, sehingga pilihan Guru tidak berlaku.

### B. Google Cloud (<https://console.cloud.google.com>)

1. Buat atau pilih proyek.
2. **APIs & Services > OAuth consent screen**: pilih **External**, lalu isi nama
   aplikasi `APREVO` dan email kontak. Cakupan yang dipakai hanya `openid`, `email`,
   dan `profile`.
3. Selama statusnya **Testing**, hanya email di **Test users** yang bisa masuk, jadi
   tambahkan akun uji. Sebelum dibagikan ke siswa, ubah ke **In production**.
4. **APIs & Services > Credentials > Create credentials > OAuth client ID**, lalu
   pilih jenis **Web application**, bukan Android, karena yang menghubungi Google
   adalah Supabase.
5. Di **Authorized redirect URIs**, isi:

   ```text
   https://ID-PROYEK.supabase.co/auth/v1/callback
   ```

6. Simpan, lalu catat **Client ID** dan **Client secret**. Client secret bersifat
   **rahasia** dan hanya diisi di dashboard Supabase, jangan masuk ke aplikasi atau
   repo.

### C. Dashboard Supabase

1. **Authentication > Sign In / Providers > Google**: aktifkan, lalu tempel Client ID
   dan Client secret.
2. **Authentication > URL Configuration > Redirect URLs**: tambahkan persis:

   ```text
   id.aprevo.app://login-callback
   ```

   Alamat ini harus sama dengan `kAuthRedirectUrl` di
   `lib/services/google_auth.dart` dan intent-filter di `AndroidManifest.xml`.

### D. Backend dan aplikasi

1. Backend harus sudah memuat `POST /me/role`. Render men-deploy-nya setelah kode
   masuk ke `main`.
2. Build APK seperti langkah 7, karena intent-filter ada di dalam APK.

### Kalau login Google bermasalah

| Gejala | Yang diperiksa |
|---|---|
| Google menampilkan `redirect_uri_mismatch` | Authorized redirect URIs di langkah B5 |
| Google menampilkan "Access blocked" | Email ada di Test users, atau status sudah In production |
| Browser berhenti di halaman Site URL atau `localhost` | Redirect URLs di langkah C2 |
| Pesan `Unsupported provider` | Google sudah diaktifkan di langkah C1 |
| Browser tidak kembali ke aplikasi | APK sudah dibuat ulang setelah intent-filter ditambahkan |
| Memilih peran gagal dengan 404 | Backend di Render sudah memuat `POST /me/role` |
| Guru ditolak dengan "Hanya guru yang boleh..." | Migrasi di langkah A sudah dijalankan sebelum akun itu dibuat |

## 8. Bagikan ke siswa

1. Bagikan file APK, misalnya lewat tautan Google Drive. Jangan menaruh APK di repo.
2. Di HP siswa, buka file APK, lalu izinkan pemasangan dari aplikasi tersebut saat
   diminta. Google Play Protect bisa memperingatkan karena aplikasi ini tidak berasal
   dari Play Store. Pilih pasang tetap. Dialog ini milik Android, jadi bantu siswa saat
   pertama kali memasang.
3. Siswa membuka aplikasi, mendaftar atau masuk, lalu bergabung ke kelas dengan kode
   akses. Tidak ada alamat yang perlu diisi.

## Batasan paket gratis Render

- **Server tidur:** setelah 15 menit tanpa trafik, layanan tidur dan butuh sekitar satu
  menit untuk bangun. Aplikasi menampilkan dan mengumumkan "Menghubungkan ke server,
  mohon tunggu". Guru bisa membuka aplikasi beberapa menit sebelum kelas supaya server
  sudah bangun.
- **Restart:** Render bisa memulai ulang layanan kapan saja. Proses deskripsi gambar
  disimpan di memori, jadi ikut berhenti. Gambar yang selesai tetap tersimpan, dan
  guru bisa mengulang sisanya.
- **CPU dan memori:** paket gratis hanya 0,1 CPU dan 512 MB, jadi memproses PDF lebih lambat daripada di laptop. **Uji unggah PDF 20 MB** setelah deploy.
  Kalau layanan restart saat memproses PDF besar (terlihat di menu **Logs**), kecilkan
  PDF atau naikkan paket.
- **Berkas:** penyimpanan di server hilang saat restart. APREVO menyimpan PDF dan gambar
  di Supabase Storage, jadi tidak terpengaruh.
- **Jam pakai:** 750 jam per bulan per workspace. Saat tidur tidak terhitung. Kalau
  habis, layanan berhenti sampai bulan berikutnya.

## Kalau ada masalah

| Gejala | Yang diperiksa |
|---|---|
| Deploy gagal saat build | Menu **Logs** di Render, cek baris `pip install` |
| Layanan langsung berhenti | Variabel `SUPABASE_*` sudah terisi semua |
| Aplikasi menunggu lama, lalu "Server terlalu lama menjawab" | Status layanan di dashboard, dan menu **Logs** |
| Aplikasi "Tidak bisa terhubung ke server" | Internet HP, dan `productionBaseUrl` sudah alamat yang benar |
| Error di server | Cari `SERVER_ERROR` di menu **Logs** |
| Fitur AI menolak | `GEMINI_API_KEY` sudah terisi |
