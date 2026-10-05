-- Suspend access to sensitive owner contacts as well as normal table access.
create or replace function app_private._listing_owner_contact(p_listing_id uuid)
returns table (owner_name text, phone_number text, whatsapp_number text)
language sql
stable
security definer
set search_path = ''
as $$
  select owner.full_name,
    owner.phone_number,
    case when owner.whatsapp_uses_phone then owner.phone_number
         else owner.whatsapp_number end
  from public.listings l
  join public.users owner on owner.user_id = l.owner_id
  where l.id = p_listing_id
    and l.is_active
    and l.owner_id <> (select auth.uid())
    and owner.is_verified
    and owner.verification_status = 'approved'
    and owner.account_status = 'active'
    and exists (
      select 1 from public.users viewer
      where viewer.user_id = (select auth.uid())
        and viewer.is_verified
        and viewer.verification_status = 'approved'
        and viewer.account_status = 'active'
    )
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = l.owner_id and b.blocked_user_id = (select auth.uid()))
         or (b.blocker_id = (select auth.uid()) and b.blocked_user_id = l.owner_id)
    );
$$;
revoke all on function app_private._listing_owner_contact(uuid) from public, anon;
grant execute on function app_private._listing_owner_contact(uuid) to authenticated;

-- The prior reviewer RPC predates moderation audit logging. Disable it so all
-- verification decisions pass through the audited admin endpoint.
revoke all on function public.review_student_verification(uuid, boolean)
  from public, anon, authenticated;
revoke all on function app_private._review_student_verification(uuid, boolean)
  from public, anon, authenticated;
