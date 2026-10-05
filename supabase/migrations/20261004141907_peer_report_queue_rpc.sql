-- Return only report-queue fields to trusted reviewers. The RPC supplies the
-- student names needed for moderation without broadening users-table RLS.
drop policy if exists "Reviewers read all conversation reports"
  on public.conversation_reports;

create function app_private._pending_conversation_reports()
returns table (
  id uuid,
  reporter_id uuid,
  reporter_name text,
  reporter_university text,
  reported_user_id uuid,
  reported_user_name text,
  reported_user_university text,
  chat_id uuid,
  reason text,
  details text,
  status text,
  reviewer_note text,
  created_at timestamptz,
  reviewed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.is_studentpad_verification_reviewer() then
    raise exception 'Verification reviewer access required' using errcode = '42501';
  end if;

  return query
    select r.id,
           r.reporter_id,
           reporter.full_name,
           reporter.university,
           r.reported_user_id,
           reported.full_name,
           reported.university,
           r.chat_id,
           r.reason,
           r.details,
           r.status,
           r.reviewer_note,
           r.created_at,
           r.reviewed_at
    from public.conversation_reports r
    join public.users reporter on reporter.user_id = r.reporter_id
    join public.users reported on reported.user_id = r.reported_user_id
    order by r.created_at desc
    limit 200;
end;
$$;
revoke all on function app_private._pending_conversation_reports()
  from public, anon;
grant execute on function app_private._pending_conversation_reports()
  to authenticated;

create function public.pending_conversation_reports()
returns table (
  id uuid,
  reporter_id uuid,
  reporter_name text,
  reporter_university text,
  reported_user_id uuid,
  reported_user_name text,
  reported_user_university text,
  chat_id uuid,
  reason text,
  details text,
  status text,
  reviewer_note text,
  created_at timestamptz,
  reviewed_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from app_private._pending_conversation_reports(); $$;
revoke all on function public.pending_conversation_reports()
  from public, anon, authenticated;
grant execute on function public.pending_conversation_reports()
  to authenticated;
