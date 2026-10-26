-- Isi materi per sub-bab, hasil pemecahan PDF.

create table if not exists public.material_sections (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.materials(id) on delete cascade,
  position integer not null check (position >= 1),
  title text not null,
  content text not null default '',
  image_description text,
  image_count integer not null default 0,
  page_start integer,
  page_end integer,
  created_at timestamptz not null default now(),
  unique (material_id, position)
);

alter table public.material_sections enable row level security;
