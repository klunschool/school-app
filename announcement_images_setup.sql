-- Enable image attachments for announcements.
-- Run this in Supabase SQL Editor once before using announcement images.

alter table public.announcements
add column if not exists image_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'announcement-images',
  'announcement-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists announcement_images_public_read on storage.objects;
create policy announcement_images_public_read
on storage.objects
for select
to public
using (bucket_id = 'announcement-images');

drop policy if exists announcement_images_staff_insert on storage.objects;
create policy announcement_images_staff_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'announcement-images'
  and owner = auth.uid()
  and exists (
    select 1
    from public.profiles p
    left join public.teacher_class tc on tc.teacher_id = p.id
    where p.id = auth.uid()
      and (
        p.role = 'admin'
        or (
          p.role in ('teacher', 'teacher_parent')
          and tc.teacher_id is not null
        )
      )
  )
);

drop policy if exists announcement_images_staff_update on storage.objects;
create policy announcement_images_staff_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'announcement-images'
  and (
    owner = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
  )
)
with check (
  bucket_id = 'announcement-images'
  and (
    owner = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
  )
);

drop policy if exists announcement_images_staff_delete on storage.objects;
create policy announcement_images_staff_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'announcement-images'
  and (
    owner = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
  )
);
