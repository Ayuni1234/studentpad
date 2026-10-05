-- PostgREST's ON CONFLICT upsert requires relation-level INSERT and UPDATE
-- privileges. RLS continues to enforce that students may only create and
-- update their own profile rows.
grant insert, update on table public.profiles to authenticated;
