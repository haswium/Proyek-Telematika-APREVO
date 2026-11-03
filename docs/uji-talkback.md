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
     HP dan laptop harus satu Wi-Fi. Alamat server juga bisa diubah di
     layar "Alamat server". Kalau backend tidak dijalankan, layar Kelas
     akan menampilkan pesan gagal; itu juga perlu diuji.
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

Data uji yang perlu disiapkan dengan akun guru sebelum menguji sisi siswa:

1. Buat satu kelas, misalnya "7A Geografi". Catat kode aksesnya (6 huruf
   kapital, contoh `KXPRTA`).
2. Unggah satu materi PDF di kelas itu, buat pre-test dan post-test, lalu
   publikasikan.
3. Supaya semua jenis soal teruji (bagian 8 sampai 11), siapkan empat
   materi dengan jenis soal berbeda: pilihan ganda, benar/salah, isian
   singkat, dan puzzle urutan.

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
| 4.6 | Masuk dengan akun **siswa** | Pindah ke layar sambutan siswa (pertama kali) atau layar Kelas | | |

## 5. Sambutan siswa (hanya muncul pertama kali)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 5.1 | Geser kanan dari awal | "Siap untuk belajar?, judul", kalimat penjelasan, lalu tiga poin. Ikon centang dan ikon headphone tidak difokus | | |
| 5.2 | Geser kanan sampai habis | Tidak ada tombol "Dengarkan". Aplikasi tidak bersuara sendiri | | |
| 5.3 | Ketuk dua kali "Mulai Belajar" | Pindah ke layar Kelas (tab Belajar) | | |

## 6. Layar Kelas (tab Belajar siswa)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 6.1 | Buka layar ini | "Memuat kelasmu." dibacakan sendiri | | |
| 6.2 | Kalau backend **tidak** jalan | Pesan gagal dibacakan sendiri, lalu ada tombol "Coba lagi" | | |
| 6.3 | Ketuk dua kali "Coba lagi" | Pesan memuat dibacakan lagi | | |
| 6.4 | Fokus ke balon Odi | Hanya teks balon yang terbaca. Gambar Odi di sebelahnya tidak difokus | | |
| 6.5 | Fokus ke kolom kode | "Kode kelas, kotak edit" dengan petunjuk "Contoh: KXPRTA" | | |
| 6.6 | Ketik beberapa huruf kecil | Huruf tampil kapital. Di bawah kolom: "Kode yang diketik: K X P ..." dieja per huruf, tidak dibacakan tiap ketukan | | |
| 6.7 | Kosongkan kolom, ketuk dua kali "Gabung" | "Kode belum diisi." dibacakan satu kali | | |
| 6.8 | Isi kurang dari 6 huruf, ketuk "Gabung" | "Kode harus 6 huruf. Baru ... huruf: ..." dengan kode dieja | | |
| 6.9 | Isi 6 huruf yang tidak ada, ketuk "Gabung" | "Kode ... tidak ditemukan..." dengan kode dieja | | |
| 6.10 | Isi kode kelas dari guru, ketuk "Gabung" | "Bergabung ke [nama kelas]." lalu kelas muncul di daftar | | |
| 6.11 | Gabung lagi dengan kode yang sama | "Kamu sudah ikut [nama kelas]." | | |
| 6.12 | Daftar kelas | Judul "Kelas yang kamu ikuti (jumlah)", lalu tiap kelas terbaca dalam satu fokus: "Kelas [nama]. [ringkasan]" | | |
| 6.13 | Menu bawah | "Belajar, tab 1 dari 3, dipilih", "Progres, tab 2 dari 3", "Profil, tab 3 dari 3" | | |

## 7. Isi kelas dan layar materi

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 7.1 | Buka satu kelas | "Memuat materi [nama kelas]." lalu judul "Daftar materi (jumlah)" | | |
| 7.2 | Tiap materi | "Materi [judul]. [status]" dalam satu fokus. Hanya materi publik yang muncul | | |
| 7.3 | Buka satu materi | Judul materi sebagai judul, balon Odi berisi langkah berikutnya | | |
| 7.4 | Kartu materi | "Materi, [judul], [jumlah sub bab]". Tidak ada tombol "Dengarkan" | | |
| 7.5 | Ketuk dua kali "Baca materi" | Daftar sub bab terbuka. Tiap sub bab terbaca dalam satu fokus | | |
| 7.6 | Buka satu sub bab | Terdengar "Sub bab 1 dari ...: [judul]". Judul sub bab bisa dilompati dengan gestur judul | | |
| 7.7 | Tombol "Sub bab berikutnya: [judul]" | Ketuk dua kali: "Sub bab 2 dari ...: [judul]" diumumkan | | |
| 7.8 | Kartu Pre-test | "Pre-test. [status]." dalam satu fokus, lalu tombol "Mulai Pre-test" | | |
| 7.9 | Kartu Post-test sebelum pre-test | "Post-test. Terkunci. Kerjakan pre-test dulu" | | |
| 7.10 | Ketuk dua kali "Mulai Post-test" | "Kerjakan pre-test dulu, ya." dibacakan satu kali | | |
| 7.11 | Ketuk dua kali "Mulai Pre-test" | Layar soal terbuka | | |

## 8. Layar soal: pilihan ganda

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

