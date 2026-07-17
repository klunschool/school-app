-- Student photo storage setup.
-- Run this once in Supabase SQL Editor.

alter table public.students
add column if not exists photo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'student-photos',
  'student-photos',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = false,
    file_size_limit = 2097152,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

drop policy if exists student_photos_select_authenticated on storage.objects;
drop policy if exists student_photos_insert_admin on storage.objects;
drop policy if exists student_photos_update_admin on storage.objects;
drop policy if exists student_photos_delete_admin on storage.objects;

create policy student_photos_select_authenticated
on storage.objects
for select
to authenticated
using (bucket_id = 'student-photos');

create policy student_photos_insert_admin
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'student-photos'
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
);

create policy student_photos_update_admin
on storage.objects
for update
to authenticated
using (
  bucket_id = 'student-photos'
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
)
with check (
  bucket_id = 'student-photos'
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
);

create policy student_photos_delete_admin
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'student-photos'
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
);

create or replace function public.admin_set_student_photo(
  p_student_id bigint,
  p_photo_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'admin only';
  end if;

  update public.students
  set photo_path = nullif(trim(coalesce(p_photo_path, '')), '')
  where id = p_student_id;

  if not found then
    raise exception 'student not found';
  end if;

  return jsonb_build_object('success', true, 'student_id', p_student_id, 'photo_path', p_photo_path);
end;
$$;

revoke all on function public.admin_set_student_photo(bigint, text) from public, anon;
grant execute on function public.admin_set_student_photo(bigint, text) to authenticated;

notify pgrst, 'reload schema';
