alter table public.roommate_profiles
  add column allow_direct_contact boolean not null default false;

create function app_private._roommate_profile_contact(p_peer_user_id uuid)
returns table (
  phone_number text,
  whatsapp_number text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    owner.phone_number,
    case
      when owner.whatsapp_uses_phone then owner.phone_number
      else owner.whatsapp_number
    end
  from public.roommate_profiles rp
  join public.users owner on owner.user_id = rp.user_id
  join public.users viewer on viewer.user_id = (select auth.uid())
  where rp.user_id = p_peer_user_id
    and rp.user_id <> (select auth.uid())
    and rp.allow_direct_contact
    and owner.is_verified
    and owner.verification_status = 'approved'
    and viewer.is_verified
    and viewer.verification_status = 'approved'
    and (
      owner.phone_number is not null
      or owner.whatsapp_number is not null
      or (owner.whatsapp_uses_phone and owner.phone_number is not null)
    )
    and not exists (
      select 1
      from public.user_blocks b
      where (b.blocker_id = owner.user_id
             and b.blocked_user_id = viewer.user_id)
         or (b.blocker_id = viewer.user_id
             and b.blocked_user_id = owner.user_id)
    );
$$;
revoke all on function app_private._roommate_profile_contact(uuid)
  from public, anon, authenticated;
grant execute on function app_private._roommate_profile_contact(uuid)
  to authenticated;

create function public.roommate_profile_contact(p_peer_user_id uuid)
returns table (
  phone_number text,
  whatsapp_number text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from app_private._roommate_profile_contact(p_peer_user_id);
$$;
revoke all on function public.roommate_profile_contact(uuid)
  from public, anon;
grant execute on function public.roommate_profile_contact(uuid)
  to authenticated;
