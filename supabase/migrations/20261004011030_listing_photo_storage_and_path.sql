alter table public.listings
  add column if not exists image_path text
  check (image_path is null or char_length(image_path) <= 512);

grant insert (image_path) on table public.listings to authenticated;
grant update (image_path) on table public.listings to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'listing-photos',
  'listing-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "Verified students upload their listing photos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'listing-photos'
    and app_private.is_verified_user((select auth.uid()))
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Verified students read listing photos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'listing-photos'
    and app_private.is_verified_user((select auth.uid()))
  );

create policy "Students remove their own listing photos"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
