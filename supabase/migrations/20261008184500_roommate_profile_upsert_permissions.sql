-- PostgREST upserts require relation-level INSERT and UPDATE privileges.
-- RLS still limits inserts and updates to a verified student's own row.
grant insert, update on table public.roommate_profiles to authenticated;
