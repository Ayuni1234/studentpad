-- Let a student block or unblock another verified peer. Keep block records
-- private to the person who created them and enforce blocks inside Postgres.
create table public.user_blocks (
  blocker_id uuid not null references public.users(user_id) on delete cascade,
  blocked_user_id uuid not null references public.users(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_user_id),
  check (blocker_id <> blocked_user_id)
);

create index user_blocks_blocked_user_idx
  on public.user_blocks (blocked_user_id);

alter table public.user_blocks enable row level security;
revoke all on table public.user_blocks from public, anon, authenticated;
grant select, insert, delete on table public.user_blocks to authenticated;

create policy "Students read their own blocked peers" on public.user_blocks
  for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy "Students block peers as themselves" on public.user_blocks
  for insert to authenticated
  with check (
    blocker_id = (select auth.uid())
    and blocked_user_id <> (select auth.uid())
  );

create policy "Students unblock peers they blocked" on public.user_blocks
  for delete to authenticated
  using (blocker_id = (select auth.uid()));

create function app_private.prevent_blocked_peer_interaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  first_user_id uuid;
  second_user_id uuid;
begin
  if tg_table_name = 'chats' then
    first_user_id := new.participant_one_id;
    second_user_id := new.participant_two_id;
  else
    select c.participant_one_id, c.participant_two_id
      into first_user_id, second_user_id
    from public.chats c
    where c.id = new.chat_id;
  end if;

  if exists (
    select 1
    from public.user_blocks b
    where (b.blocker_id = first_user_id and b.blocked_user_id = second_user_id)
       or (b.blocker_id = second_user_id and b.blocked_user_id = first_user_id)
  ) then
    raise exception using
      errcode = '23514',
      message = 'This interaction is unavailable because one participant blocked the other.';
  end if;

  return new;
end;
$$;

revoke all on function app_private.prevent_blocked_peer_interaction() from public, anon, authenticated;

create trigger chats_prevent_blocked_peer_interaction
  before insert on public.chats
  for each row execute function app_private.prevent_blocked_peer_interaction();

create trigger messages_prevent_blocked_peer_interaction
  before insert on public.messages
  for each row execute function app_private.prevent_blocked_peer_interaction();
