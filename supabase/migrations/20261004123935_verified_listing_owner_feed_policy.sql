drop policy if exists "Verified students read active listings" on public.listings;
create policy "Verified students read active listings from verified owners"
  on public.listings
  for select
  to authenticated
  using (
    (
      is_active
      and app_private.is_verified_user((select auth.uid()))
      and app_private.is_verified_user(owner_id)
    )
    or owner_id = (select auth.uid())
  );
