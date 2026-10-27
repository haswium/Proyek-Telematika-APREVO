# Kontrak API APREVO

Dokumen ini mengikuti `backend/main.py` di branch `feat/backend-lengkap`.
Perbarui dokumen ini setiap kali endpoint berubah.

## Umum

- Base URL lokal: `http://localhost:8000`. Dokumentasi interaktif di `/docs`.
- Autentikasi: header `Authorization: Bearer <access_token>` dari Supabase Auth.
  Token tidak valid atau kedaluwarsa menghasilkan `401`.
- Peran dibaca dari tabel `public.users.role` (`teacher` atau `student`).
  Baris ini dibuat otomatis dari metadata akun saat daftar
  (`backend/migrations/000_users_trigger.sql`). Peran salah atau profil belum
  ada menghasilkan `403`.
- Error memakai format FastAPI: `{"detail": "<pesan>"}`.
- Waktu memakai ISO 8601 dengan zona waktu. Waktu tanpa zona ditolak `400`.
- CORS mengizinkan `localhost`, `127.0.0.1`, dan IP jaringan lokal (`10.x`,
  `172.16-31.x`, `192.168.x`) di port mana pun, ditambah `CORS_ORIGINS` di `.env`.

### Jadwal kuis

Tiap kuis punya `available_from` (waktu buka) dan `deadline_at` (waktu tutup).

| `status`      | Arti |
|---------------|------|
| `unscheduled` | Jadwal belum diisi |
| `upcoming`    | Belum dibuka |
| `open`        | Bisa dikerjakan |
| `closed`      | Tenggat lewat, pembahasan terbuka |

Membuka soal, memulai percobaan, dan menyimpan jawaban di luar jadwal ditolak
`403 "Kuis belum tersedia"` atau `403 "Deadline kuis telah lewat"`.

### Pre-test dan post-test

`quizzes.kind` bernilai `pre` atau `post`, satu masing-masing per materi.
Post-test terkunci (`403 "Kerjakan pre-test terlebih dahulu"`) sampai siswa
mengumpulkan pre-test materi yang sama. Materi tanpa pre-test tidak mengunci
post-test.

### Umpan balik jawaban

1. Saat mengerjakan: tiap jawaban hanya mendapat `is_correct`.
2. Setelah dikumpulkan: `result` menampilkan soal, jawaban siswa, dan
   `is_correct`, tanpa kunci jawaban.
3. Setelah tenggat lewat: `discussion` menambahkan jawaban benar dan
   `explanation`.

## Jenis soal

| `type`            | Kunci jawaban                            | Format jawaban siswa            |
|-------------------|------------------------------------------|---------------------------------|
| `multiple_choice` | `question_options.is_correct` (tepat 1)  | `selected_option_ids` (tepat 1) |
| `true_false`      | `questions.correct_answer`               | `boolean_value`                 |
| `text`            | `question_answers.answer` (bisa banyak)  | `text_value`                    |
| `ordering`        | `question_items.correct_order` (mulai 1) | `ordered_item_ids` (semua item) |

Isian singkat dinilai setelah dinormalisasi: spasi di awal/akhir dibuang,
huruf kecil, spasi ganda dijadikan satu.

## Endpoint pengembangan

`/test-auth`, `/test-supabase`, `/debug-auth`, `/debug-policy`, dan `/test-login` hanya aktif
kalau `ENABLE_DEBUG_ENDPOINTS=1`. Selain itu `404`.

| Metode | Path             | Auth | Keterangan |
|--------|------------------|------|------------|
| GET    | `/`              | -    | `{"message": "Hello World"}` |
| GET    | `/test-auth`     | ya   | `{"message", "user_id"}` |
| GET    | `/test-supabase` | -    | Satu baris `materials` |
| GET    | `/debug-auth`    | ya   | Uji RLS pada satu kuis dengan ID tetap |
| GET    | `/debug-policy`  | ya   | Uji RLS pada satu kuis dengan ID tetap |
| POST   | `/test-login`    | -    | Login dengan `TEST_LOGIN_EMAIL`/`TEST_LOGIN_PASSWORD` dari `.env`, mengembalikan `{"access_token"}` |
| POST   | `/validate-ai`   | guru | Validasi body `AIOutput`, mengembalikan `{"message", "data"}` |

## Guru

### POST `/teacher/subjects`

Body `{"name": "7A Geografi"}`. Kode akses 6 huruf kapital dibuat otomatis.
Respons: `{"message", "subject": {id, name, access_code, teacher_id, created_at}}`.

### GET `/teacher/subjects`

Respons: `{"subjects": [{id, name, access_code, created_at, student_count,
material_count}]}`.

