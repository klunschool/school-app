-- Allow authenticated users to read announcements.
-- Allow admins and homeroom teachers to create and manage announcements.

alter table public.announcements enable row level security;

alter table public.announcements
add column if not exists class_id bigint references public.classes(id) on delete set null;

drop policy if exists announcements_select on public.announcements;
create policy announcements_select
on public.announcements
for select
to authenticated
using (
  class_id is null
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role in ('admin', 'finance')
  )
  or exists (
    select 1
    from public.teacher_class tc
    where tc.teacher_id = auth.uid()
      and tc.class_id = announcements.class_id
  )
  or exists (
    select 1
    from public.students s
    where s.profile_id = auth.uid()
      and s.class_id = announcements.class_id
  )
  or exists (
    select 1
    from public.parent_student ps
    join public.students s on s.id = ps.student_id
    where ps.parent_id = auth.uid()
      and s.class_id = announcements.class_id
  )
);

drop policy if exists announcements_insert_staff on public.announcements;
create policy announcements_insert_staff
on public.announcements
for insert
to authenticated
with check (
  created_by = auth.uid()
  and (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
    or exists (
      select 1
      from public.profiles p
      join public.teacher_class tc on tc.teacher_id = p.id
      where p.id = auth.uid()
        and p.role in ('teacher', 'teacher_parent')
        and announcements.class_id = tc.class_id
    )
  )
);

drop policy if exists announcements_update_staff on public.announcements;
create policy announcements_update_staff
on public.announcements
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
  or exists (
    select 1
    from public.profiles p
    join public.teacher_class tc on tc.teacher_id = p.id
    where p.id = auth.uid()
      and p.role in ('teacher', 'teacher_parent')
      and announcements.class_id = tc.class_id
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
  or exists (
    select 1
    from public.profiles p
    join public.teacher_class tc on tc.teacher_id = p.id
    where p.id = auth.uid()
      and p.role in ('teacher', 'teacher_parent')
      and announcements.class_id = tc.class_id
  )
);

drop policy if exists announcements_delete_staff on public.announcements;
drop policy if exists announcements_delete_admin on public.announcements;
create policy announcements_delete_staff
on public.announcements
for delete
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
  or exists (
    select 1
    from public.profiles p
    join public.teacher_class tc on tc.teacher_id = p.id
    where p.id = auth.uid()
      and p.role in ('teacher', 'teacher_parent')
      and announcements.class_id = tc.class_id
  )
);

grant select, insert, update, delete on public.announcements to authenticated;
