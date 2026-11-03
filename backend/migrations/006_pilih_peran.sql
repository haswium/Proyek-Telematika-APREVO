-- Akun Google belum punya peran saat pertama masuk. Baris public.users baru dibuat
-- setelah peran dipilih lewat POST /me/role, jadi akun itu tidak lagi otomatis
-- menjadi siswa. Jalankan setelah 000_users_trigger.sql. Aman dijalankan ulang.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'role', '') not in ('teacher', 'student') then
    return new;
  end if;

  insert into public.users (id, name, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(new.email, '@', 1)),
    new.raw_user_meta_data ->> 'role'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Peran tidak bisa diganti: hanya trigger dan backend yang menulis tabel ini.
revoke insert, update, delete on public.users from anon, authenticated;
