# Uji TalkBack APREVO

Daftar langkah untuk dicoba langsung di HP Android dengan TalkBack menyala.
Isi kolom **Hasil** dengan `OK` atau `GAGAL`, lalu tulis apa yang terdengar
di kolom **Catatan** kalau berbeda dari yang seharusnya.

- Tanggal uji:
- HP dan versi Android:
- Versi TalkBack:
- Penguji:

## Persiapan

1. Pasang aplikasi ke HP: sambungkan HP lewat USB (USB debugging aktif),
   lalu jalankan `flutter run`.
   - Kalau ingin daftar materi siswa diambil dari backend, jalankan backend
     dengan `--host 0.0.0.0`, lalu jalankan aplikasi dengan
     `flutter run --dart-define=API_BASE_URL=http://<IP-laptop>:8000`.
     HP dan laptop harus satu Wi-Fi. Kalau backend tidak dijalankan, layar
     Materi Saya akan menampilkan pesan gagal; itu juga perlu diuji.
2. Siapkan dua akun: satu **siswa** dan satu **guru**. Kalau belum ada,
   buat lewat layar Daftar saat pengujian.
3. Nyalakan TalkBack: Setelan > Aksesibilitas > TalkBack.
4. Atur bahasa suara TalkBack ke Bahasa Indonesia (Setelan TalkBack >
   Setelan text-to-speech).

Gestur yang dipakai:

| Gestur | Fungsi |
|---|---|
| Geser kanan / kiri satu jari | Pindah ke elemen berikutnya / sebelumnya |
| Ketuk dua kali | Aktifkan elemen yang sedang difokus |
| Geser bawah lalu kanan | Kembali (sama dengan tombol kembali) |
| Geser atas lalu bawah, pilih "Judul" | Lompat antarjudul |

Kode akses contoh yang selalu tersedia di aplikasi (data contoh di memori):

| Kode | Materi | Jenis soal |
|---|---|---|
| `APV-7K29` | Fotosintesis | Quiz (pilihan ganda) |
| `APV-3NPS` | Sistem Pernapasan | Benar atau Salah |
| `APV-D4AR` | Daur Air | Puzzle Urutan |
| `APV-TS8X` | Tata Surya | Isian Singkat |

## Pemeriksaan umum (berlaku di semua layar)

Periksa sambil mengerjakan layar-layar di bawah. Isi sekali di akhir.

| No | Yang diperiksa | Yang seharusnya | Hasil | Catatan |
|---|---|---|---|---|
| U1 | Tombol kembali di kiri atas | Terbaca "Kembali, tombol" (bukan "Back") | | |
| U2 | Hiasan (logo gelombang suara, gelembung latar, ikon centang, batang progres) | Tidak pernah difokus TalkBack | | |
| U3 | Semua tombol | Terbaca nama tombolnya, tidak ada yang hanya "tombol" tanpa nama | | |
| U4 | Ukuran tombol | Semua tombol mudah diketuk dengan satu jari, tidak perlu presisi | | |
| U5 | Pesan error dan umpan balik | Dibacakan **satu kali** saja, tidak dobel | | |
| U6 | Pesan error yang sama muncul dua kali berturut-turut | Tetap dibacakan pada kali kedua | | |
| U7 | Setelan > Aksesibilitas > Hapus animasi, lalu buka aplikasi | Odi, logo, dan putaran loading berhenti bergerak | | |

## 1. Layar pembuka (splash)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 1.1 | Buka aplikasi | "APREVO, judul", lalu "Belajar lebih mudah, satu suara" | | |
| 1.2 | Tunggu sekitar 2 detik | Pindah sendiri ke layar sambutan | | |

## 2. Layar sambutan

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 2.1 | Geser kanan dari awal sampai akhir | Urutan: "APREVO, judul", "Belajar lebih mudah, satu suara", kalimat penjelasan, "Masuk, tombol", "Daftar, tombol" | | |
| 2.2 | Fokus ke "Daftar", ketuk dua kali | Layar Daftar terbuka | | |

