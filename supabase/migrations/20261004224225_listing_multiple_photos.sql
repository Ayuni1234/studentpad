alter table public.listings
  add column if not exists images text[] not null default '{}'::text[];

update public.listings
set images = array[image_path]::text[]
where image_path is not null
  and cardinality(images) = 0;

alter table public.listings
  add constraint listings_images_max_six_check
  check (
    cardinality(images) <= 6
    and array_position(images, null) is null
    and array_position(images, '') is null
  );

grant insert (images) on table public.listings to authenticated;
grant update (images) on table public.listings to authenticated;

update storage.buckets
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'listing-photos';

create or replace function app_private.can_upload_listing_photo(p_object_name text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_path_parts text[];
  v_listing_id text;
  v_image_paths text[];
  v_existing_count bigint;
begin
  if v_user_id is null then
    return false;
  end if;

  v_path_parts := storage.foldername(p_object_name);
  if pg_catalog.cardinality(v_path_parts) <> 2
     or v_path_parts[1] <> v_user_id::text then
    return false;
  end if;

  select l.id::text, l.images
    into v_listing_id, v_image_paths
  from public.listings l
  join public.users u on u.user_id = l.owner_id
  where l.id::text = v_path_parts[2]
    and l.owner_id = v_user_id
    and u.is_verified
    and u.verification_status = 'approved';

  if v_listing_id is null then
    return false;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_listing_id, 0)
  );

  select count(*)
    into v_existing_count
  from storage.objects o
  where o.bucket_id = 'listing-photos'
    and (
      (
        (storage.foldername(o.name))[1] = v_user_id::text
        and (storage.foldername(o.name))[2] = v_listing_id
      )
      or o.name = any(v_image_paths)
    );

  return v_existing_count < 6;
end;
$function$;

revoke all on function app_private.can_upload_listing_photo(text) from public, anon;
grant execute on function app_private.can_upload_listing_photo(text) to authenticated;

drop policy if exists "Verified students upload their listing photos" on storage.objects;
create policy "Verified students upload their listing photos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'listing-photos'
    and app_private.can_upload_listing_photo(name)
  );
