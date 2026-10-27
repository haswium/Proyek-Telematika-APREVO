-- Materi menjadi bagian dari kelas. Boleh null untuk materi lama
-- yang masih memakai materials.access_code dan material_access.

alter table public.materials
  add column if not exists subject_id uuid references public.subjects(id);

create index if not exists materials_subject_id_idx on public.materials (subject_id);
