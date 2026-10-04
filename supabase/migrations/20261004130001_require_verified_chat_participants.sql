drop policy if exists "Chat participants read their chats" on public.chats;
create policy "Verified chat participants read their chats"
  on public.chats
  for select
  to authenticated
  using (
    (
      participant_one_id = (select auth.uid())
      or participant_two_id = (select auth.uid())
    )
    and app_private.is_verified_user((select auth.uid()))
    and app_private.is_verified_user(participant_one_id)
    and app_private.is_verified_user(participant_two_id)
  );

drop policy if exists "Chat participants read messages" on public.messages;
create policy "Verified chat participants read messages"
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.chats c
      where c.id = chat_id
        and (
          c.participant_one_id = (select auth.uid())
          or c.participant_two_id = (select auth.uid())
        )
        and app_private.is_verified_user((select auth.uid()))
        and app_private.is_verified_user(c.participant_one_id)
        and app_private.is_verified_user(c.participant_two_id)
    )
  );

drop policy if exists "Chat participants send messages as themselves" on public.messages;
create policy "Verified chat participants send messages as themselves"
  on public.messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1
      from public.chats c
      where c.id = chat_id
        and (
          c.participant_one_id = (select auth.uid())
          or c.participant_two_id = (select auth.uid())
        )
        and app_private.is_verified_user((select auth.uid()))
        and app_private.is_verified_user(c.participant_one_id)
        and app_private.is_verified_user(c.participant_two_id)
    )
  );
