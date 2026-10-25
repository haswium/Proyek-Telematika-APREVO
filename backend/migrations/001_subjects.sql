-- Mata pelajaran milik guru, dengan satu kode akses 6 huruf kapital.

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  access_code text not null unique check (access_code ~ '^[A-Z]{6}$'),
  teacher_id uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists subjects_teacher_id_idx on public.subjects (teacher_id);

create table if not exists public.subject_students (
  subject_id uuid not null references public.subjects(id) on delete cascade,
  student_id uuid not null references public.users(id),
  joined_at timestamptz not null default now(),
  primary key (subject_id, student_id)
);

create index if not exists subject_students_student_id_idx
  on public.subject_students (student_id);

-- Backend memakai service role. RLS tanpa policy menutup akses kunci anon.
alter table public.subjects enable row level security;
alter table public.subject_students enable row level security;