## 3. Layar Daftar

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 3.1 | Geser kanan dari awal | "Daftar ke APREVO, judul" (satu kalimat, tidak terpotong dua) | | |
| 3.2 | Geser ke pilihan peran | "Daftar sebagai Siswa, dipilih, tombol", lalu "Daftar sebagai Guru, tombol" | | |
| 3.3 | Ketuk dua kali "Daftar sebagai Guru" | Terdengar "dipilih" untuk Guru | | |
| 3.4 | Kembalikan pilihan ke Siswa | Siswa terbaca "dipilih" lagi | | |
| 3.5 | Geser ke kolom isian | "Nama, kotak edit", "Email, kotak edit", "Password, kotak edit". Nama kolom terbaca, bukan hanya "kotak edit" | | |
| 3.6 | Geser ke tombol mata di kolom password | "Tampilkan password, tombol". Setelah diketuk dua kali: "Sembunyikan password" | | |
| 3.7 | Kosongkan semua kolom, ketuk dua kali "Daftar" | "Nama belum diisi." dibacakan satu kali | | |
| 3.8 | Ketuk dua kali "Daftar" sekali lagi tanpa mengubah apa pun | "Nama belum diisi." dibacakan lagi | | |
| 3.9 | Isi nama, email salah (tanpa @), ketuk "Daftar" | "Email belum benar. Contoh: nama@email.com" | | |
| 3.10 | Isi password kurang dari 6 huruf, ketuk "Daftar" | "Password minimal 6 karakter." | | |
| 3.11 | Fokus ke "Sudah punya akun? Masuk" | Terbaca sebagai tombol | | |

## 4. Layar Masuk

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 4.1 | Geser kanan dari awal | "Masuk ke APREVO, judul", "Email, kotak edit", "Password, kotak edit", "Tampilkan password, tombol", "Lupa password?, tombol" | | |
| 4.2 | Kata "atau" di antara tombol | Tidak difokus | | |
| 4.3 | Ketuk dua kali "Masuk" dengan kolom kosong | "Email belum benar..." dibacakan satu kali | | |
| 4.4 | Isi email benar dan password salah, ketuk "Masuk" | "Email atau password salah." | | |
| 4.5 | Ketuk dua kali "Lupa password?" | Pesan "Lupa password akan aktif..." dibacakan satu kali | | |
| 4.6 | Masuk dengan akun **siswa** | Pindah ke layar sambutan siswa (pertama kali) atau Materi Saya | | |

## 5. Sambutan siswa (hanya muncul pertama kali)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 5.1 | Geser kanan dari awal | "Siap untuk belajar?, judul", kalimat penjelasan, lalu tiga poin. Ikon centang dan ikon headphone tidak difokus | | |
| 5.2 | Geser kanan sampai habis | Tidak ada tombol "Dengarkan". Aplikasi tidak bersuara sendiri | | |
| 5.3 | Ketuk dua kali "Mulai Belajar" | Pindah ke Materi Saya | | |

## 6. Materi Saya (tab Belajar siswa)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 6.1 | Buka layar ini | "Sedang memuat materimu. Tunggu sebentar." dibacakan sendiri | | |
| 6.2 | Kalau backend **tidak** jalan | "Gagal memuat materi. Tidak bisa terhubung ke server..." dibacakan sendiri, lalu ada tombol "Coba lagi" | | |
| 6.3 | Ketuk dua kali "Coba lagi" | Pesan memuat dibacakan lagi | | |
| 6.4 | Kalau backend jalan | Judul "Materi yang kamu ikuti (jumlah)", lalu tiap materi terbaca dalam satu kalimat: "Materi [judul]. [status]" | | |
| 6.5 | Fokus ke balon Odi | Hanya teks balon yang terbaca. Gambar Odi di sebelahnya tidak difokus | | |
| 6.6 | Fokus ke kolom kode | "Kode akses materi, kotak edit" | | |
| 6.7 | Kosongkan kolom, ketuk dua kali "Buka materi" | "Kode akses belum diisi." dibacakan satu kali | | |
| 6.8 | Isi `XXX`, ketuk "Buka materi" | "Kode akses tidak ditemukan..." | | |
| 6.9 | Isi `APV-7K29`, ketuk "Buka materi" | Layar materi Fotosintesis terbuka | | |
| 6.10 | Menu bawah | "Belajar, tab 1 dari 3, dipilih", "Progres, tab 2 dari 3", "Profil, tab 3 dari 3" | | |

## 7. Layar Materi (satu materi)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 7.1 | Geser kanan dari awal | "Kode akses: A P V 7 K 2 9" (dieja per huruf), lalu judul materi sebagai judul, lalu "Jenis soal: Quiz" | | |
| 7.2 | Kartu materi | "Materi, Fotosintesis" dalam satu fokus | | |
| 7.3 | Ketuk dua kali "Baca materi" | Daftar sub bab terbuka. Tidak ada tombol "Dengarkan" atau "Hentikan suara" | | |
| 7.4 | Ketuk dua kali "Baca teks" | Layar teks materi terbuka. Isinya terbaca. Untuk materi dari backend: "Isi materi belum tersedia." | | |
| 7.5 | Kartu Pre-test | "Pre-test. 2 soal. Belum dikerjakan" dalam satu fokus, lalu tombol "Mulai Pre-test" | | |
| 7.6 | Kartu Post-test sebelum pre-test | "Post-test. 3 soal. Terkunci. Kerjakan pre-test dulu" | | |
| 7.7 | Ketuk dua kali "Mulai Post-test" | "Kerjakan pre-test dulu, ya." dibacakan satu kali | | |
| 7.8 | Ketuk dua kali "Mulai Pre-test" | Layar soal terbuka | | |

