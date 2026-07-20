-- Teacher leave attendance helper.
-- Run this once in Supabase SQL Editor.

alter table public.attendance
  add column if not exists attendance_note text;

alter table public.attendance
  add column if not exists scan_source text;

create or replace function public.record_teacher_leave_attendance(
  p_student_id bigint,
  p_date date,
  p_leave_type text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_class_id bigint;
  note_text text;
begin
  if auth.uid() is null then
    raise exception 'กรุณาเข้าสู่ระบบ';
  end if;

  if p_leave_type not in ('sick', 'personal') then
    raise exception 'ประเภทการลาไม่ถูกต้อง';
  end if;

  select class_id
  into target_class_id
  from public.students
  where id = p_student_id
  limit 1;

  if target_class_id is null then
    raise exception 'ไม่พบนักเรียน';
  end if;

  if not (
    exists (
      select 1
      from public.profiles
      where id = auth.uid()
        and role = 'admin'
    )
    or exists (
      select 1
      from public.teacher_class
      where teacher_id = auth.uid()
        and class_id = target_class_id
    )
  ) then
    raise exception 'ไม่มีสิทธิ์บันทึกการลาห้องนี้';
  end if;

  note_text := case p_leave_type
    when 'sick' then 'ลาป่วยโดยครูประจำชั้น'
    when 'personal' then 'ลากิจโดยครูประจำชั้น'
    else 'ลาโดยครูประจำชั้น'
  end;

  update public.attendance
  set status = 'leave',
      attendance_note = note_text,
      scan_source = 'teacher_manual'
  where student_id = p_student_id
    and date = p_date;

  if not found then
    insert into public.attendance (student_id, date, status, attendance_note, scan_source)
    values (p_student_id, p_date, 'leave', note_text, 'teacher_manual');
  end if;
end;
$$;

revoke all on function public.record_teacher_leave_attendance(bigint, date, text) from public, anon;
grant execute on function public.record_teacher_leave_attendance(bigint, date, text) to authenticated;

notify pgrst, 'reload schema';
