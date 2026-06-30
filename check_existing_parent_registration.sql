-- ตรวจสอบก่อนสมัคร เพื่อไม่ให้ Supabase แสดงว่าส่งอีเมลแล้วสำหรับบัญชีเดิม
-- ต้องระบุอีเมลพร้อมเลขนักเรียน 13 หลักที่มีอยู่จริง

create or replace function public.check_parent_registration(
  p_email text,
  p_student_id_no text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  student_row public.students%rowtype;
  parent_user_id uuid;
  email_exists boolean := false;
  student_claimed boolean := false;
begin
  select * into student_row
  from public.students
  where trim(student_id_no) = trim(p_student_id_no)
  limit 1;

  if student_row.id is null then
    return jsonb_build_object('registered', false, 'student_found', false);
  end if;

  select id into parent_user_id
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  email_exists := parent_user_id is not null;

  student_claimed := exists (
    select 1
    from public.parent_student ps
    where ps.student_id = student_row.id
  ) or exists (
    select 1
    from public.parent_link_requests r
    where r.student_id = student_row.id
      and r.status in ('pending', 'approved')
  );

  return jsonb_build_object(
    'registered', email_exists or student_claimed,
    'student_found', true,
    'email_exists', email_exists,
    'student_claimed', student_claimed
  );
end;
$$;

revoke all on function public.check_parent_registration(text, text)
  from public;
grant execute on function public.check_parent_registration(text, text)
  to anon, authenticated;

notify pgrst, 'reload schema';
