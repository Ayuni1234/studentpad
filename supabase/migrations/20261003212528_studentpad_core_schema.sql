-- StudentPad core schema. Student ID references stay private to their owner.
create extension if not exists pgcrypto;

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;

create table public.users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text check (full_name is null or char_length(full_name) between 1 and 120),
  university text check (university is null or char_length(university) <= 160),
  student_id_url text check (student_id_url is null or char_length(student_id_url) <= 2048),
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references public.users(user_id) on delete cascade,
  budget_min_ghs numeric(12,2) check (budget_min_ghs is null or budget_min_ghs >= 0),
  budget_max_ghs numeric(12,2) check (budget_max_ghs is null or budget_max_ghs >= 0),
  cleanliness_score smallint check (cleanliness_score between 1 and 5),
  sleep_schedule text check (sleep_schedule is null or char_length(sleep_schedule) <= 80),
  bio text check (bio is null or char_length(bio) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (budget_min_ghs is null or budget_max_ghs is null or budget_min_ghs <= budget_max_ghs)
);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(user_id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  description text not null default '' check (char_length(description) <= 5000),
  listing_type text not null check (listing_type in ('has_space', 'needs_space')),
  location text not null check (char_length(location) between 1 and 240),
  monthly_rent_ghs numeric(12,2) not null check (monthly_rent_ghs >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.chats (
  id uuid primary key default gen_random_uuid(),
  participant_one_id uuid not null references public.users(user_id) on delete cascade,
  participant_two_id uuid not null references public.users(user_id) on delete cascade,
  created_by uuid not null references public.users(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  check (participant_one_id <> participant_two_id),
  check (created_by = participant_one_id or created_by = participant_two_id)
);

create unique index chats_participants_unique_idx on public.chats (
  least(participant_one_id, participant_two_id),
  greatest(participant_one_id, participant_two_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null references public.users(user_id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index listings_browse_idx on public.listings (listing_type, location, monthly_rent_ghs)
  where is_active;
create index messages_chat_created_idx on public.messages (chat_id, created_at desc);

-- This helper reveals only whether a target user is verified. It is kept out
-- of exposed schemas and can only be executed by authenticated callers.
create function app_private.is_verified_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1 from public.users u
      where u.user_id = target_user_id and u.is_verified
    );
$$;
revoke all on function app_private.is_verified_user(uuid) from public, anon;
grant execute on function app_private.is_verified_user(uuid) to authenticated;

alter table public.users enable row level security;
alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.chats enable row level security;
alter table public.messages enable row level security;

-- User account rows, including student ID references, are owner-only.
create policy "Users read their own account" on public.users
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Users create their own account" on public.users
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users update their own account" on public.users
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- The verification flag is database-managed: client roles cannot write it.
revoke all on table public.users from public, anon, authenticated;
grant select on table public.users to authenticated;
grant insert (user_id, full_name, university, student_id_url)
  on table public.users to authenticated;
grant update (full_name, university, student_id_url)
  on table public.users to authenticated;

-- Only verified students can discover one another's profile and listings.
create policy "Users read their own or verified profiles" on public.profiles
  for select to authenticated using (
    user_id = (select auth.uid()) or app_private.is_verified_user(user_id)
  );
create policy "Users create their own profile" on public.profiles
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users update their own profile" on public.profiles
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;
grant insert (user_id, budget_min_ghs, budget_max_ghs, cleanliness_score, sleep_schedule, bio)
  on table public.profiles to authenticated;
grant update (budget_min_ghs, budget_max_ghs, cleanliness_score, sleep_schedule, bio, updated_at)
  on table public.profiles to authenticated;

create policy "Verified students read active listings" on public.listings
  for select to authenticated using (
    (is_active and app_private.is_verified_user((select auth.uid())))
    or owner_id = (select auth.uid())
  );
create policy "Verified students create their own listings" on public.listings
  for insert to authenticated with check (
    owner_id = (select auth.uid()) and app_private.is_verified_user((select auth.uid()))
  );
create policy "Owners update their listings" on public.listings
  for update to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
create policy "Owners delete their listings" on public.listings
  for delete to authenticated using (owner_id = (select auth.uid()));
revoke all on table public.listings from public, anon, authenticated;
grant select, delete on table public.listings to authenticated;
grant insert (owner_id, title, description, listing_type, location, monthly_rent_ghs)
  on table public.listings to authenticated;
grant update (title, description, listing_type, location, monthly_rent_ghs, is_active, updated_at)
  on table public.listings to authenticated;

create policy "Chat participants read their chats" on public.chats
  for select to authenticated using (
    participant_one_id = (select auth.uid()) or participant_two_id = (select auth.uid())
  );
create policy "Verified students create chats with verified peers" on public.chats
  for insert to authenticated with check (
    created_by = (select auth.uid())
    and (participant_one_id = (select auth.uid()) or participant_two_id = (select auth.uid()))
    and app_private.is_verified_user(participant_one_id)
    and app_private.is_verified_user(participant_two_id)
  );
revoke all on table public.chats from public, anon, authenticated;
grant select on table public.chats to authenticated;
grant insert (participant_one_id, participant_two_id, created_by)
  on table public.chats to authenticated;

create policy "Chat participants read messages" on public.messages
  for select to authenticated using (
    exists (
      select 1 from public.chats c
      where c.id = chat_id
        and (c.participant_one_id = (select auth.uid()) or c.participant_two_id = (select auth.uid()))
    )
  );
create policy "Chat participants send messages as themselves" on public.messages
  for insert to authenticated with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.chats c
      where c.id = chat_id
        and (c.participant_one_id = (select auth.uid()) or c.participant_two_id = (select auth.uid()))
    )
  );
revoke all on table public.messages from public, anon, authenticated;
grant select on table public.messages to authenticated;
grant insert (chat_id, sender_id, body) on table public.messages to authenticated;

-- Enable Postgres Changes for authenticated real-time message subscribers.
alter publication supabase_realtime add table public.messages;
