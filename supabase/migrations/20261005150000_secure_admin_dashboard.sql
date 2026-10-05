-- StudentPad administrators use the server-managed reviewer allowlist. There
-- is intentionally no client-editable admin flag in public.users.
alter table public.users
  add column account_status text not null default 'active'
    check (account_status in ('active', 'suspended', 'banned')),
  add column moderation_note text,
  add column moderated_at timestamptz,
  add column moderated_by uuid references auth.users(id) on delete set null,
  add column verification_review_note text;

create index users_account_status_idx on public.users (account_status);
revoke update (account_status, moderation_note, moderated_at, moderated_by,
               verification_review_note)
  on public.users from anon, authenticated;

create table app_private.admin_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  target_type text not null,
  target_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table app_private.admin_audit_log enable row level security;
create policy "Admin audit log has no direct access"
  on app_private.admin_audit_log for all to authenticated
  using (false) with check (false);
revoke all on app_private.admin_audit_log from public, anon, authenticated;

create or replace function app_private.is_user_account_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and not exists (
      select 1 from public.users u
      where u.user_id = (select auth.uid())
        and u.account_status <> 'active'
    );
$$;
revoke all on function app_private.is_user_account_active() from public, anon;
grant execute on function app_private.is_user_account_active() to authenticated;

create or replace function app_private.is_studentpad_verification_reviewer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and app_private.is_user_account_active()
    and exists (
      select 1 from app_private.verification_reviewers r
      where r.user_id = (select auth.uid())
    );
$$;
revoke all on function app_private.is_studentpad_verification_reviewer() from public, anon;
grant execute on function app_private.is_studentpad_verification_reviewer() to authenticated;

create or replace function app_private.is_studentpad_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select app_private.is_studentpad_verification_reviewer(); $$;
revoke all on function app_private.is_studentpad_admin() from public, anon;
grant execute on function app_private.is_studentpad_admin() to authenticated;

create or replace function public.is_studentpad_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select app_private.is_studentpad_admin(); $$;
revoke all on function public.is_studentpad_admin() from public, anon;
grant execute on function public.is_studentpad_admin() to authenticated;

create or replace function app_private.is_verified_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and app_private.is_user_account_active()
    and exists (
      select 1 from public.users u
      where u.user_id = target_user_id
        and u.is_verified
        and u.account_status = 'active'
    );
$$;

create or replace function app_private.is_approved_listing_owner(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users u
    where u.user_id = target_user_id
      and u.is_verified
      and u.verification_status = 'approved'
      and u.account_status = 'active'
  );
$$;

-- Restrictive policies compose with existing ownership/verification rules.
-- Suspended accounts fail closed across every authenticated app table.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'users', 'profiles', 'listings', 'chats', 'messages',
    'user_blocks', 'conversation_reports'
  ] loop
    execute format(
      'drop policy if exists active_account_required on public.%I', table_name
    );
    execute format(
      'create policy active_account_required on public.%I as restrictive for all to authenticated using (app_private.is_user_account_active()) with check (app_private.is_user_account_active())',
      table_name
    );
  end loop;
end;
$$;

drop policy if exists active_account_required on storage.objects;
create policy active_account_required on storage.objects
  as restrictive for all to authenticated
  using (app_private.is_user_account_active())
  with check (app_private.is_user_account_active());

create or replace function public.my_account_access_state()
returns table (account_status text, moderation_note text)
language sql
stable
security definer
set search_path = ''
as $$
  select u.account_status, u.moderation_note
  from public.users u
  where u.user_id = (select auth.uid())
    and (select auth.uid()) is not null;
$$;
revoke all on function public.my_account_access_state() from public, anon;
grant execute on function public.my_account_access_state() to authenticated;

create function public.admin_dashboard_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'pending_verifications', (select count(*) from public.users where verification_status = 'pending'),
    'active_listings', (select count(*) from public.listings where is_active),
    'registered_users', (select count(*) from public.users),
    'restricted_accounts', (select count(*) from public.users where account_status <> 'active')
  ) into result;
  return result;
end;
$$;
revoke all on function public.admin_dashboard_summary() from public, anon;
grant execute on function public.admin_dashboard_summary() to authenticated;

