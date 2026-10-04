-- Reviewer controlled student verification. Student ID images remain private.
alter table public.users
  add column verification_status text not null default 'not_submitted'
    check (verification_status in ('not_submitted', 'pending', 'approved', 'rejected')),
  add column verification_reviewed_at timestamptz,
  add column verification_reviewer_id uuid references auth.users(id) on delete set null;

update public.users
set verification_status = case
  when is_verified then 'approved'
  when student_id_url is not null then 'pending'
  else 'not_submitted'
end;

create index users_pending_verification_idx
  on public.users (created_at)
  where verification_status = 'pending';

create table app_private.verification_reviewers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
comment on table app_private.verification_reviewers is
  'Provision reviewer UUIDs through the Supabase SQL editor; never expose this table through the API.';
alter table app_private.verification_reviewers enable row level security;
revoke all on table app_private.verification_reviewers from public, anon, authenticated;

create function app_private.is_studentpad_verification_reviewer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1 from app_private.verification_reviewers r
      where r.user_id = (select auth.uid())
    );
$$;
revoke all on function app_private.is_studentpad_verification_reviewer() from public, anon;
grant execute on function app_private.is_studentpad_verification_reviewer() to authenticated;

-- Public-schema wrapper so the Flutter client can show reviewer navigation.
create function public.is_studentpad_verification_reviewer()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select app_private.is_studentpad_verification_reviewer(); $$;
revoke all on function public.is_studentpad_verification_reviewer() from public, anon;
grant execute on function public.is_studentpad_verification_reviewer() to authenticated;

-- Submission is allowed only for the signed-in student's own uploaded object.
revoke insert (student_id_url) on table public.users from authenticated;
revoke update (student_id_url) on table public.users from authenticated;
create function public.my_student_verification_state()
returns table (
  student_id_path text,
  verification_status text,
  is_verified boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select u.student_id_url, u.verification_status, u.is_verified
  from public.users u
  where u.user_id = (select auth.uid());
$$;
revoke all on function public.my_student_verification_state() from public, anon;
grant execute on function public.my_student_verification_state() to authenticated;

create function public.submit_student_verification(p_student_id_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_student_id_path is null
     or split_part(p_student_id_path, '/', 1) <> v_user_id::text
     or char_length(p_student_id_path) > 512 then
    raise exception 'Invalid student ID path' using errcode = '22023';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'student-verification'
      and o.name = p_student_id_path
  ) then
    raise exception 'Uploaded student ID image was not found' using errcode = '22023';
  end if;

  update public.users
  set student_id_url = p_student_id_path,
      verification_status = 'pending',
      verification_reviewed_at = null,
      verification_reviewer_id = null,
      updated_at = now()
  where user_id = v_user_id and not is_verified;
  if not found then
    raise exception 'Account is already verified or has no profile' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.submit_student_verification(text) from public, anon;
grant execute on function public.submit_student_verification(text) to authenticated;

create function public.pending_student_verifications()
returns table (
  user_id uuid,
  full_name text,
  university text,
  student_id_url text,
  submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.is_studentpad_verification_reviewer() then
    raise exception 'Verification reviewer access required' using errcode = '42501';
  end if;
  return query
    select u.user_id, u.full_name, u.university, u.student_id_url, u.updated_at
    from public.users u
    where u.verification_status = 'pending'
    order by u.updated_at asc;
end;
$$;
revoke all on function public.pending_student_verifications() from public, anon;
grant execute on function public.pending_student_verifications() to authenticated;

create function public.review_student_verification(
  p_student_user_id uuid,
  p_approved boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.is_studentpad_verification_reviewer() then
    raise exception 'Verification reviewer access required' using errcode = '42501';
  end if;
  update public.users
  set is_verified = p_approved,
      verification_status = case when p_approved then 'approved' else 'rejected' end,
      verification_reviewed_at = now(),
      verification_reviewer_id = (select auth.uid()),
      updated_at = now()
  where user_id = p_student_user_id
    and verification_status = 'pending';
  if not found then
    raise exception 'No pending submission was found for this student' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.review_student_verification(uuid, boolean) from public, anon;
grant execute on function public.review_student_verification(uuid, boolean) to authenticated;

-- Reviewers can read the private bucket through authenticated storage APIs.
drop policy if exists "Students read their own verification image" on storage.objects;
create policy "Students and reviewers read verification images"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'student-verification'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or app_private.is_studentpad_verification_reviewer()
    )
  );
