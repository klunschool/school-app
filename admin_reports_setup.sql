-- Admin report helpers.
-- Run this once in Supabase SQL Editor.

create or replace function public.admin_parent_link_report()
returns table (
  student_id bigint,
  parent_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select ps.student_id, ps.parent_id
  from public.parent_student ps
  where exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  );
$$;

revoke all on function public.admin_parent_link_report() from public, anon;
grant execute on function public.admin_parent_link_report() to authenticated;

create or replace function public.teacher_parent_link_report()
returns table (
  student_id bigint,
  parent_id uuid,
  parent_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select ps.student_id, ps.parent_id, p.full_name as parent_name
  from public.parent_student ps
  left join public.profiles p on p.id = ps.parent_id
  join public.students s on s.id = ps.student_id
  join public.teacher_class tc on tc.class_id = s.class_id
  where tc.teacher_id = auth.uid()
    or exists (
      select 1
      from public.profiles me
      where me.id = auth.uid()
        and me.role = 'admin'
    );
$$;

revoke all on function public.teacher_parent_link_report() from public, anon;
grant execute on function public.teacher_parent_link_report() to authenticated;

create or replace function public.teacher_parent_usage_report()
returns table (
  class_id bigint,
  class_name text,
  student_id bigint,
  student_name text,
  student_no integer,
  parent_id uuid,
  parent_name text,
  parent_email text,
  confirmed_at timestamptz,
  last_sign_in_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id as class_id,
    c.name as class_name,
    s.id as student_id,
    s.full_name as student_name,
    s.student_no,
    ps.parent_id,
    p.full_name as parent_name,
    u.email as parent_email,
    u.confirmed_at,
    u.last_sign_in_at
  from public.students s
  join public.classes c on c.id = s.class_id
  left join public.parent_student ps on ps.student_id = s.id
  left join public.profiles p on p.id = ps.parent_id
  left join auth.users u on u.id = ps.parent_id
  where exists (
      select 1
      from public.profiles me
      where me.id = auth.uid()
        and me.role = 'admin'
    )
    or exists (
      select 1
      from public.teacher_class tc
      where tc.teacher_id = auth.uid()
        and tc.class_id = s.class_id
    )
  order by c.name, s.student_no, s.full_name, u.email;
$$;

revoke all on function public.teacher_parent_usage_report() from public, anon;
grant execute on function public.teacher_parent_usage_report() to authenticated;

notify pgrst, 'reload schema';
