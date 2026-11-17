-- Materi dari banyak format (DOCX, PPTX, XLSX, CSV, TXT, MD, foto, audio).
-- Jalankan sekali di Supabase > SQL Editor. Aman dijalankan ulang.

-- 1. Kolom baru di materials -------------------------------------------------

alter table public.materials
  add column if not exists source_type text not null default 'pdf',
  -- Path file asli di bucket material-files (selain PDF, yang tetap di
  -- materials-pdf lewat file_url). Untuk audio, ini file yang diputar siswa.
  add column if not exists source_path text,
  add column if not exists conversion_status text not null default 'ready',
  add column if not exists conversion_step text,
  add column if not exists conversion_error text,
  add column if not exists audio_duration_seconds integer;

-- Materi lama: PDF, kecuali materi tempel teks (file_url kosong).
update public.materials
  set source_type = 'text'
  where coalesce(file_url, '') = '' and source_type = 'pdf';

alter table public.materials
  drop constraint if exists materials_source_type_check,
  add constraint materials_source_type_check check (
    source_type in (
      'pdf', 'docx', 'pptx', 'xlsx', 'csv', 'txt', 'md', 'image', 'audio', 'text'
    )
  ),
  drop constraint if exists materials_conversion_status_check,
  add constraint materials_conversion_status_check check (
    conversion_status in ('processing', 'ready', 'failed')
  ),
  drop constraint if exists materials_audio_duration_check,
  add constraint materials_audio_duration_check check (
    audio_duration_seconds is null
    or audio_duration_seconds between 0 and 900
  );

-- Backend mencari materi yang masih diproses saat menyala ulang.
create index if not exists materials_conversion_processing_idx
  on public.materials (conversion_status)
  where conversion_status = 'processing';

-- 2. Bucket material-files ----------------------------------------------------
-- Private. Hanya backend (kunci service_role) yang membaca dan menulis;
-- siswa memutar audio lewat signed URL berumur 1 jam dari backend.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'material-files',
  'material-files',
  false,
  26214400, -- 25 MB, sama dengan batas audio di backend
  array[
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'text/plain',
    'text/markdown',
    'image/jpeg',
    'image/png',
    'audio/mpeg',
    'audio/mp4',
    'audio/wav',
    'audio/ogg'
  ]
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 3. Policy --------------------------------------------------------------------
-- service_role melewati RLS, jadi backend tetap bisa mengakses bucket ini.
-- Policy RESTRICTIVE ini menutup bucket untuk anon dan authenticated,
-- termasuk kalau nanti ada policy lain yang membuka storage.objects lebih luas.
-- Aplikasi Flutter tidak pernah menyentuh bucket ini secara langsung.

drop policy if exists "material-files hanya lewat backend" on storage.objects;
create policy "material-files hanya lewat backend"
  on storage.objects
  as restrictive
  for all
  to anon, authenticated
  using (bucket_id <> 'material-files')
  with check (bucket_id <> 'material-files');
