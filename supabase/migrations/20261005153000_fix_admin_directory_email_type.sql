create or replace function app_private._admin_user_directory(p_search text default null)
returns table (
  user_id uuid, full_name text, email text, university text,
  verification_status text, account_status text, moderation_note text,
  created_at timestamptz, is_admin boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  needle text := nullif(left(btrim(p_search), 120), '');
begin
  if not app_private.is_studentpad_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  return query
    select u.user_id, u.full_name, a.email::text, u.university,
           u.verification_status, u.account_status, u.moderation_note,
           u.created_at,
           exists (
             select 1 from app_private.verification_reviewers r
             where r.user_id = u.user_id
           )
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
revoke all on function app_private._admin_user_directory(text) from public, anon;
grant execute on function app_private._admin_user_directory(text) to authenticated;