## 8. Layar soal: pilihan ganda (APV-7K29)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 8.1 | Buka layar soal | Terdengar "Soal 1 dari 2. Pilih satu jawaban yang benar." | | |
| 8.2 | Geser kanan dari awal | Urutan: "Soal 1 dari 2, judul", instruksi, pertanyaan, pilihan A sampai D, "Periksa Jawaban" | | |
| 8.3 | Batang progres | Tidak difokus | | |
| 8.4 | Fokus ke pilihan | "Pilihan A, Akar, tombol" dalam satu fokus (huruf dan teks tidak terpisah) | | |
| 8.5 | Ketuk dua kali satu pilihan | Terdengar "dipilih" | | |
| 8.6 | Fokus ke "Periksa Jawaban" sebelum memilih | Terbaca "dinonaktifkan" | | |
| 8.7 | Pilih jawaban **salah**, ketuk "Periksa Jawaban" | Umpan balik dibacakan sendiri, satu kali: "Belum tepat... Jawabanmu: ... Jawaban yang benar: ... Penjelasan: ..." | | |
| 8.8 | Setelah umpan balik, geser kanan | Kartu umpan balik ada di antara pilihan jawaban dan tombol "Soal berikutnya" | | |
| 8.9 | Ketuk dua kali "Soal berikutnya" | Terdengar "Soal 2 dari 2..." | | |
| 8.10 | Jawab **benar** | Umpan balik "Benar! Hebat!" dengan jawaban dan penjelasan | | |

## 9. Layar soal: benar atau salah (APV-3NPS)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 9.1 | Fokus ke pilihan | "Benar, tombol" dan "Salah, tombol" | | |
| 9.2 | Pilih lalu periksa | Umpan balik dibacakan satu kali, berisi jawabanmu dan jawaban yang benar | | |

## 10. Layar soal: isian singkat (APV-TS8X)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 10.1 | Fokus ke kolom jawaban | "Jawabanmu, kotak edit" | | |
| 10.2 | Ketik jawaban, tekan selesai di keyboard | Jawaban diperiksa dan umpan balik dibacakan | | |
| 10.3 | Fokus ke kolom setelah menjawab | Terbaca dinonaktifkan | | |

## 11. Layar soal: puzzle urutan (APV-D4AR)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 11.1 | Fokus ke satu item | "Posisi 1 dari 3: [teks item]" dalam satu fokus | | |
| 11.2 | Geser kanan dari item | "Naikkan [teks item], tombol", "Turunkan [teks item], tombol" | | |
| 11.3 | Tombol "Naikkan" di item pertama | Terbaca dinonaktifkan | | |
| 11.4 | Ketuk dua kali "Turunkan" di item pertama | Terdengar "[teks item] pindah ke urutan 2." | | |
| 11.5 | Setelah memindah, geser ke item lagi | Posisi dan teks item sudah sesuai urutan baru | | |
| 11.6 | Periksa jawaban yang salah | Umpan balik menyebut "Yang perlu diperbaiki: Urutan ... seharusnya ..." | | |
| 11.7 | Tidak ada gerakan seret (drag) yang diperlukan | Semua bisa diselesaikan dengan tombol | | |

## 12. Layar hasil

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 12.1 | Selesaikan satu tes | Ringkasan dibacakan sendiri: "[Pre-test] [judul] selesai. Kamu benar ... dari ... soal, ... dari 3 bintang..." | | |
| 12.2 | Geser kanan dari awal | Gambar Odi tidak difokus. Fokus pertama langsung ke ringkasan hasil | | |
| 12.3 | Bintang | Tidak dibaca per ikon, sudah masuk dalam ringkasan | | |
| 12.5 | Ketuk dua kali "Kembali ke langkah belajar" | Kembali ke layar materi. Post-test sudah tidak terkunci | | |

## 13. Tab Progres siswa

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 13.1 | Buka tab Progres | Balon Odi berisi jumlah bintang dan materi selesai | | |
| 13.2 | Kartu tiap materi | Judul materi sebagai judul, lalu status pre-test, status post-test, "... dari 3 bintang" | | |

