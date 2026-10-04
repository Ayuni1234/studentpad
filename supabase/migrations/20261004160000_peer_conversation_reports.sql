-- Private, reviewer-managed reports submitted from peer conversations.
create table public.conversation_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.users(user_id) on delete cascade,
  reported_user_id uuid not null references public.users(user_id) on delete cascade,
  chat_id uuid not null references public.chats(id) on delete cascade,
  reason text not null check (reason in (
    'scam_or_fraud',
    'harassment_or_abuse',
    'unsafe_housing',
    'impersonation',
    'other'
  )),
  details text not null default '' check (char_length(details) <= 1000),
  status text not null default 'open'
    check (status in ('open', 'resolved', 'dismissed')),
  reviewer_note text check (reviewer_note is null or char_length(reviewer_note) <= 1000),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewer_id uuid references auth.users(id) on delete set null,
  check (reporter_id <> reported_user_id)
);

create index conversation_reports_open_idx
  on public.conversation_reports (created_at desc)
  where status = 'open';

alter table public.conversation_reports enable row level security;
revoke all on table public.conversation_reports from public, anon, authenticated;
grant select, insert on table public.conversation_reports to authenticated;

create policy "Reporters read their own reports" on public.conversation_reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));

create policy "Reviewers read all conversation reports" on public.conversation_reports
  for select to authenticated
  using (app_private.is_studentpad_verification_reviewer());

create policy "Verified students report their chat peer" on public.conversation_reports
  for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and reporter_id <> reported_user_id
    and app_private.is_verified_user((select auth.uid()))
    and app_private.is_verified_user(reported_user_id)
    and exists (
      select 1 from public.chats c
      where c.id = chat_id
        and (
          (c.participant_one_id = (select auth.uid())
            and c.participant_two_id = reported_user_id)
          or
          (c.participant_two_id = (select auth.uid())
            and c.participant_one_id = reported_user_id)
        )
    )
  );

create function app_private._review_conversation_report(
  p_report_id uuid,
  p_decision text,
  p_reviewer_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.is_studentpad_verification_reviewer() then
    raise exception 'Verification reviewer access required' using errcode = '42501';
  end if;
  if p_decision not in ('resolve', 'dismiss') then
    raise exception 'A valid report decision is required' using errcode = '22023';
  end if;
  if p_reviewer_note is not null and char_length(btrim(p_reviewer_note)) > 1000 then
    raise exception 'Reviewer notes must be at most 1000 characters' using errcode = '22023';
  end if;

  update public.conversation_reports
  set status = case when p_decision = 'resolve' then 'resolved' else 'dismissed' end,
      reviewer_note = nullif(btrim(p_reviewer_note), ''),
      reviewer_id = (select auth.uid()),
      reviewed_at = now()
  where id = p_report_id and status = 'open';
  if not found then
    raise exception 'No open conversation report was found' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function app_private._review_conversation_report(uuid, text, text)
  from public, anon;
grant execute on function app_private._review_conversation_report(uuid, text, text)
  to authenticated;

create function public.review_conversation_report(
  p_report_id uuid,
  p_decision text,
  p_reviewer_note text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select app_private._review_conversation_report(
    p_report_id, p_decision, p_reviewer_note
  );
$$;
revoke all on function public.review_conversation_report(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.review_conversation_report(uuid, text, text)
  to authenticated;
