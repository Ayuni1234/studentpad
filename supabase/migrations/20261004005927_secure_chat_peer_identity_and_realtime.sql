-- Expose only basic student identity fields to verified peers for the inbox.
revoke select on table public.users from public, anon, authenticated;
grant select (user_id, full_name, university, is_verified)
  on table public.users to authenticated;

create policy "Verified students discover verified users"
  on public.users
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (
      is_verified
      and app_private.is_verified_user((select auth.uid()))
    )
  );

-- The inbox subscribes to conversation creation as well as message inserts.
alter publication supabase_realtime add table public.chats;