### GET `/teacher/subjects/{subject_id}/materials`

Semua materi, termasuk draf. Respons: `{"subject": {...}, "materials": [{id,
title, is_published, created_at, section_count, quizzes: [{id, title,
material_id, kind, attempt_limit, available_from, deadline_at, status}]}]}`.

### POST `/teacher/materials/upload`

Multipart: `title` (teks), `file` (PDF, maksimal 20 MB), `subject_id`
(opsional, harus milik guru). PDF disimpan di bucket `materials-pdf` lalu
dipecah per sub-bab ke `material_sections`.

```json
{
  "message": "PDF berhasil diunggah dan diekstraksi.",
  "material": { "id": "...", "title": "...", "subject_id": "...", "is_published": false, "...": "..." },
  "extraction": { "total_pages": 3, "total_images": 1, "extracted_text": "..." },
  "sections": [
    { "id": "...", "position": 1, "title": "Fotosintesis", "page_start": 1, "page_end": 2, "image_count": 1 }
  ]
}
```

Judul sub-bab diambil dari daftar isi PDF. Kalau tidak ada, judul dicari dari
huruf yang lebih besar, baris tebal, atau penomoran (`BAB 1`, `1.2 Judul`).
Kalau tetap tidak ada, satu sub-bab per halaman. Teks sebelum judul pertama
menjadi sub-bab "Pendahuluan".

File dianggap PDF kalau namanya berakhiran `.pdf` dan isinya diawali `%PDF-`.
`content_type` dari klien tidak dipakai, karena HP sering mengirimnya sebagai
`application/octet-stream`. Aplikasi tetap mengirim `application/pdf`.

Error: `400` bukan PDF (`"File harus berformat PDF."` atau `"Isi file bukan
PDF yang valid."`) atau tidak bisa diproses, `403` bukan guru, `404`
kelas tidak ditemukan, `413` terlalu besar, `500` gagal simpan.

### PATCH `/teacher/materials/{material_id}`

Body (isi salah satu atau keduanya): `{"title": "...", "is_published": true}`.
Respons: `{"message", "material"}`.

### POST `/teacher/materials/{material_id}/quizzes`

```json
{ "kind": "pre", "title": "Pre-test Tumbuhan", "attempt_limit": 1,
  "available_from": "2026-11-01T07:00:00+07:00", "deadline_at": "2026-11-03T21:00:00+07:00" }
```

`title` opsional (bawaan "Pre-test"/"Post-test"), `attempt_limit` opsional.
Respons: `{"message", "quiz"}`. Error: `400` tenggat tidak setelah waktu buka,
`409` materi sudah punya kuis jenis itu.

### PATCH `/teacher/quizzes/{quiz_id}/schedule`

Body `{"available_from", "deadline_at"}`. Respons: `{"message", "quiz"}`.

### POST `/quizzes/{quiz_id}/questions`

Hanya guru pemilik kuis. Body `AIOutput`. `explanation` opsional di setiap soal.

```json
{
  "questions": [
    { "type": "multiple_choice", "question": "...", "explanation": "...",
      "options": [ { "text": "...", "is_correct": true }, { "text": "...", "is_correct": false } ] },
    { "type": "true_false", "question": "...", "correct_answer": true },
    { "type": "text", "question": "...", "answers": [ { "answer": "..." } ] },
    { "type": "ordering", "question": "...",
      "items": [ { "text": "...", "correct_order": 1 }, { "text": "...", "correct_order": 2 } ] }
  ]
}
```

Respons: `{"message", "questions": [<baris questions>]}`. Error: `403`, `404`,
`422` (misalnya pilihan ganda dengan lebih dari satu jawaban benar).

### GET `/quizzes/{quiz_id}`

Hanya guru pemilik. Respons: `{"quiz": {id, title, material_id, teacher_id,
attempt_limit, created_at, kind, available_from, deadline_at}, "questions":
[...]}`. Tiap soal berisi `explanation` dan kunci jawaban: `options` (dengan
`is_correct`), `answer` (daftar `{id, answer}` untuk isian), atau `items`
(dengan `correct_order`).

### GET `/teacher/subjects/{subject_id}/results`

```json
{
  "subject": { "...": "..." },
  "student_count": 2,
  "materials": [
    { "id": "...", "title": "...", "is_published": true, "quizzes": [
      { "id": "...", "kind": "pre", "status": "closed", "submitted_count": 1, "average_percent": 50.0,
        "students": [
          { "student_id": "...", "name": "Andi", "attempt_count": 1,
            "latest_attempt": { "attempt_id": "...", "correct_count": 1, "total_questions": 2, "submitted_at": "..." } },
          { "student_id": "...", "name": "Budi", "attempt_count": 0, "latest_attempt": null }
        ] }
    ] }
  ]
}
```

