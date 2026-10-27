-- Gambar di halaman materi beserta deskripsi AI (Gemini) yang bisa diedit guru.
--
-- Tabel material_images dibuat lebih dulu oleh fitur deskripsi gambar Hasna
-- (kolom id, material_id, image_url, description, audio_url). Kode sekarang
-- juga membutuhkan:
--   image_key      kunci gambar, sama dengan penanda [[gambar:<image_key>]]
--                  di isi halaman (material_sections.content)
--   page_number    halaman PDF tempat gambar pertama kali muncul
--   is_decorative  gambar hiasan yang tidak dibacakan ke siswa
--
-- Cara menjalankan: Supabase > SQL Editor > New query, tempel seluruh isi
-- file ini, lalu Run. Aman dijalankan lebih dari sekali.

create table if not exists public.material_images (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.materials(id) on delete cascade,
  image_url text not null,
  description text,
  audio_url text
);

alter table public.material_images
  add column if not exists image_key text,
  add column if not exists page_number integer,
  add column if not exists is_decorative boolean not null default false;

-- Satu baris per gambar per materi. Baris lama tanpa image_key (NULL) tidak
-- bentrok karena NULL tidak dianggap sama.
create unique index if not exists material_images_material_key
  on public.material_images (material_id, image_key);

alter table public.material_images enable row level security;

-- Supaya API Supabase langsung mengenali kolom baru.
notify pgrst, 'reload schema';
