create or replace function public.get_teacher_checkin_history(p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'กรุณาเข้าสู่ระบบ';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('teacher', 'teacher_parent', 'admin')
  ) then
    raise exception 'ไม่มีสิทธิ์ดูประวัติสแกน';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cl.id,
        'student_id', cl.student_id,
        'type', cl.type,
        'scanned_at', cl.scanned_at,
        'students', jsonb_build_object(
          'full_name', s.full_name,
          'student_no', s.student_no,
          'class_name', c.name
        )
      )
      order by cl.scanned_at asc
    ),
    '[]'::jsonb
  )
  into result_data
  from public.checkin_log cl
  join public.students s on s.id = cl.student_id
  left join public.classes c on c.id = s.class_id
  where cl.scanned_at >= (p_date::timestamp at time zone 'Asia/Bangkok')
    and cl.scanned_at < ((p_date + 1)::timestamp at time zone 'Asia/Bangkok')
    and (
      exists (
        select 1 from public.profiles
        where id = auth.uid() and role = 'admin'
      )
      or exists (
        select 1
        from public.teacher_class tc
        where tc.teacher_id = auth.uid()
          and tc.class_id = s.class_id
      )
    );

  return result_data;
end;
$$;

revoke all on function public.get_teacher_checkin_history(date) from public, anon;
grant execute on function public.get_teacher_checkin_history(date) to authenticated;

notify pgrst, 'reload schema';