`latest_attempt` adalah percobaan terakhir yang sudah dikumpulkan.
`average_percent` dihitung dari siswa yang sudah mengumpulkan. Bintang dihitung
di aplikasi dengan `starsFor`.

## Siswa

### POST `/student/subjects/join`

Body `{"code": "KXPRTA"}`. Huruf kecil, spasi, dan strip diabaikan. Bergabung
ulang tidak error. Respons: `{"message", "already_joined", "subject": {id,
name}}`. Error: `400` format kode salah, `404` kode tidak ditemukan.

### GET `/student/subjects`

Respons: `{"subjects": [{id, name, teacher_name, material_count, joined_at}]}`.
`material_count` hanya menghitung materi yang dipublikasikan.

### GET `/student/subjects/{subject_id}/materials`

Hanya anggota. Materi yang dipublikasikan beserta status kuis:

```json
{
  "subject": { "id": "...", "name": "IPA" },
  "materials": [
    { "id": "...", "title": "Tumbuhan", "section_count": 4, "quizzes": [
      { "id": "...", "kind": "post", "title": "Post-test", "available_from": "...", "deadline_at": "...",
        "status": "open", "attempt_limit": null, "attempts_used": 0, "unfinished_attempt_id": null,
        "locked": true, "discussion_available": false, "latest_attempt": null }
    ] }
  ]
}
```

### GET `/materials/{material_id}/sections`

Untuk guru pemilik materi, atau siswa yang punya akses ke materi yang sudah
dipublikasikan. Respons: `{"material": {id, title}, "sections": [{id, position,
title, content, image_description, image_count, page_start, page_end}]}`,
diurutkan dari `position`. `image_description` masih `null` sampai deskripsi
gambar diisi.

### GET `/student/materials`

Materi yang dipublikasikan dari `material_access` (cara lama) dan dari kelas
yang diikuti. Respons: `{"materials": [{id, title, is_published}]}`.

### GET `/student/quizzes/{quiz_id}`

Soal tanpa kunci jawaban. Opsi dan item diacak. Mengikuti jadwal dan kunci
post-test. Respons: `{"quiz": {id, title, attempt_limit}, "questions": [{id,
type, question, options?: [{id, text}], items?: [{id, text}]}]}`.
Error: `400` belum ada soal, `403` jadwal, kunci, belum dipublikasikan, atau
tanpa akses, `404`.

### POST `/quizzes/{quiz_id}/attempts`

Memulai percobaan. Kalau ada percobaan yang belum dikumpulkan, percobaan itu
dikembalikan. Respons: `{"message", "attempt": {id, submitted_at, ...}}`.
Error: `403` jadwal, kunci post-test, akses, atau batas percobaan; `404`;
`400` belum ada soal.

### PUT `/student/attempts/{attempt_id}/answers/{question_id}`

Menyimpan atau mengganti jawaban satu soal. Body (isi tepat satu format jawaban):

```json
{ "question_id": "<sama dengan di URL>", "selected_option_ids": ["..."] }
```

Respons: `{"message", "attempt_id", "question_id", "is_correct"}`. Tidak berisi
jawaban benar atau pembahasan. Error: `400` format salah, `403` jadwal, `404`,
`409` sudah dikumpulkan.

### POST `/student/attempts/{attempt_id}/submit`

Menilai ulang semua jawaban di server dan menutup percobaan. Respons:
`{"message", "attempt_id", "correct_count", "total_questions", "submitted_at",
"deadline_passed"}`. Error: `404` tidak ditemukan, `409` sudah dikumpulkan.

### GET `/student/attempts/{attempt_id}/result`

Hanya untuk percobaan yang sudah dikumpulkan. Tidak berisi kunci jawaban.
Respons: `{"attempt_id", "quiz_id", "quiz_title", "score", "total_questions",
"submitted_at", "deadline_at", "discussion_available", "review": [...]}`.
Tiap item `review` berisi `question_id`, `type`, `question`, `is_correct`,
`answer` (nilai untuk benar/salah dan isian), `options` (`{option_id, text,
selected}`), atau `items` (`{item_id, text, selected_order}`).

### GET `/student/attempts/{attempt_id}/discussion`

Hanya setelah `deadline_at` lewat, selain itu `403 "Pembahasan baru terbuka
setelah tenggat kuis lewat."`. Bentuknya sama dengan `result`, ditambah per
soal:

- `explanation`
- pilihan ganda: `is_correct` di tiap opsi
- benar/salah: `correct_answer`
- isian: `accepted_answers` (daftar teks)
- urutan: `correct_order` di tiap item
