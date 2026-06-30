create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  student_id bigint not null references public.students(id) on delete cascade,
  parent_id uuid not null references public.profiles(id) on delete cascade,
  leave_date date not null,
  leave_type text not null check (leave_type in ('sick', 'personal', 'other')),
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.leave_requests
  drop constraint if exists leave_requests_student_id_leave_date_key;
create unique index if not exists leave_requests_active_student_date_uidx
  on public.leave_requests(student_id, leave_date)
  where status in ('pending', 'approved');

create index if not exists leave_requests_parent_idx
  on public.leave_requests(parent_id, created_at desc);
create index if not exists leave_requests_student_idx
  on public.leave_requests(student_id, leave_date desc);
create index if not exists leave_requests_status_idx
  on public.leave_requests(status, created_at desc);

alter table public.leave_requests enable row level security;

drop policy if exists leave_requests_select on public.leave_requests;
create policy leave_requests_select
on public.leave_requests
for select
to authenticated
using (
  parent_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'finance')
  )
  or exists (
    select 1
    from public.students s
    join public.teacher_class tc on tc.class_id = s.class_id
    where s.id = leave_requests.student_id
      and tc.teacher_id = auth.uid()
  )
);

drop policy if exists leave_requests_insert on public.leave_requests;
create policy leave_requests_insert
on public.leave_requests
for insert
to authenticated
with check (
  parent_id = auth.uid()
  and exists (
    select 1
    from public.parent_student ps
    where ps.parent_id = auth.uid()
      and ps.student_id = leave_requests.student_id
  )
);

drop policy if exists leave_requests_update on public.leave_requests;
create policy leave_requests_update
on public.leave_requests
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
  or exists (
    select 1
    from public.students s
    join public.teacher_class tc on tc.class_id = s.class_id
    where s.id = leave_requests.student_id
      and tc.teacher_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
  or exists (
    select 1
    from public.students s
    join public.teacher_class tc on tc.class_id = s.class_id
    where s.id = leave_requests.student_id
      and tc.teacher_id = auth.uid()
  )
);

grant select, insert, update on public.leave_requests to authenticated;

create or replace function public.sync_approved_leave_to_attendance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    update public.attendance
    set status = 'leave'
    where student_id = new.student_id
      and date = new.leave_date;

    if not found then
      insert into public.attendance (student_id, date, status)
      values (new.student_id, new.leave_date, 'leave');
    end if;
  elsif new.status = 'rejected' and old.status = 'approved' then
    delete from public.attendance
    where student_id = new.student_id
      and date = new.leave_date
      and status = 'leave';
  end if;

  return new;
end;
$$;

drop trigger if exists sync_approved_leave on public.leave_requests;
create trigger sync_approved_leave
after update of status on public.leave_requests
for each row
execute function public.sync_approved_leave_to_attendance();
