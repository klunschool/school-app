create or replace function public.can_access_student(target_student_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_finance_staff()
    or exists (
      select 1 from public.students s
      where s.id = target_student_id and s.profile_id = auth.uid()
    )
    or exists (
      select 1 from public.teacher_class tc
      join public.students s on s.class_id = tc.class_id
      where tc.teacher_id = auth.uid() and s.id = target_student_id
    )
    or exists (
      select 1 from public.parent_student ps
      where ps.student_id = target_student_id and ps.parent_id = auth.uid()
    );
$$;

notify pgrst, 'reload schema';
