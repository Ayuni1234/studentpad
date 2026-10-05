-- Contact numbers belong to the account owner. They are never exposed through
-- the general users SELECT grant; approved listing peers get them only from a
-- narrowly scoped RPC for an active listing.
alter table public.users
  add column phone_number text,
  add column whatsapp_number text,
  add column whatsapp_uses_phone boolean not null default false,
  add constraint users_phone_number_format_check check (
    phone_number is null or phone_number ~ '^\+[1-9][0-9]{7,14}$'
  ),
  add constraint users_whatsapp_number_format_check check (
    whatsapp_number is null or whatsapp_number ~ '^\+[1-9][0-9]{7,14}$'
  ),
  add constraint users_whatsapp_phone_required_check check (
    not whatsapp_uses_phone or phone_number is not null
  );

grant insert (phone_number, whatsapp_number, whatsapp_uses_phone)
  on table public.users to authenticated;
grant update (phone_number, whatsapp_number, whatsapp_uses_phone)
  on table public.users to authenticated;

create function app_private._my_contact_details()
returns table (
  phone_number text,
  whatsapp_number text,
  whatsapp_uses_phone boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select u.phone_number, u.whatsapp_number, u.whatsapp_uses_phone
  from public.users u
  where u.user_id = (select auth.uid())
    and (select auth.uid()) is not null;
$$;
revoke all on function app_private._my_contact_details() from public, anon;
grant execute on function app_private._my_contact_details() to authenticated;

create function public.my_contact_details()
returns table (
  phone_number text,
  whatsapp_number text,
  whatsapp_uses_phone boolean
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from app_private._my_contact_details(); $$;
revoke all on function public.my_contact_details() from public, anon;
grant execute on function public.my_contact_details() to authenticated;

create function app_private._listing_owner_contact(p_listing_id uuid)
returns table (
  owner_name text,
  phone_number text,
  whatsapp_number text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    owner.full_name,
    owner.phone_number,
    case
      when owner.whatsapp_uses_phone then owner.phone_number
      else owner.whatsapp_number
    end
  from public.listings l
  join public.users owner on owner.user_id = l.owner_id
  where l.id = p_listing_id
    and l.is_active
    and (select auth.uid()) is not null
    and l.owner_id <> (select auth.uid())
    and owner.is_verified
    and owner.verification_status = 'approved'
    and exists (
      select 1
      from public.users viewer
      where viewer.user_id = (select auth.uid())
        and viewer.is_verified
        and viewer.verification_status = 'approved'
    )
    and not exists (
      select 1
      from public.user_blocks b
      where (b.blocker_id = l.owner_id and b.blocked_user_id = (select auth.uid()))
         or (b.blocker_id = (select auth.uid()) and b.blocked_user_id = l.owner_id)
    );
$$;
revoke all on function app_private._listing_owner_contact(uuid) from public, anon;
grant execute on function app_private._listing_owner_contact(uuid) to authenticated;

create function public.listing_owner_contact(p_listing_id uuid)
returns table (
  owner_name text,
  phone_number text,
  whatsapp_number text
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from app_private._listing_owner_contact(p_listing_id); $$;
revoke all on function public.listing_owner_contact(uuid) from public, anon;
grant execute on function public.listing_owner_contact(uuid) to authenticated;
