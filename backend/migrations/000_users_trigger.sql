-- Salin akun baru dari auth.users ke public.users memakai metadata
-- `name` dan `role` yang dikirim aplikasi saat daftar.
-- Aman dijalankan ulang.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, name, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(new.email, '@', 1)),
    case when new.raw_user_meta_data ->> 'role' = 'teacher' then 'teacher' else 'student' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Isi baris untuk akun yang sudah terdaftar sebelum trigger ada.
insert into public.users (id, name, role)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data ->> 'name', ''), split_part(u.email, '@', 1)),
  case when u.raw_user_meta_data ->> 'role' = 'teacher' then 'teacher' else 'student' end
from auth.users u
on conflict (id) do nothing;
