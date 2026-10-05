-- Publish listing details for browsing while keeping owner identity and all
-- contact information private until the viewer passes verification.

create or replace function app_private.is_approved_listing_owner(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users u
    where u.user_id = target_user_id
      and u.is_verified
      and u.verification_status = 'approved'
  );
$$;
revoke all on function app_private.is_approved_listing_owner(uuid) from public, anon, authenticated;
grant usage on schema app_private to anon, authenticated;
grant execute on function app_private.is_approved_listing_owner(uuid) to anon, authenticated;

grant select (
  id,
  title,
  description,
  listing_type,
  location,
  monthly_rent_ghs,
  image_path,
  images,
  created_at
) on public.listings to anon;

drop policy if exists "Verified students read active listings from verified owners"
  on public.listings;
create policy "Anyone can browse active listings from approved owners"
  on public.listings
  for select
  to anon
  using (
    is_active
    and app_private.is_approved_listing_owner(owner_id)
  );

create policy "Students browse active listings and their own listings"
  on public.listings
  for select
  to authenticated
  using (
    (
      is_active
      and app_private.is_approved_listing_owner(owner_id)
    )
    or owner_id = (select auth.uid())
  );

-- Listing images are marketplace content. Making only this bucket public lets
-- guests load images by known path; existing insert/delete RLS still protects
-- who may manage the underlying objects.
update storage.buckets
set public = true
where id = 'listing-photos';

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

  select l.owner_id
    into v_owner_id
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
    insert into public.chats (
      participant_one_id,
      participant_two_id,
      created_by
    ) values (v_first_id, v_second_id, v_viewer_id)
    on conflict do nothing;

    select c.id into v_chat_id
    from public.chats c
    where c.participant_one_id = v_first_id
      and c.participant_two_id = v_second_id;
  end if;

  return v_chat_id;
end;
$$;
revoke all on function app_private._start_listing_chat(uuid) from public, anon, authenticated;
grant execute on function app_private._start_listing_chat(uuid) to authenticated;

create or replace function public.start_listing_chat(p_listing_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select app_private._start_listing_chat(p_listing_id);
$$;
revoke all on function public.start_listing_chat(uuid) from public, anon, authenticated;
grant execute on function public.start_listing_chat(uuid) to authenticated;
