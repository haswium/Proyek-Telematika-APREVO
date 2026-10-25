-- Jenis tes, jadwal kuis, penjelasan per soal, dan status benar per jawaban.

alter table public.quizzes
  add column if not exists kind text,
  add column if not exists available_from timestamptz,
  add column if not exists deadline_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'quizzes_kind_check') then
    alter table public.quizzes
      add constraint quizzes_kind_check check (kind in ('pre', 'post'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quizzes_schedule_check') then
    alter table public.quizzes
      add constraint quizzes_schedule_check check (deadline_at > available_from);
  end if;
end $$;

-- Satu pre-test dan satu post-test aktif per materi.
create unique index if not exists quizzes_material_kind_key
  on public.quizzes (material_id, kind)
  where deleted_at is null and kind is not null;

alter table public.questions
  add column if not exists explanation text;

alter table public.answers
  add column if not exists is_correct boolean;

-- Dipakai upsert autosave (on_conflict attempt_id,question_id).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'answers_attempt_question_key'
  ) then
    alter table public.answers
      add constraint answers_attempt_question_key unique (attempt_id, question_id);
  end if;
end $$;
