create extension if not exists pgcrypto;

create table if not exists public.parent_link_codes (
  id uuid primary key default gen_random_uuid(),
  student_id bigint not null references public.students(id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null default (now() + interval '30 days'),
  used_by uuid references public.profiles(id) on delete set null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists parent_link_codes_active_student_uidx
  on public.parent_link_codes(student_id)
  where used_at is null;

alter table public.parent_link_codes enable row level security;
revoke all on public.parent_link_codes from anon, authenticated;

create or replace function public.create_parent_codes_for_class(p_class_name text)
returns table (
  student_no integer,
  full_name text,
  student_id_no text,
  link_code text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  item record;
  generated_code text;
  expiry timestamptz := now() + interval '30 days';
begin
  for item in
    select s.id, s.student_no, s.full_name, s.student_id_no
    from public.students s
    join public.classes c on c.id = s.class_id
    where c.name = p_class_name
    order by s.student_no
  loop
    generated_code := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10));

    delete from public.parent_link_codes plc
    where plc.student_id = item.id
      and plc.used_at is null;

    insert into public.parent_link_codes (student_id, code_hash, expires_at)
    values (
      item.id,
      encode(digest(generated_code, 'sha256'), 'hex'),
      expiry
    );

    student_no := item.student_no;
    full_name := item.full_name;
    student_id_no := item.student_id_no;
    link_code := generated_code;
    expires_at := expiry;
    return next;
  end loop;
end;
$$;

revoke all on function public.create_parent_codes_for_class(text) from public, anon, authenticated;

create or replace function public.create_parent_code_for_student(p_student_id_no text)
returns table (
  full_name text,
  student_id_no text,
  link_code text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  item record;
  generated_code text := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10));
  expiry timestamptz := now() + interval '30 days';
begin
  select s.id, s.full_name, s.student_id_no
  into item
  from public.students s
  where s.student_id_no = trim(p_student_id_no)
  limit 1;

  if item.id is null then
    raise exception 'ไม่พบเลขประจำตัวนักเรียน';
  end if;

  delete from public.parent_link_codes plc
  where plc.student_id = item.id
    and plc.used_at is null;

  insert into public.parent_link_codes (student_id, code_hash, expires_at)
  values (item.id, encode(digest(generated_code, 'sha256'), 'hex'), expiry);

  full_name := item.full_name;
  student_id_no := item.student_id_no;
  link_code := generated_code;
  expires_at := expiry;
  return next;
end;
$$;

revoke all on function public.create_parent_code_for_student(text) from public, anon, authenticated;

create or replace function public.claim_parent_student(
  p_student_id_no text,
  p_link_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  matched_code public.parent_link_codes%rowtype;
  student_row public.students%rowtype;
  parent_name text;
begin
  if current_user_id is null then
    raise exception 'กรุณาเข้าสู่ระบบและยืนยันอีเมลก่อน';
  end if;

  select s.*
  into student_row
  from public.students s
  where s.student_id_no = trim(p_student_id_no)
  limit 1;

  if student_row.id is null then
    raise exception 'ไม่พบเลขประจำตัวนักเรียน';
  end if;

  if exists (
    select 1
    from public.parent_student ps
    where ps.parent_id = current_user_id
      and ps.student_id = student_row.id
  ) then
    return jsonb_build_object(
      'success', true,
      'already_linked', true,
      'student_id', student_row.id,
      'student_name', student_row.full_name
    );
  end if;

  select plc.*
  into matched_code
  from public.parent_link_codes plc
  where plc.student_id = student_row.id
    and plc.used_at is null
    and plc.expires_at > now()
    and plc.code_hash = encode(digest(upper(trim(p_link_code)), 'sha256'), 'hex')
  for update;

  if matched_code.id is null then
    raise exception 'รหัสเชื่อมบัญชีไม่ถูกต้อง หมดอายุ หรือถูกใช้แล้ว';
  end if;

  select coalesce(
    nullif(raw_user_meta_data->>'full_name', ''),
    split_part(email, '@', 1)
  )
  into parent_name
  from auth.users
  where id = current_user_id;

  insert into public.profiles (id, full_name, role)
  values (current_user_id, parent_name, 'parent')
  on conflict (id) do update
  set full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
      role = case
        when public.profiles.role = 'teacher' then 'teacher_parent'
        else public.profiles.role
      end;

  insert into public.parent_student (parent_id, student_id)
  values (current_user_id, student_row.id)
  on conflict do nothing;

  update public.parent_link_codes
  set used_by = current_user_id,
      used_at = now()
  where id = matched_code.id;

  return jsonb_build_object(
    'success', true,
    'student_id', student_row.id,
    'student_name', student_row.full_name
  );
end;
$$;

revoke all on function public.claim_parent_student(text, text) from public, anon;
grant execute on function public.claim_parent_student(text, text) to authenticated;

create or replace function public.handle_parent_self_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.raw_user_meta_data->>'registration_source' = 'school_parent' then
    insert into public.profiles (id, full_name, role)
    values (
      new.id,
      coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(new.email, '@', 1)),
      'parent'
    )
    on conflict (id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_parent_self_signup on auth.users;
create trigger on_parent_self_signup
after insert on auth.users
for each row
execute function public.handle_parent_self_signup();

notify pgrst, 'reload schema';
