-- Profiles are discoverable only when both the viewer and profile owner are verified.
drop policy if exists "Users read their own or verified profiles" on public.profiles;
create policy "Users read their own or verified profiles" on public.profiles
  for select to authenticated using (
    user_id = (select auth.uid()) or (
      app_private.is_verified_user((select auth.uid()))
      and app_private.is_verified_user(user_id)
    )
  );
