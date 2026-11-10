-- Presensi per pertemuan di kelas.
--
-- Guru membuka sesi dengan waktu buka dan tutup. Siswa menekan Hadir selama
-- sesi terbuka. Alpa tidak disimpan oleh tugas terjadwal: siswa tanpa catatan
-- di sesi yang sudah tutup dihitung alpa saat data dibaca, karena server
-- Render bisa tidur. Catatan baru dibuat saat siswa menekan Hadir atau guru
-- mengubah status.

create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 100),
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (closes_at > opens_at)
);

create index if not exists attendance_sessions_subject_idx
  on public.attendance_sessions (subject_id, opens_at);

create table if not exists public.attendance_records (
  session_id uuid not null
    references public.attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.users(id),
  status text not null check (status in ('hadir', 'izin', 'sakit', 'alpa')),
  -- 'siswa' dari tombol Hadir, 'guru' kalau diubah guru.
  source text not null check (source in ('siswa', 'guru')),
  updated_by uuid not null references public.users(id),
  marked_at timestamptz not null default now(),
  -- Satu siswa satu catatan per sesi.
  primary key (session_id, student_id)
);

create index if not exists attendance_records_student_idx
  on public.attendance_records (student_id);

-- Backend memakai service role. RLS tanpa policy menutup akses kunci anon dan
-- akun yang login langsung ke Supabase.
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
