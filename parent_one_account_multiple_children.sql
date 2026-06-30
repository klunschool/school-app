-- นักเรียน 1 คนมีผู้ปกครองหลัก 1 บัญชี
-- ผู้ปกครอง 1 บัญชีผูกนักเรียนได้หลายคน

do $$
begin
  if exists (
    select student_id
    from public.parent_student
    group by student_id
    having count(distinct parent_id) > 1
  ) then
    raise exception 'พบนักเรียนที่ผูกผู้ปกครองมากกว่า 1 บัญชี กรุณาตรวจสอบ parent_student ก่อนติดตั้ง';
  end if;
end;
$$;

create unique index if not exists parent_student_one_parent_per_student
  on public.parent_student (student_id);

create or replace function public.review_parent_link_request(
  p_request_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.parent_link_requests%rowtype;
  existing_parent uuid;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'ไม่มีสิทธิ์อนุมัติรายการ';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'สถานะไม่ถูกต้อง';
  end if;

  select * into request_row
  from public.parent_link_requests
  where id = p_request_id
  for update;

  if request_row.id is null then
    raise exception 'ไม่พบคำขอ';
  end if;

  if p_decision = 'approved' then
    select parent_id into existing_parent
    from public.parent_student
    where student_id = request_row.student_id
    limit 1;

    if existing_parent is not null and existing_parent <> request_row.parent_id then
      raise exception 'นักเรียนคนนี้ผูกกับบัญชีผู้ปกครองอื่นแล้ว';
    end if;

    insert into public.parent_student (parent_id, student_id)
    values (request_row.parent_id, request_row.student_id)
    on conflict do nothing;
  end if;

  update public.parent_link_requests
  set status = p_decision,
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = p_request_id;

  return jsonb_build_object('success', true, 'status', p_decision);
end;
$$;

revoke all on function public.review_parent_link_request(uuid, text)
  from public, anon;
grant execute on function public.review_parent_link_request(uuid, text)
  to authenticated;

notify pgrst, 'reload schema';