create function public.admin_verification_queue()
returns table (
  user_id uuid, full_name text, university text, student_id_url text,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  return query
    select u.user_id, u.full_name, u.university, u.student_id_url, u.updated_at
    from public.users u
    where u.verification_status = 'pending'
    order by u.updated_at asc;
end;
$$;
revoke all on function public.admin_verification_queue() from public, anon;
grant execute on function public.admin_verification_queue() to authenticated;

create function public.admin_review_verification(
  p_student_user_id uuid, p_approved boolean, p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare clean_note text := nullif(left(btrim(p_note), 500), '');
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_approved is null then
    raise exception 'Choose approve or reject' using errcode = '22023';
  end if;
  if not p_approved and clean_note is null then
    raise exception 'Add a brief reason when rejecting a submission' using errcode = '22023';
  end if;
  update public.users
  set is_verified = p_approved,
      verification_status = case when p_approved then 'approved' else 'rejected' end,
      verification_review_note = case when p_approved then null else clean_note end,
      verification_reviewed_at = now(),
      verification_reviewer_id = (select auth.uid()),
      updated_at = now()
  where user_id = p_student_user_id and verification_status = 'pending';
  if not found then
    raise exception 'No pending submission was found for this student' using errcode = 'P0002';
  end if;
  insert into app_private.admin_audit_log (actor_id, action, target_type, target_id, details)
  values ((select auth.uid()), case when p_approved then 'verification_approved' else 'verification_rejected' end,
          'user', p_student_user_id, jsonb_build_object('note', clean_note));
end;
$$;
revoke all on function public.admin_review_verification(uuid, boolean, text) from public, anon;
grant execute on function public.admin_review_verification(uuid, boolean, text) to authenticated;

create function public.admin_active_listings()
returns table (
  id uuid, owner_id uuid, owner_name text, title text, location text,
  monthly_rent_ghs numeric, listing_type text, created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  return query
    select l.id, l.owner_id, u.full_name, l.title, l.location,
           l.monthly_rent_ghs, l.listing_type, l.created_at
    from public.listings l
    left join public.users u on u.user_id = l.owner_id
    where l.is_active
    order by l.created_at desc
    limit 250;
end;
$$;
revoke all on function public.admin_active_listings() from public, anon;
grant execute on function public.admin_active_listings() to authenticated;

create function public.admin_set_listing_active(
  p_listing_id uuid, p_is_active boolean, p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare clean_note text := nullif(left(btrim(p_note), 500), '');
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_is_active is null then
    raise exception 'Listing status is required' using errcode = '22023';
  end if;
  update public.listings set is_active = p_is_active, updated_at = now()
  where id = p_listing_id;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  insert into app_private.admin_audit_log (actor_id, action, target_type, target_id, details)
  values ((select auth.uid()), case when p_is_active then 'listing_restored' else 'listing_deactivated' end,
          'listing', p_listing_id, jsonb_build_object('note', clean_note));
end;
$$;
revoke all on function public.admin_set_listing_active(uuid, boolean, text) from public, anon;
grant execute on function public.admin_set_listing_active(uuid, boolean, text) to authenticated;

create function public.admin_user_directory(p_search text default null)
returns table (
  user_id uuid, full_name text, email text, university text,
  verification_status text, account_status text, moderation_note text,
  created_at timestamptz, is_admin boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare needle text := nullif(left(btrim(p_search), 120), '');
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  return query
    select u.user_id, u.full_name, a.email, u.university,
           u.verification_status, u.account_status, u.moderation_note,
           u.created_at,
           exists (select 1 from app_private.verification_reviewers r where r.user_id = u.user_id)
    from public.users u
    left join auth.users a on a.id = u.user_id
    where needle is null
       or u.full_name ilike '%' || needle || '%'
       or u.university ilike '%' || needle || '%'
       or a.email ilike '%' || needle || '%'
    order by u.created_at desc
    limit 200;
end;
$$;
revoke all on function public.admin_user_directory(text) from public, anon;
grant execute on function public.admin_user_directory(text) to authenticated;

create function public.admin_set_account_status(
  p_student_user_id uuid, p_status text, p_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare clean_note text := nullif(left(btrim(p_note), 500), '');
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_status not in ('active', 'suspended', 'banned') then
    raise exception 'Choose a valid account status' using errcode = '22023';
  end if;
  if p_student_user_id = (select auth.uid()) then
    raise exception 'Administrators cannot change their own account status' using errcode = '42501';
  end if;
  if exists (select 1 from app_private.verification_reviewers r where r.user_id = p_student_user_id) then
    raise exception 'An administrator account cannot be changed from this screen' using errcode = '42501';
  end if;
  if p_status <> 'active' and clean_note is null then
    raise exception 'Add a reason for suspending or banning this account' using errcode = '22023';
  end if;
  update public.users
  set account_status = p_status,
      moderation_note = case when p_status = 'active' then null else clean_note end,
      moderated_at = now(), moderated_by = (select auth.uid()), updated_at = now()
  where user_id = p_student_user_id;
  if not found then
    raise exception 'Student account not found' using errcode = 'P0002';
  end if;
  insert into app_private.admin_audit_log (actor_id, action, target_type, target_id, details)
  values ((select auth.uid()), 'account_' || p_status, 'user', p_student_user_id,
          jsonb_build_object('note', clean_note));
end;
$$;
revoke all on function public.admin_set_account_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_account_status(uuid, text, text) to authenticated;

create function public.admin_audit_log(p_limit integer default 100)
returns table (
  id bigint, actor_id uuid, actor_name text, action text,
  target_type text, target_id uuid, details jsonb, created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  return query
    select log.id, log.actor_id, u.full_name, log.action,
           log.target_type, log.target_id, log.details, log.created_at
    from app_private.admin_audit_log log
    left join public.users u on u.user_id = log.actor_id
    order by log.created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 200));
end;
$$;
revoke all on function public.admin_audit_log(integer) from public, anon;
grant execute on function public.admin_audit_log(integer) to authenticated;