## 14. Tab Profil (siswa dan guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 14.1 | Fokus ke Odi | Deskripsi Odi dibacakan. Ketuk dua kali: deskripsi dibacakan suara aplikasi | | |
| 14.2 | Geser kanan | Nama sebagai judul, lalu peran | | |
| 14.3 | Kartu info | "Email, [alamat email]" dalam satu fokus, lalu "Penyimpanan akun, ..." dalam satu fokus | | |
| 14.4 | Ketuk dua kali "Keluar dari akun" | Kembali ke layar sambutan | | |

## 15. Beranda guru (masuk dengan akun guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 15.1 | Geser kanan dari awal | Jumlah materi publik, "Selamat datang kembali", nama guru sebagai judul, penjelasan | | |
| 15.2 | Kartu materi | Jenis soal, status (Publik/Draf), judul materi sebagai judul | | |
| 15.3 | Kode akses di kartu | "Kode akses: A P V ..." dieja per huruf | | |
| 15.4 | Tombol salin | "Salin kode akses, tombol". Setelah diketuk dua kali: "Kode akses disalin." dibacakan satu kali | | |
| 15.5 | Kotak angka | "Siswa: 2", "Soal pre-test: 2", "Soal post-test: 3" | | |
| 15.6 | Tombol kelola | "Kelola materi [judul], tombol" (judul ikut disebut) | | |
| 15.7 | Ketuk dua kali "Buat Materi Baru" | Dialog terbuka. "Judul materi, kotak edit", "Isi materi, kotak edit", tombol "Batal" dan "Lanjut buat soal" | | |
| 15.8 | Menu bawah guru | "Materi", "Siswa", "Hasil", "Profil", masing-masing "tab ... dari 4" | | |

## 16. Kelola materi (guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 16.1 | Buka materi baru tanpa soal | Pilihan jenis soal: "Quiz, dipilih", "Benar atau Salah", dan lain-lain | | |
| 16.2 | Ketuk dua kali jenis soal lain | Jenis itu terbaca "dipilih" | | |
| 16.3 | Ketuk dua kali "Buat soal Pre-test dengan AI" | "AI sedang membuat soal Pre-test. Tunggu sebentar." lalu "... soal Pre-test dibuat. Periksa sebelum dipublikasikan." | | |
| 16.4 | Baris soal | "Pre-test soal 1. [pertanyaan]. Ketuk untuk ubah" | | |
| 16.5 | Tombol hapus di baris soal | "Hapus Pre-test soal 1, tombol" | | |
| 16.6 | Ketuk dua kali tombol hapus | "Pre-test soal 1 dihapus." | | |
| 16.7 | Setelah ada soal, pilihan jenis soal | Terbaca dinonaktifkan, dan kalimat di bawahnya menjelaskan alasannya | | |
| 16.8 | Sakelar "Publikasikan ke siswa" sebelum soal lengkap | "Isi dulu pre-test dan post-test..." dibacakan satu kali | | |
| 16.9 | Setelah soal lengkap, nyalakan sakelar | Status sakelar berubah, dan terdengar "Materi dipublikasikan." | | |

## 17. Form soal (guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 17.1 | Buka "Tambah soal" untuk Quiz | "Pertanyaan, kotak edit", "Pilihan A" sampai "Pilihan D", judul "Jawaban benar", pilihan "Pilihan A, dipilih" dan seterusnya | | |
| 17.2 | Ketuk dua kali "Simpan soal" dengan pertanyaan kosong | "Pertanyaan belum diisi." dibacakan satu kali | | |
| 17.3 | Kolom opsional | "Deskripsi gambar (opsional), kotak edit" dan "Penjelasan jawaban, kotak edit", termasuk petunjuknya | | |

## 18. Tab Siswa dan Hasil (guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 18.1 | Tab Siswa, fokus ke satu siswa | "[nama]. Mengikuti ... materi, selesai ..., ... bintang" dalam satu fokus | | |
| 18.2 | Tab Hasil, kartu materi | Judul sebagai judul, "Nilai pre-test: ...", "Nilai post-test: ...", lalu kalimat perbandingan | | |

## Tanpa TalkBack

Matikan TalkBack, lalu ulangi beberapa langkah ini. APREVO tidak punya
suara sendiri (tanpa TTS), jadi aplikasi harus **diam**. Semua informasi
tetap tampil di layar.

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| T1 | Masuk pertama kali sebagai siswa baru | Sambutan tampil, tidak ada suara | | |
| T2 | Masukkan kode akses salah | Pesan error tampil, tidak ada suara | | |
| T3 | Jawab satu soal | Umpan balik tampil, tidak ada suara | | |
| T4 | Selesaikan satu tes | Ringkasan hasil tampil, tidak ada suara | | |

## Masalah yang ditemukan

| No langkah | Apa yang terjadi | Seberapa mengganggu (ringan / sedang / berat) |
|---|---|---|
| | | |
