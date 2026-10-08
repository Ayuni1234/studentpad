create table public.roommate_profiles (
  user_id uuid primary key
    constraint roommate_profiles_public_user_fkey
      references public.users(user_id) on delete cascade
    constraint roommate_profiles_auth_user_fkey
      references auth.users(id) on delete cascade,
  bio text not null default '' check (char_length(bio) <= 1200),
  major text not null check (char_length(btrim(major)) between 1 and 160),
  graduation_year integer not null
    check (graduation_year between 2000 and 2200),
  gender text not null default 'Prefer not to say'
    check (char_length(gender) between 1 and 80),
  housing_type_preference text not null
    check (housing_type_preference in ('On-campus', 'Off-campus', 'Either')),
  preferred_locations text[] not null default '{}'
    check (
      cardinality(preferred_locations) between 1 and 20
      and array_position(preferred_locations, null) is null
    ),
  budget_min_ghs numeric(12, 2) not null check (budget_min_ghs >= 0),
  budget_max_ghs numeric(12, 2) not null
    check (budget_max_ghs >= budget_min_ghs),
  -- Stores a private profile-photos bucket object path, never a public URL.
  avatar_url text check (
    avatar_url is null
    or (
      char_length(avatar_url) <= 512
      and split_part(avatar_url, '/', 1) = user_id::text
    )
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index roommate_profiles_discovery_idx
  on public.roommate_profiles (housing_type_preference, budget_min_ghs, budget_max_ghs);
create index roommate_profiles_locations_idx
  on public.roommate_profiles using gin (preferred_locations);

alter table public.roommate_profiles enable row level security;
revoke all on table public.roommate_profiles from public, anon, authenticated;
grant select on table public.roommate_profiles to authenticated;
grant insert (
  user_id,
  bio,
  major,
  graduation_year,
  gender,
  housing_type_preference,
  preferred_locations,
  budget_min_ghs,
  budget_max_ghs,
  avatar_url
) on table public.roommate_profiles to authenticated;
grant update (
  bio,
  major,
  graduation_year,
  gender,
  housing_type_preference,
  preferred_locations,
  budget_min_ghs,
  budget_max_ghs,
  avatar_url
) on table public.roommate_profiles to authenticated;

create function app_private.touch_roommate_profile_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function app_private.touch_roommate_profile_updated_at()
  from public, anon, authenticated;

create trigger roommate_profiles_updated_at
  before update on public.roommate_profiles
  for each row execute function app_private.touch_roommate_profile_updated_at();

create policy "Verified students discover roommate profiles"
  on public.roommate_profiles
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (
      app_private.is_verified_user((select auth.uid()))
      and app_private.is_verified_user(user_id)
    )
  );

create policy "Verified students create their roommate profile"
  on public.roommate_profiles
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and app_private.is_verified_user((select auth.uid()))
  );

create policy "Verified students update their roommate profile"
  on public.roommate_profiles
  for update
  to authenticated
  using (
    user_id = (select auth.uid())
    and app_private.is_verified_user((select auth.uid()))
  )
  with check (
    user_id = (select auth.uid())
    and app_private.is_verified_user((select auth.uid()))
  );

drop policy if exists "Users read their own profile photo" on storage.objects;
create policy "Users and verified roommate peers read profile photos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (
        app_private.is_verified_user((select auth.uid()))
        and exists (
          select 1
          from public.roommate_profiles rp
          join public.users u on u.user_id = rp.user_id
          where rp.user_id::text = (storage.foldername(name))[1]
            and u.is_verified
        )
      )
    )
  );
