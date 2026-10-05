create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(user_id) on delete cascade,
  notification_type text not null check (
    notification_type in ('message', 'verification_approved', 'verification_rejected')
  ),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 300),
  chat_id uuid references public.chats(id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index notifications_user_created_idx
  on public.notifications (user_id, created_at desc);
create index notifications_unread_user_idx
  on public.notifications (user_id)
  where read_at is null;

alter table public.notifications enable row level security;
revoke all on table public.notifications from public, anon, authenticated;
grant select on table public.notifications to authenticated;
grant update (read_at) on table public.notifications to authenticated;

create policy "Users read their own notifications"
  on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Users mark their own notifications as read"
  on public.notifications for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and read_at is not null);

create or replace function app_private.notify_message_recipient()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
begin
  select case
    when c.participant_one_id = new.sender_id then c.participant_two_id
    when c.participant_two_id = new.sender_id then c.participant_one_id
    else null
  end
  into v_recipient
  from public.chats c
  where c.id = new.chat_id;

  if v_recipient is not null then
    insert into public.notifications (user_id, notification_type, title, body, chat_id)
    values (
      v_recipient,
      'message',
      'New message',
      'A student sent you a message.',
      new.chat_id
    );
  end if;
  return new;
end;
$$;
revoke all on function app_private.notify_message_recipient() from public, anon, authenticated;

drop trigger if exists notify_message_recipient on public.messages;
create trigger notify_message_recipient
  after insert on public.messages
  for each row execute function app_private.notify_message_recipient();

create or replace function app_private.notify_verification_decision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.verification_status is distinct from old.verification_status then
    if new.verification_status = 'approved' then
      insert into public.notifications (user_id, notification_type, title, body)
      values (new.user_id, 'verification_approved', 'Student verification approved',
              'Your account is verified. You can now contact other students.');
    elsif new.verification_status = 'rejected' then
      insert into public.notifications (user_id, notification_type, title, body)
      values (new.user_id, 'verification_rejected', 'Verification needs attention',
              'Please review your student ID submission and try again.');
    end if;
  end if;
  return new;
end;
$$;
revoke all on function app_private.notify_verification_decision() from public, anon, authenticated;

drop trigger if exists notify_verification_decision on public.users;
create trigger notify_verification_decision
  after update of verification_status on public.users
  for each row execute function app_private.notify_verification_decision();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
