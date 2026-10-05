-- Keep privilege-elevated implementations outside PostgREST's exposed schema.
alter function public.admin_dashboard_summary() set schema app_private;
alter function app_private.admin_dashboard_summary() rename to _admin_dashboard_summary;
alter function public.admin_verification_queue() set schema app_private;
alter function app_private.admin_verification_queue() rename to _admin_verification_queue;
alter function public.admin_review_verification(uuid, boolean, text) set schema app_private;
alter function app_private.admin_review_verification(uuid, boolean, text) rename to _admin_review_verification;
alter function public.admin_active_listings() set schema app_private;
alter function app_private.admin_active_listings() rename to _admin_active_listings;
alter function public.admin_set_listing_active(uuid, boolean, text) set schema app_private;
alter function app_private.admin_set_listing_active(uuid, boolean, text) rename to _admin_set_listing_active;
alter function public.admin_user_directory(text) set schema app_private;
alter function app_private.admin_user_directory(text) rename to _admin_user_directory;
alter function public.admin_set_account_status(uuid, text, text) set schema app_private;
alter function app_private.admin_set_account_status(uuid, text, text) rename to _admin_set_account_status;
alter function public.admin_audit_log(integer) set schema app_private;
alter function app_private.admin_audit_log(integer) rename to _admin_audit_log;
alter function public.my_account_access_state() set schema app_private;
alter function app_private.my_account_access_state() rename to _my_account_access_state;

revoke all on function app_private._admin_dashboard_summary() from public, anon;
grant execute on function app_private._admin_dashboard_summary() to authenticated;
revoke all on function app_private._admin_verification_queue() from public, anon;
grant execute on function app_private._admin_verification_queue() to authenticated;
revoke all on function app_private._admin_review_verification(uuid, boolean, text) from public, anon;
grant execute on function app_private._admin_review_verification(uuid, boolean, text) to authenticated;
revoke all on function app_private._admin_active_listings() from public, anon;
grant execute on function app_private._admin_active_listings() to authenticated;
revoke all on function app_private._admin_set_listing_active(uuid, boolean, text) from public, anon;
grant execute on function app_private._admin_set_listing_active(uuid, boolean, text) to authenticated;
revoke all on function app_private._admin_user_directory(text) from public, anon;
grant execute on function app_private._admin_user_directory(text) to authenticated;
revoke all on function app_private._admin_set_account_status(uuid, text, text) from public, anon;
grant execute on function app_private._admin_set_account_status(uuid, text, text) to authenticated;
revoke all on function app_private._admin_audit_log(integer) from public, anon;
grant execute on function app_private._admin_audit_log(integer) to authenticated;
revoke all on function app_private._my_account_access_state() from public, anon;
grant execute on function app_private._my_account_access_state() to authenticated;

create function public.admin_dashboard_summary()
returns jsonb language sql security invoker set search_path = ''
as $$ select app_private._admin_dashboard_summary(); $$;
revoke all on function public.admin_dashboard_summary() from public, anon;
grant execute on function public.admin_dashboard_summary() to authenticated;

create function public.admin_verification_queue()
returns table (user_id uuid, full_name text, university text, student_id_url text, submitted_at timestamptz)
language sql security invoker set search_path = ''
as $$ select * from app_private._admin_verification_queue(); $$;
revoke all on function public.admin_verification_queue() from public, anon;
grant execute on function public.admin_verification_queue() to authenticated;

create function public.admin_review_verification(
  p_student_user_id uuid, p_approved boolean, p_note text default null
)
returns void language sql security invoker set search_path = ''
as $$ select app_private._admin_review_verification(p_student_user_id, p_approved, p_note); $$;
revoke all on function public.admin_review_verification(uuid, boolean, text) from public, anon;
grant execute on function public.admin_review_verification(uuid, boolean, text) to authenticated;

create function public.admin_active_listings()
returns table (id uuid, owner_id uuid, owner_name text, title text, location text,
  monthly_rent_ghs numeric, listing_type text, created_at timestamptz)
language sql security invoker set search_path = ''
as $$ select * from app_private._admin_active_listings(); $$;
revoke all on function public.admin_active_listings() from public, anon;
grant execute on function public.admin_active_listings() to authenticated;

create function public.admin_set_listing_active(
  p_listing_id uuid, p_is_active boolean, p_note text default null
)
returns void language sql security invoker set search_path = ''
as $$ select app_private._admin_set_listing_active(p_listing_id, p_is_active, p_note); $$;
revoke all on function public.admin_set_listing_active(uuid, boolean, text) from public, anon;
grant execute on function public.admin_set_listing_active(uuid, boolean, text) to authenticated;

create function public.admin_user_directory(p_search text default null)
returns table (user_id uuid, full_name text, email text, university text,
  verification_status text, account_status text, moderation_note text,
  created_at timestamptz, is_admin boolean)
language sql security invoker set search_path = ''
as $$ select * from app_private._admin_user_directory(p_search); $$;
revoke all on function public.admin_user_directory(text) from public, anon;
grant execute on function public.admin_user_directory(text) to authenticated;

create function public.admin_set_account_status(
  p_student_user_id uuid, p_status text, p_note text
)
returns void language sql security invoker set search_path = ''
as $$ select app_private._admin_set_account_status(p_student_user_id, p_status, p_note); $$;
revoke all on function public.admin_set_account_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_account_status(uuid, text, text) to authenticated;

create function public.admin_audit_log(p_limit integer default 100)
returns table (id bigint, actor_id uuid, actor_name text, action text,
  target_type text, target_id uuid, details jsonb, created_at timestamptz)
language sql security invoker set search_path = ''
as $$ select * from app_private._admin_audit_log(p_limit); $$;
revoke all on function public.admin_audit_log(integer) from public, anon;
grant execute on function public.admin_audit_log(integer) to authenticated;

create function public.my_account_access_state()
returns table (account_status text, moderation_note text)
language sql security invoker set search_path = ''
as $$ select * from app_private._my_account_access_state(); $$;
revoke all on function public.my_account_access_state() from public, anon;
grant execute on function public.my_account_access_state() to authenticated;
