-- A listing chat RPC must always return an existing participant-visible chat
-- or fail with a useful error. Never let a null UUID reach the Flutter router.
create or replace function app_private._start_listing_chat(p_listing_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_owner_id uuid;
  v_first_id uuid;
  v_second_id uuid;
  v_chat_id uuid;
begin
  if v_viewer_id is null then
    raise exception using errcode = '42501', message = 'Sign in to contact this student.';
  end if;

  if not app_private.is_approved_listing_owner(v_viewer_id) then
    raise exception using errcode = '42501', message = 'Approved student verification is required to contact students.';
  end if;

  select l.owner_id into v_owner_id
  from public.listings l
  where l.id = p_listing_id
    and l.is_active
    and app_private.is_approved_listing_owner(l.owner_id);

  if v_owner_id is null then
    raise exception using errcode = 'P0002', message = 'This listing is unavailable for contact.';
  end if;
  if v_owner_id = v_viewer_id then
    raise exception using errcode = '22023', message = 'You cannot message yourself.';
  end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = v_owner_id and b.blocked_user_id = v_viewer_id)
       or (b.blocker_id = v_viewer_id and b.blocked_user_id = v_owner_id)
  ) then
    raise exception using errcode = '42501', message = 'Contact is unavailable.';
  end if;

  v_first_id := least(v_viewer_id, v_owner_id);
  v_second_id := greatest(v_viewer_id, v_owner_id);

  select c.id into v_chat_id
  from public.chats c
  where c.participant_one_id = v_first_id
    and c.participant_two_id = v_second_id;

  if v_chat_id is null then
    insert into public.chats (participant_one_id, participant_two_id, created_by)
    values (v_first_id, v_second_id, v_viewer_id)
    on conflict do nothing;

    select c.id into v_chat_id
    from public.chats c
    where c.participant_one_id = v_first_id
      and c.participant_two_id = v_second_id;
  end if;

  if v_chat_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Could not create or find the conversation. Please try again.';
  end if;

  return v_chat_id;
end;
$$;

revoke all on function app_private._start_listing_chat(uuid) from public, anon, authenticated;
grant execute on function app_private._start_listing_chat(uuid) to authenticated;

create or replace function public.start_listing_chat(p_listing_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return app_private._start_listing_chat(p_listing_id);
end;
$$;

revoke all on function public.start_listing_chat(uuid) from public, anon, authenticated;
grant execute on function public.start_listing_chat(uuid) to authenticated;
