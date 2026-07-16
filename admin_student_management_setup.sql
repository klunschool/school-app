-- Admin student management helpers.
-- Run this once in Supabase SQL Editor.

create or replace function public.admin_move_students(
  p_student_ids bigint[],
  p_class_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  moved_count integer;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'admin only';
  end if;

  if p_student_ids is null or array_length(p_student_ids, 1) is null then
    raise exception 'no students selected';
  end if;

  if not exists (select 1 from public.classes c where c.id = p_class_id) then
    raise exception 'target class not found';
  end if;

  update public.students
  set class_id = p_class_id
  where id = any(p_student_ids);

  get diagnostics moved_count = row_count;

  return jsonb_build_object('success', true, 'moved_count', moved_count);
end;
$$;

create or replace function public.admin_delete_student(
  p_student_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_name text;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'admin only';
  end if;

  select s.full_name
  into deleted_name
  from public.students s
  where s.id = p_student_id;

  if deleted_name is null then
    raise exception 'student not found';
  end if;

  if to_regclass('public.parent_student') is not null then
    execute 'delete from public.parent_student where student_id = $1' using p_student_id;
  end if;

  if to_regclass('public.parent_link_codes') is not null then
    execute 'delete from public.parent_link_codes where student_id = $1' using p_student_id;
  end if;

  if to_regclass('public.parent_link_requests') is not null then
    execute 'delete from public.parent_link_requests where student_id = $1' using p_student_id;
  end if;

  delete from public.students
  where id = p_student_id;

  return jsonb_build_object('success', true, 'student_name', deleted_name);
end;
$$;

revoke all on function public.admin_move_students(bigint[], bigint) from public, anon;
revoke all on function public.admin_delete_student(bigint) from public, anon;
grant execute on function public.admin_move_students(bigint[], bigint) to authenticated;
grant execute on function public.admin_delete_student(bigint) to authenticated;

notify pgrst, 'reload schema';