## 9. Layar soal: benar atau salah

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 9.1 | Fokus ke pilihan | "Benar, tombol" dan "Salah, tombol" | | |
| 9.2 | Pilih lalu periksa | Umpan balik dibacakan satu kali, berisi jawabanmu dan jawaban yang benar | | |

## 10. Layar soal: isian singkat

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 10.1 | Fokus ke kolom jawaban | "Jawabanmu, kotak edit" | | |
| 10.2 | Ketik jawaban, tekan selesai di keyboard | Jawaban diperiksa dan umpan balik dibacakan | | |
| 10.3 | Fokus ke kolom setelah menjawab | Terbaca dinonaktifkan | | |

## 11. Layar soal: puzzle urutan

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
| 13.2 | Nama kelas | Terbaca sebagai judul, materi dikelompokkan per kelas | | |
| 13.3 | Kartu tiap materi | Judul materi sebagai judul, lalu status pre-test, status post-test, "... dari 3 bintang" | | |

## 14. Tab Profil (siswa dan guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 14.1 | Fokus ke Odi | Deskripsi Odi dibacakan sebagai gambar. Ketuk dua kali tidak melakukan apa pun | | |
| 14.2 | Geser kanan | Nama sebagai judul, lalu peran | | |
| 14.3 | Kartu info | "Email, [alamat email]" dalam satu fokus, lalu "Penyimpanan akun, ..." dalam satu fokus | | |
| 14.4 | Ketuk dua kali "Keluar dari akun" | Kembali ke layar sambutan | | |

## 15. Beranda guru (masuk dengan akun guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 15.1 | Geser kanan dari awal | "Kelas Saya", jumlah kelas, "Selamat datang kembali", nama guru sebagai judul, penjelasan | | |
| 15.2 | Ketuk dua kali "Buat Kelas" | Dialog "Kelas baru" terbuka. "Nama kelas, kotak edit" dengan petunjuk "Contoh: 7A Geografi" | | |
| 15.3 | Ketuk dua kali "Buat" dengan nama kosong | "Nama kelas belum diisi." dibacakan satu kali | | |
| 15.4 | Isi nama, ketuk "Buat" | "Kelas [nama] dibuat. Kode aksesnya ..." dengan kode dieja per huruf | | |
| 15.5 | Kartu kelas | Nama kelas sebagai judul, "Siswa: ...", "Materi: ..." | | |
| 15.6 | Kode akses di kartu | "Kode akses: K X P R T A" dieja per huruf | | |
| 15.7 | Tombol salin | "Salin kode akses, tombol". Setelah diketuk dua kali: "Kode akses disalin." dibacakan satu kali | | |
| 15.8 | Tombol buka | "Buka kelas [nama], tombol" (nama kelas ikut disebut) | | |
| 15.9 | Menu bawah guru | "Kelas", "Siswa", "Hasil", "Profil", masing-masing "tab ... dari 4" | | |

## 16. Isi kelas dan kelola materi (guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 16.1 | Buka satu kelas | Nama kelas sebagai judul, kode akses dieja, tombol "Unggah Materi PDF", lalu "Daftar materi (jumlah)" | | |
| 16.2 | Kelas tanpa materi | "Belum ada materi di kelas ini." | | |
| 16.3 | Kartu materi | Status (Publik/Draf), judul sebagai judul, tombol "Kelola materi [judul]" | | |
| 16.4 | Buka "Kelola materi" | Pilihan jenis soal terbaca, yang aktif terbaca "dipilih" | | |
| 16.5 | Setelah ada soal, pilihan jenis soal | Terbaca dinonaktifkan, dan kalimat di bawahnya menjelaskan alasannya | | |
| 16.6 | Ketuk dua kali "Buat Pre-test" | Layar jadwal terbuka: waktu buka dan tenggat | | |
| 16.7 | Hapus satu draf soal | "Draf Pre-test soal 1 dihapus." | | |
| 16.8 | Sakelar "Publikasikan ke siswa" sebelum soal lengkap | "Simpan dulu minimal satu soal untuk ..." dibacakan satu kali | | |
| 16.9 | Setelah soal lengkap, nyalakan sakelar | Status sakelar berubah, dan terdengar "Materi dipublikasikan." | | |

## 17. Form soal (guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 17.1 | Buka "Tambah soal" untuk pilihan ganda | "Pertanyaan, kotak edit", kolom pilihan, judul "Jawaban benar", lalu pilihan dengan satu yang "dipilih" | | |
| 17.2 | Ketuk dua kali "Simpan soal" dengan pertanyaan kosong | "Pertanyaan belum diisi." dibacakan satu kali | | |
| 17.3 | Kolom penjelasan | "Penjelasan jawaban, kotak edit", termasuk petunjuknya | | |

## 18. Tab Siswa dan Hasil (guru)

| No | Langkah | Yang seharusnya terdengar / terjadi | Hasil | Catatan |
|---|---|---|---|---|
| 18.1 | Tab Siswa, fokus ke satu siswa | "[nama]. Ikut ... kelas, ..." dalam satu fokus | | |
| 18.2 | Tab Hasil | Nama kelas sebagai judul, lalu kartu tiap materi | | |
| 18.3 | Kartu materi | Judul sebagai judul, nilai pre-test dan post-test, lalu kalimat perbandingan | | |

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
