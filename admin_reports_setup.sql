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

notify pgrst, 'reload schema';
