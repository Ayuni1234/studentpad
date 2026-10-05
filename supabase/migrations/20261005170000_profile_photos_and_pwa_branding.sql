-- Profile photos remain private and each account can access only its own file.
alter table public.profiles
  add column if not exists avatar_path text;

alter table public.profiles
  drop constraint if exists profiles_avatar_path_owner_check;

alter table public.profiles
  add constraint profiles_avatar_path_owner_check
  check (
    avatar_path is null
    or (
      char_length(avatar_path) <= 512
      and split_part(avatar_path, '/', 1) = user_id::text
    )
  );

grant insert (user_id, avatar_path)
  on table public.profiles to authenticated;
grant update (avatar_path)
  on table public.profiles to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'profile-photos',
  'profile-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users upload their own profile photo" on storage.objects;
create policy "Users upload their own profile photo"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users read their own profile photo" on storage.objects;
create policy "Users read their own profile photo"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users delete their own profile photo" on storage.objects;
create policy "Users delete their own profile photo"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
